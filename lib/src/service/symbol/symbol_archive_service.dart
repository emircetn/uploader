import 'dart:io';

import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/archived_build.dart';
import 'package:uploader/src/util/build_parameters.dart';

/// Compresses what a build leaves behind for crash reporters out of
/// `build/`, which the next build or a `flutter clean` overwrites, into a
/// folder per run:
///
/// ```
/// <archiveRoot>/<appName>/<version+build>/<runId>/<platform>-<target>/
///   mapping.txt.zip, native-libs.zip, dSYMs.zip, ...
///   manifest.json
/// ```
class SymbolArchiveService {
  final String archiveRoot;
  final String appName;
  final String projectRoot;

  SymbolArchiveService({
    required this.archiveRoot,
    required this.appName,
    required this.projectRoot,
  });

  String get appRoot => "$archiveRoot/$appName";

  static const _iosDsymsPath = "build/ios/archive/Runner.xcarchive/dSYMs";

  /// The files the last release build of [platform] left in the project, by
  /// kind. A kind the build did not produce is left out: a project without
  /// R8 has no mapping file, one without `--split-debug-info` no Dart
  /// symbols. A folder holding no files counts as not produced.
  ///
  /// Android paths follow the variant `--flavor` selects, such as
  /// `mapping/prodRelease/` for `--flavor prod`.
  Map<SymbolKind, String> collect(
    AppPlatform platform, {
    List<String> buildParameters = const [],
  }) {
    final found = <SymbolKind, String>{};

    void addFirst(SymbolKind kind, Iterable<String> candidates) {
      for (final candidate in candidates) {
        final path = _absolute(candidate);
        final type = FileSystemEntity.typeSync(path);
        if (type == FileSystemEntityType.file ||
            type == FileSystemEntityType.directory && _hasFiles(path)) {
          found[kind] = path;
          return;
        }
      }
    }

    if (platform == AppPlatform.android) {
      final variant = BuildParameters.androidReleaseVariant(buildParameters);
      final task = variant.capitalized;
      addFirst(SymbolKind.mapping, [
        "build/app/outputs/mapping/$variant/mapping.txt",
      ]);
      addFirst(SymbolKind.crashlyticsMappingId, [
        "build/app/generated/res/injectCrashlyticsMappingFileId$task/values/"
            "com_google_firebase_crashlytics_mappingfileid.xml",
        "build/app/generated/crashlytics/res/$variant/values/"
            "com_google_firebase_crashlytics_mappingfileid.xml",
      ]);
      addFirst(SymbolKind.nativeLibs, [
        "build/app/intermediates/merged_native_libs/$variant/"
            "merge${task}NativeLibs/out/lib",
        "build/app/intermediates/merged_native_libs/$variant/out/lib",
      ]);
    } else if (platform == AppPlatform.ios) {
      addFirst(SymbolKind.dsyms, [_iosDsymsPath]);
    }

    final splitDebugInfo = BuildParameters.splitDebugInfoPath(buildParameters);
    if (splitDebugInfo != null &&
        dartSymbolFiles(_absolute(splitDebugInfo), platform).isNotEmpty) {
      found[SymbolKind.dartSymbols] = _absolute(splitDebugInfo);
    }

    return found;
  }

  /// The `app.<platform>-<arch>.symbols` files `--split-debug-info` wrote
  /// for [platform]. The folder is usually shared by both platforms, and
  /// with parallel builds the other one may still be writing to it.
  static List<String> dartSymbolFiles(String folder, AppPlatform platform) {
    final directory = Directory(folder);
    if (!directory.existsSync()) return const [];
    final prefix = "app.${platform.value}-";
    return [
      for (final entity in directory.listSync())
        if (entity is File)
          if (entity.uri.pathSegments.last case final name
              when name.startsWith(prefix) && name.endsWith(".symbols"))
            name,
    ]..sort();
  }

  /// The build id the New Relic Gradle plugin compiled into the last
  /// Android release build of the variant [buildParameters] select, or null
  /// without the plugin.
  String? readNewRelicBuildId({List<String> buildParameters = const []}) {
    final variant = BuildParameters.androidReleaseVariant(buildParameters);
    final folder = Directory(
      _absolute(
        "build/app/generated/java/newrelicConfig${variant.capitalized}",
      ),
    );
    if (!folder.existsSync()) return null;

    final pattern = RegExp(r'BUILD_ID\s*=\s*"([^"]+)"');
    for (final entity in folder.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith("NewRelicConfig.java")) {
        continue;
      }
      final match = pattern.firstMatch(entity.readAsStringSync());
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Compresses each of [files] into its own zip in a new folder for this
  /// build and writes the manifest. Throws when they cannot be archived,
  /// since a run that continued would lose them with the next build.
  ///
  /// A folder is zipped from inside, so `dSYMs.zip` holds the `.dSYM`
  /// bundles at its root, the layout New Relic takes as it is. Nothing is
  /// copied uncompressed first.
  Future<ArchivedBuild> archive({
    required String runId,
    required String version,
    required String? buildNumber,
    required AppPlatform platform,
    required BuildTarget target,
    required Map<SymbolKind, String> files,
    String? firebaseAppId,
    String? newRelicBuildId,
    String? gitCommit,
    DateTime? now,
  }) async {
    final directory = Directory(
      "$appRoot/${ArchivedBuild.fullVersionOf(version, buildNumber)}/$runId/"
      "${platform.value}-${target.name}",
    );
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);

    final staging = Directory.systemTemp.createTempSync("uploader_symbols_");
    try {
      for (final MapEntry(key: kind, value: source) in files.entries) {
        final zip = "${directory.path}/${kind.zipName}";
        if (kind == SymbolKind.dartSymbols) {
          await _zip(
            zip,
            dartSymbolFiles(source, platform),
            workingDirectory: source,
          );
        } else if (FileSystemEntity.isDirectorySync(source)) {
          await _zip(zip, ["-r", "."], workingDirectory: source);
        } else {
          Link("${staging.path}/${kind.archivedName}").createSync(source);
          await _zip(zip, [kind.archivedName], workingDirectory: staging.path);
        }
      }
    } catch (_) {
      directory.deleteSync(recursive: true);
      rethrow;
    } finally {
      staging.deleteSync(recursive: true);
    }

    final build = ArchivedBuild(
      directory: directory,
      appName: appName,
      version: version,
      buildNumber: buildNumber,
      platform: platform,
      target: target,
      createdAt: now ?? DateTime.now(),
      gitCommit: gitCommit,
      firebaseAppId: firebaseAppId,
      newRelicBuildId: newRelicBuildId,
      files: {for (final kind in files.keys) kind: kind.zipName},
    );
    build.save();
    return build;
  }

  static Future<void> _zip(
    String zip,
    List<String> entries, {
    required String workingDirectory,
  }) async {
    final result = await Process.run("zip", [
      "-q",
      zip,
      ...entries,
    ], workingDirectory: workingDirectory);
    if (result.exitCode != 0) {
      throw ProcessException(
        "zip",
        [zip],
        "${result.stderr}".trim(),
        result.exitCode,
      );
    }
  }

  /// Extracts [kinds] of [build] into a temporary folder and points
  /// [ArchivedBuild.pathOf] at them. Call [release] when done.
  Future<void> extract(ArchivedBuild build, Iterable<SymbolKind> kinds) async {
    final folder = Directory.systemTemp.createTempSync("uploader_symbols_");
    final extracted = <SymbolKind>{};
    try {
      for (final kind in kinds) {
        final zip = build.zipOf(kind);
        if (zip == null) continue;
        final destination = kind.isFolder
            ? "${folder.path}/${kind.archivedName}"
            : folder.path;
        final result = await Process.run("unzip", [
          "-q",
          zip,
          "-d",
          destination,
        ]);
        if (result.exitCode != 0) {
          throw ProcessException(
            "unzip",
            [zip],
            "${result.stderr}".trim(),
            result.exitCode,
          );
        }
        extracted.add(kind);
      }
    } catch (_) {
      folder.deleteSync(recursive: true);
      rethrow;
    }
    build.contentDirectory = folder;
    build.extractedKinds = extracted;
  }

  /// Removes what [extract] unpacked.
  void release(ArchivedBuild build) {
    final folder = build.contentDirectory;
    build.contentDirectory = null;
    build.extractedKinds = const {};
    if (folder != null && folder.existsSync()) {
      folder.deleteSync(recursive: true);
    }
  }

  static bool _hasFiles(String folder) => Directory(folder)
      .listSync(recursive: true, followLinks: true)
      .any((entity) => entity is File);

  /// Every archived build of this app, oldest run first.
  List<ArchivedBuild> loadAll() {
    final builds = <ArchivedBuild>[];
    for (final run in _runFolders()) {
      final folders = run.listSync()..sort((a, b) => a.path.compareTo(b.path));
      for (final entity in folders) {
        if (entity is! Directory) continue;
        final build = ArchivedBuild.load(entity);
        if (build != null) builds.add(build);
      }
    }
    return builds;
  }

  /// Removes the oldest runs beyond [keepLast]. A run with an upload still
  /// pending outlives them, but only the newest [keepLast] such runs do: an
  /// upload that can never go through, such as one whose token is only set
  /// on CI, would otherwise keep every local run forever.
  ///
  /// Returns the folders removed, and among them those that still had an
  /// upload pending.
  ({List<String> removed, List<String> removedPending}) prune(int keepLast) {
    if (keepLast <= 0) return (removed: const [], removedPending: const []);

    final runs = _runFolders().reversed.toList();
    final removed = <String>[];
    final removedPending = <String>[];
    var keptPending = 0;
    for (final run in runs.skip(keepLast)) {
      final hasPending = run.listSync().whereType<Directory>().any(
        (folder) => ArchivedBuild.load(folder)?.hasPendingUploads ?? false,
      );
      if (hasPending && keptPending < keepLast) {
        keptPending++;
        continue;
      }

      run.deleteSync(recursive: true);
      removed.add(run.path);
      if (hasPending) removedPending.add(run.path);

      final versionFolder = run.parent;
      if (versionFolder.existsSync() && versionFolder.listSync().isEmpty) {
        versionFolder.deleteSync();
      }
    }
    return (removed: removed, removedPending: removedPending);
  }

  /// Run folders across every version, oldest first. Run ids are
  /// timestamps, so their names sort by time.
  List<Directory> _runFolders() {
    final root = Directory(appRoot);
    if (!root.existsSync()) return const [];

    final runs = [
      for (final version in root.listSync().whereType<Directory>())
        ...version.listSync().whereType<Directory>(),
    ];
    runs.sort((a, b) => _name(a).compareTo(_name(b)));
    return runs;
  }

  static String _name(Directory directory) =>
      directory.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);

  String _absolute(String path) =>
      path.startsWith("/") ? path : "$projectRoot/$path";

  /// A run id that sorts by time: `20261102-143005`.
  static String runIdFor(DateTime time) {
    String two(int value) => value.toString().padLeft(2, "0");
    return "${time.year}${two(time.month)}${two(time.day)}-"
        "${two(time.hour)}${two(time.minute)}${two(time.second)}";
  }
}
