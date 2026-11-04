import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/secret_helper.dart';
import 'package:uploader/src/model/archived_build.dart';
import 'package:uploader/src/model/symbols_config.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/service/symbol/symbol_destination.dart';
import 'package:uploader/src/util/printer.dart';
import 'package:uploader/src/util/retry_utils.dart';

/// Sends the mapping file and dSYMs to New Relic's symbol endpoint, the same
/// one its Gradle plugin and Xcode script post to.
class NewRelicDestination implements SymbolDestination {
  final NewRelicSymbolsConfig config;
  final SecretHelper secrets;
  final ProcessService processService;
  final int retryCount;
  final Dio dio;

  NewRelicDestination({
    required this.config,
    required this.secrets,
    required this.processService,
    required this.retryCount,
    Dio? dio,
  }) : dio = dio ?? Dio(BaseOptions(connectTimeout: connectTimeout));

  static const connectTimeout = Duration(seconds: 30);

  /// How long New Relic may take to answer once a file is sent.
  static const receiveTimeout = Duration(minutes: 5);

  /// The time a file of [bytes] may take to send: at least 256 KB/s, plus a
  /// minute. A stalled upload fails and is retried instead of holding the
  /// run forever, and a large one on a slow line is not cut short.
  static Duration sendTimeoutFor(int bytes) =>
      Duration(seconds: 60 + bytes ~/ (256 * 1024));

  /// The line the New Relic Gradle plugin tags a mapping file with. New
  /// Relic matches a crash to a mapping file by it, so an untagged file is
  /// accepted but never used.
  static const buildIdTag = "# NR_BUILD_ID -> ";

  /// The largest zip New Relic takes.
  static const maxZipBytes = 600 * 1000 * 1000;

  /// When the archived zip is larger than [maxZipBytes], dSYMs are batched
  /// under this many bytes before compression.
  static const maxBatchBytes = 500 * 1000 * 1000;

  @override
  String get name => "newRelic";

  @override
  bool supports(AppPlatform platform) => config.tokenFor(platform) != null;

  /// The archived `dSYMs.zip` goes as it is when New Relic takes its size;
  /// only a larger one is extracted to be batched.
  @override
  Set<SymbolKind> kindsNeeded(ArchivedBuild build) {
    if (build.platform != AppPlatform.ios) {
      return {
        if (build.files.containsKey(SymbolKind.mapping)) SymbolKind.mapping,
      };
    }
    final zip = build.zipOf(SymbolKind.dsyms);
    if (zip == null || File(zip).lengthSync() <= maxZipBytes) return const {};
    return {SymbolKind.dsyms};
  }

  @override
  Future<UploadOutcome> upload(ArchivedBuild build) async {
    return switch (build.platform) {
      AppPlatform.ios => _uploadDsyms(build),
      _ => _uploadMapping(build),
    };
  }

  Future<UploadOutcome> _uploadMapping(ArchivedBuild build) async {
    final mapping = build.pathOf(SymbolKind.mapping);
    if (mapping == null) {
      return const UploadOutcome.skipped("no mapping.txt in this build");
    }

    final token = _token(AppPlatform.android);
    if (token == null) return _missingToken(AppPlatform.android);

    final hasTag = hasBuildIdTag(File(mapping));
    final buildId = build.newRelicBuildId;
    if (!hasTag && buildId == null) {
      return const UploadOutcome.skipped(
        "the New Relic build id was not found, so the mapping file could not "
        "be matched to the build; is the New Relic Gradle plugin applied?",
      );
    }

    Directory? temp;
    try {
      var file = File(mapping);
      if (!hasTag) {
        temp = Directory.systemTemp.createTempSync("uploader_newrelic_");
        file = tagMapping(file, buildId!, temp);
      }

      final isSuccess = await RetryUtils.run(
        () => _post(
          platform: build.platform,
          token: token,
          field: "upload",
          file: file,
        ),
        retryCount: retryCount,
        label: "[android] newRelic mapping upload",
      );
      return isSuccess
          ? const UploadOutcome.done("mapping file")
          : const UploadOutcome.pending("mapping file upload failed");
    } finally {
      temp?.deleteSync(recursive: true);
    }
  }

  Future<UploadOutcome> _uploadDsyms(ArchivedBuild build) async {
    final archivedZip = build.zipOf(SymbolKind.dsyms);
    if (archivedZip == null) {
      return const UploadOutcome.skipped("no dSYMs in this build");
    }

    final token = _token(AppPlatform.ios);
    if (token == null) return _missingToken(AppPlatform.ios);

    // The archive holds the bundles at the zip's root, as New Relic takes
    // them, so a zip within the limit goes as it is.
    final zipFile = File(archivedZip);
    if (zipFile.lengthSync() <= maxZipBytes) {
      final isSuccess = await RetryUtils.run(
        () => _post(
          platform: AppPlatform.ios,
          token: token,
          field: "dsym",
          file: zipFile,
        ),
        retryCount: retryCount,
        label: "[ios] newRelic dSYM upload",
      );
      return isSuccess
          ? const UploadOutcome.done("the archived dSYMs.zip")
          : const UploadOutcome.pending("dSYM upload failed");
    }

    final dsyms = build.pathOf(SymbolKind.dsyms)!;

    final bundles = [
      for (final entity in Directory(dsyms).listSync())
        if (entity is Directory && entity.path.endsWith(".dSYM"))
          (
            name: entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
            size: directorySize(entity),
          ),
    ];
    if (bundles.isEmpty) {
      return const UploadOutcome.skipped("the dSYMs folder is empty");
    }

    final temp = Directory.systemTemp.createTempSync("uploader_newrelic_");
    try {
      final batches = batchBySize(bundles, maxBatchBytes);
      for (final (index, batch) in batches.indexed) {
        final zip = "${temp.path}/dsyms_${index + 1}.zip";
        final isZipped = await processService.run(
          platform: AppPlatform.ios,
          executable: "zip",
          arguments: ["-r", "-q", zip, ...batch],
          workingDirectory: dsyms,
        );
        if (!isZipped) {
          return UploadOutcome.pending(
            "dSYMs could not be zipped (batch ${index + 1}/${batches.length})",
          );
        }

        final isSuccess = await RetryUtils.run(
          () => _post(
            platform: AppPlatform.ios,
            token: token,
            field: "dsym",
            file: File(zip),
          ),
          retryCount: retryCount,
          label:
              "[ios] newRelic dSYM upload "
              "(batch ${index + 1}/${batches.length})",
        );
        if (!isSuccess) {
          return UploadOutcome.pending(
            "dSYM upload failed (batch ${index + 1}/${batches.length})",
          );
        }
        File(zip).deleteSync();
      }
      return UploadOutcome.done(
        "${bundles.length} dSYMs in ${batches.length} upload(s)",
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  }

  String? _token(AppPlatform platform) {
    final source = config.tokenFor(platform);
    return source == null ? null : secrets.resolve(source);
  }

  UploadOutcome _missingToken(AppPlatform platform) => UploadOutcome.pending(
    "the ${platform.value} token was not found: "
    "${config.tokenFor(platform)!.description} is not set",
  );

  Future<bool> _post({
    required AppPlatform platform,
    required String token,
    required String field,
    required File file,
  }) async {
    try {
      final response = await dio.postUri<dynamic>(
        config.region.symbolUri,
        data: FormData.fromMap({
          field: await MultipartFile.fromFile(file.path),
        }),
        options: Options(
          headers: {"X-APP-LICENSE-KEY": token},
          sendTimeout: sendTimeoutFor(file.lengthSync()),
          receiveTimeout: receiveTimeout,
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) return true;

      Printer.warning(
        "[${platform.value}] New Relic answered HTTP $status: "
        "${_shorten("${response.data}")}",
      );
      return false;
    } on DioException catch (e) {
      Printer.warning(
        "[${platform.value}] New Relic upload failed: ${e.message ?? e.type}",
      );
      return false;
    }
  }

  static String _shorten(String text) =>
      text.length > 300 ? "${text.substring(0, 300)}..." : text;

  /// Whether the Gradle plugin already tagged [mapping]. The tag is a
  /// single line, so only the ends of a file that can run to hundreds of MB
  /// are read.
  static bool hasBuildIdTag(File mapping) {
    const window = 64 * 1024;
    final length = mapping.lengthSync();
    final handle = mapping.openSync();
    try {
      bool contains(int start) {
        handle.setPositionSync(start);
        final bytes = handle.readSync(window);
        return String.fromCharCodes(bytes).contains(buildIdTag);
      }

      return contains(0) || (length > window && contains(length - window));
    } finally {
      handle.closeSync();
    }
  }

  /// A copy of [mapping] in [folder] with [buildId] appended the way the
  /// Gradle plugin writes it. The archived file stays as R8 wrote it.
  static File tagMapping(File mapping, String buildId, Directory folder) {
    final tagged = File("${folder.path}/mapping.txt");
    mapping.copySync(tagged.path);

    final endsWithNewline = () {
      final handle = tagged.openSync();
      try {
        final length = handle.lengthSync();
        if (length == 0) return true;
        handle.setPositionSync(length - 1);
        return handle.readByteSync() == 0x0A;
      } finally {
        handle.closeSync();
      }
    }();

    tagged.writeAsBytesSync(
      Uint8List.fromList(
        "${endsWithNewline ? "" : "\n"}$buildIdTag$buildId\n".codeUnits,
      ),
      mode: FileMode.append,
    );
    return tagged;
  }

  static int directorySize(Directory directory) {
    var size = 0;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File) size += entity.lengthSync();
    }
    return size;
  }

  /// Groups [items] in order into batches no larger than [maxBytes]; an item
  /// larger than that gets a batch of its own.
  static List<List<String>> batchBySize(
    List<({String name, int size})> items,
    int maxBytes,
  ) {
    final batches = <List<String>>[];
    var current = <String>[];
    var currentSize = 0;
    for (final item in items) {
      if (current.isNotEmpty && currentSize + item.size > maxBytes) {
        batches.add(current);
        current = [];
        currentSize = 0;
      }
      current.add(item.name);
      currentSize += item.size;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }
}
