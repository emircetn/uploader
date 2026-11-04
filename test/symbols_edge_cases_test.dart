import 'dart:io';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/secret_helper.dart';
import 'package:uploader/src/model/app_detail.dart';
import 'package:uploader/src/model/archived_build.dart';
import 'package:uploader/src/model/pubspec_parameters.dart';
import 'package:uploader/src/model/symbols_config.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/service/symbol/crashlytics_destination.dart';
import 'package:uploader/src/service/symbol/new_relic_destination.dart';
import 'package:uploader/src/service/symbol/symbol_archive_service.dart';
import 'package:uploader/src/service/symbol/symbol_destination.dart';
import 'package:uploader/src/service/symbol/symbol_service.dart';
import 'package:yaml/yaml.dart';

void write(String path, String content) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// Records the commands it is asked to run instead of running them.
class RecordingProcessService extends ProcessService {
  final commands = <List<String>>[];
  final bool succeeds;

  RecordingProcessService({this.succeeds = true});

  @override
  Future<bool> run({
    required AppPlatform platform,
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
  }) async {
    commands.add([executable, ...arguments]);
    return succeeds;
  }
}

/// Answers every request locally and keeps what was sent.
class RecordedRequest {
  final Uri uri;
  final Map<String, dynamic> headers;
  final String field;
  final String filename;
  final List<int> bytes;

  RecordedRequest(
    this.uri,
    this.headers,
    this.field,
    this.filename,
    this.bytes,
  );
}

Dio fakeDio(List<RecordedRequest> requests, {int status = 200}) =>
    Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final part = (options.data as FormData).files.single;
            final bytes = await part.value.finalize().expand((c) => c).toList();
            requests.add(
              RecordedRequest(
                options.uri,
                options.headers,
                part.key,
                part.value.filename!,
                bytes,
              ),
            );
            handler.resolve(
              Response(requestOptions: options, statusCode: status, data: ""),
            );
          },
        ),
      );

void main() {
  late Directory temp;
  late String project;
  late String archive;

  setUp(() {
    temp = Directory.systemTemp.createTempSync("uploader_symbols_edge_");
    project = "${temp.path}/project";
    archive = "${temp.path}/archive";
    Directory(project).createSync();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  SymbolArchiveService archiveService() => SymbolArchiveService(
    archiveRoot: archive,
    appName: "app",
    projectRoot: project,
  );

  Future<ArchivedBuild> archiveFrom(
    AppPlatform platform, {
    List<String> buildParameters = const [],
    String? firebaseAppId = "1:2:${"x"}:3",
    String? newRelicBuildId,
    String runId = "20261102-120000",
  }) => archiveService().archive(
    runId: runId,
    version: "1.0.0",
    buildNumber: "1",
    platform: platform,
    target: BuildTarget.store,
    files: archiveService().collect(platform, buildParameters: buildParameters),
    firebaseAppId: firebaseAppId,
    newRelicBuildId: newRelicBuildId,
  );

  Future<List<String>> zipEntries(String zip) async {
    final listing = await Process.run("unzip", ["-Z1", zip]);
    return "${listing.stdout}".trim().split("\n");
  }

  group('collect', () {
    test('an empty folder counts as not produced', () {
      Directory(
        "$project/build/ios/archive/Runner.xcarchive/dSYMs",
      ).createSync(recursive: true);
      expect(archiveService().collect(AppPlatform.ios), isEmpty);
    });

    test('an empty dSYMs folder does not stop the run', () async {
      Directory(
        "$project/build/ios/archive/Runner.xcarchive/dSYMs",
      ).createSync(recursive: true);
      final service = SymbolService(
        config: SymbolsConfig(archivePath: archive),
        appDetail: AppDetail(appName: "app", buildVersion: "1.0.0"),
        retryCount: 0,
        projectRoot: project,
        environment: const {},
      );
      expect(
        await service.handleBuild(
          platform: AppPlatform.ios,
          target: BuildTarget.store,
          buildParameters: const [],
        ),
        isTrue,
      );
      expect(Directory(archive).existsSync(), isFalse);
    });

    test('a flavor reads its own variant', () {
      write("$project/build/app/outputs/mapping/release/mapping.txt", "old");
      write(
        "$project/build/app/outputs/mapping/prodRelease/mapping.txt",
        "prod",
      );
      write(
        "$project/build/app/intermediates/merged_native_libs/prodRelease/"
            "mergeProdReleaseNativeLibs/out/lib/arm64-v8a/libapp.so",
        "elf",
      );
      write(
        "$project/build/app/generated/java/newrelicConfigProdRelease/"
            "NewRelicConfig.java",
        'static final String BUILD_ID = "prod-id";',
      );

      final files = archiveService().collect(
        AppPlatform.android,
        buildParameters: const ["--flavor", "prod"],
      );
      expect(File(files[SymbolKind.mapping]!).readAsStringSync(), "prod");
      expect(files.keys, contains(SymbolKind.nativeLibs));
      expect(
        archiveService().readNewRelicBuildId(
          buildParameters: const ["--flavor=prod"],
        ),
        "prod-id",
      );
      expect(archiveService().readNewRelicBuildId(), isNull);
    });

    test('Dart symbols are archived per platform', () async {
      write("$project/build/symbols/app.android-arm64.symbols", "a");
      write("$project/build/symbols/app.android-arm.symbols", "a");
      write("$project/build/symbols/app.ios-arm64.symbols", "i");
      const parameters = ["--split-debug-info=build/symbols"];

      final android = await archiveFrom(
        AppPlatform.android,
        buildParameters: parameters,
      );
      expect(await zipEntries(android.zipOf(SymbolKind.dartSymbols)!), [
        "app.android-arm.symbols",
        "app.android-arm64.symbols",
      ]);

      File("$project/build/symbols/app.ios-arm64.symbols").deleteSync();
      expect(
        archiveService().collect(AppPlatform.ios, buildParameters: parameters),
        isNot(contains(SymbolKind.dartSymbols)),
      );
    });
  });

  group('CrashlyticsDestination', () {
    Future<(UploadOutcome, List<List<String>>)> uploadTo(
      ArchivedBuild build, {
      bool succeeds = true,
    }) async {
      final process = RecordingProcessService(succeeds: succeeds);
      final destination = CrashlyticsDestination(
        processService: process,
        projectRoot: project,
        retryCount: 0,
      );
      await archiveService().extract(build, destination.kindsNeeded(build));
      try {
        return (await destination.upload(build), process.commands);
      } finally {
        archiveService().release(build);
      }
    }

    void writeAndroid({bool withMappingId = true}) {
      write("$project/build/app/outputs/mapping/release/mapping.txt", "m");
      if (withMappingId) {
        write(
          "$project/build/app/generated/res/"
              "injectCrashlyticsMappingFileIdRelease/values/"
              "com_google_firebase_crashlytics_mappingfileid.xml",
          "<resources/>",
        );
      }
      write(
        "$project/build/app/intermediates/merged_native_libs/release/"
            "mergeReleaseNativeLibs/out/lib/arm64-v8a/libapp.so",
        "elf",
      );
    }

    test(
      'Android sends the mapping file and native and Dart symbols',
      () async {
        writeAndroid();
        write("$project/build/symbols/app.android-arm64.symbols", "a");
        final build = await archiveFrom(
          AppPlatform.android,
          buildParameters: const ["--split-debug-info=build/symbols"],
          firebaseAppId: "1:2:android:3",
        );

        final (outcome, commands) = await uploadTo(build);

        expect(outcome.status, UploadStatus.done);
        expect(commands.map((c) => c.take(3).toList()), [
          ["firebase", "crashlytics:mappingfile:upload", "--app=1:2:android:3"],
          ["firebase", "crashlytics:symbols:upload", "--app=1:2:android:3"],
          ["firebase", "crashlytics:symbols:upload", "--app=1:2:android:3"],
        ]);
        expect(commands.first[3], endsWith("/crashlytics_mapping_file_id.xml"));
        expect(commands.first[3], startsWith("--resource-file="));
        expect(commands.first.last, endsWith("/mapping.txt"));
      },
    );

    test(
      'a mapping file without its id is skipped, not left pending',
      () async {
        write("$project/build/app/outputs/mapping/release/mapping.txt", "m");
        final build = await archiveFrom(AppPlatform.android);

        final (outcome, commands) = await uploadTo(build);

        expect(outcome.status, UploadStatus.skipped);
        expect(outcome.message, contains("mapping file id"));
        expect(commands, isEmpty);
      },
    );

    test('the rest still goes when only the mapping id is missing', () async {
      writeAndroid(withMappingId: false);
      final build = await archiveFrom(AppPlatform.android);

      final (outcome, commands) = await uploadTo(build);

      expect(outcome.status, UploadStatus.done);
      expect(outcome.message, contains("mapping.txt not uploaded"));
      expect(commands.single[1], "crashlytics:symbols:upload");
    });

    test('a missing Firebase app id leaves the upload pending', () async {
      writeAndroid();
      final build = await archiveFrom(AppPlatform.android, firebaseAppId: null);

      final (outcome, commands) = await uploadTo(build);

      expect(outcome.status, UploadStatus.pending);
      expect(commands, isEmpty);
    });

    test('a failed command leaves the upload pending', () async {
      writeAndroid();
      final build = await archiveFrom(AppPlatform.android);

      final (outcome, _) = await uploadTo(build, succeeds: false);

      expect(outcome.status, UploadStatus.pending);
    });

    group('iOS', () {
      setUp(() {
        write(
          "$project/build/ios/archive/Runner.xcarchive/dSYMs/Runner.app.dSYM/"
              "Contents/Info.plist",
          "<plist/>",
        );
      });

      test('sends dSYMs through upload-symbols', () async {
        write(
          "$project/${CrashlyticsDestination.uploadSymbolsRelativePath}",
          "",
        );
        final build = await archiveFrom(
          AppPlatform.ios,
          firebaseAppId: "1:2:ios:3",
        );

        final (outcome, commands) = await uploadTo(build);

        expect(outcome.status, UploadStatus.done);
        expect(commands.single.skip(1).take(4), [
          "-ai",
          "1:2:ios:3",
          "-p",
          "ios",
        ]);
        expect(commands.single.last, endsWith("/dSYMs"));
      });

      test(
        'pending until pod install when the project uses CocoaPods',
        () async {
          write("$project/ios/Podfile", "");
          final (outcome, _) = await uploadTo(
            await archiveFrom(AppPlatform.ios),
          );
          expect(outcome.status, UploadStatus.pending);
          expect(outcome.message, contains("pod install"));
        },
      );

      test('skipped for a project without CocoaPods', () async {
        final (outcome, _) = await uploadTo(await archiveFrom(AppPlatform.ios));
        expect(outcome.status, UploadStatus.skipped);
      });
    });
  });

  group('NewRelicDestination', () {
    NewRelicDestination destination(
      List<RecordedRequest> requests, {
      Map<String, String> environment = const {"NR": "token-1"},
      int status = 200,
    }) => NewRelicDestination(
      config: const NewRelicSymbolsConfig(
        region: NewRelicRegion.eu,
        androidToken: TokenSource.env("NR"),
        iosToken: TokenSource.env("NR"),
      ),
      secrets: SecretHelper(projectRoot: project, environment: environment),
      processService: ProcessService(),
      retryCount: 0,
      dio: fakeDio(requests, status: status),
    );

    Future<UploadOutcome> uploadTo(
      NewRelicDestination destination,
      ArchivedBuild build,
    ) async {
      await archiveService().extract(build, destination.kindsNeeded(build));
      try {
        return await destination.upload(build);
      } finally {
        archiveService().release(build);
      }
    }

    test('posts a tagged mapping copy with the token header', () async {
      write(
        "$project/build/app/outputs/mapping/release/mapping.txt",
        "a -> b:\n",
      );
      final build = await archiveFrom(
        AppPlatform.android,
        newRelicBuildId: "nr-1",
      );
      final requests = <RecordedRequest>[];

      final outcome = await uploadTo(destination(requests), build);

      expect(outcome.status, UploadStatus.done);
      final request = requests.single;
      expect(
        request.uri.toString(),
        "https://mobile-symbol-upload.eu.nr-data.net/symbol",
      );
      expect(request.headers["X-APP-LICENSE-KEY"], "token-1");
      expect(request.field, "upload");
      expect(
        String.fromCharCodes(request.bytes),
        contains("a -> b:\n# NR_BUILD_ID -> nr-1\n"),
      );
    });

    test('posts the archived dSYMs.zip without extracting it', () async {
      write(
        "$project/build/ios/archive/Runner.xcarchive/dSYMs/Runner.app.dSYM/"
            "Contents/Info.plist",
        "<plist/>",
      );
      final build = await archiveFrom(AppPlatform.ios);
      final requests = <RecordedRequest>[];
      final newRelic = destination(requests);

      expect(newRelic.kindsNeeded(build), isEmpty);
      final outcome = await uploadTo(newRelic, build);

      expect(outcome.status, UploadStatus.done);
      expect(requests.single.field, "dsym");
      expect(requests.single.filename, "dSYMs.zip");
      expect(
        requests.single.bytes,
        File(build.zipOf(SymbolKind.dsyms)!).readAsBytesSync(),
      );
    });

    test('an HTTP error leaves the upload pending', () async {
      write("$project/build/app/outputs/mapping/release/mapping.txt", "m");
      final build = await archiveFrom(
        AppPlatform.android,
        newRelicBuildId: "nr-1",
      );
      final outcome = await uploadTo(destination([], status: 500), build);
      expect(outcome.status, UploadStatus.pending);
    });

    test(
      'a token not where its source says leaves the upload pending',
      () async {
        write("$project/build/app/outputs/mapping/release/mapping.txt", "m");
        final build = await archiveFrom(
          AppPlatform.android,
          newRelicBuildId: "nr-1",
        );
        final requests = <RecordedRequest>[];
        final outcome = await uploadTo(
          destination(requests, environment: const {}),
          build,
        );
        expect(outcome.status, UploadStatus.pending);
        expect(outcome.message, contains("environment variable NR"));
        expect(requests, isEmpty);
      },
    );

    test('the send timeout grows with the file', () {
      expect(NewRelicDestination.sendTimeoutFor(0).inSeconds, 60);
      expect(
        NewRelicDestination.sendTimeoutFor(150 * 1000 * 1000).inMinutes,
        greaterThanOrEqualTo(10),
      );
    });
  });

  group('SymbolService', () {
    SymbolService serviceWith(
      List<SymbolCommand> commands, {
      bool dryRun = false,
    }) => SymbolService(
      config: SymbolsConfig(archivePath: archive, commands: commands),
      appDetail: AppDetail(appName: "app", buildVersion: "1.0.0"),
      retryCount: 0,
      dryRun: dryRun,
      projectRoot: project,
      environment: const {},
    );

    void writeMapping() =>
        write("$project/build/app/outputs/mapping/release/mapping.txt", "m");

    Future<ArchivedBuild> buildWithPending() async {
      writeMapping();
      final service = serviceWith(const [
        SymbolCommand(name: "flaky", run: "exit 1"),
      ]);
      await service.handleBuild(
        platform: AppPlatform.android,
        target: BuildTarget.store,
        buildParameters: const [],
      );
      await service.uploadArchived();
      return archiveService().loadAll().single;
    }

    test('a dry run leaves the archive untouched', () async {
      writeMapping();
      await serviceWith(const [
        SymbolCommand(name: "c", run: "true"),
      ], dryRun: true).handleBuild(
        platform: AppPlatform.android,
        target: BuildTarget.store,
        buildParameters: const [],
      );
      expect(Directory(archive).existsSync(), isFalse);
    });

    test('a pending destination that is gone is marked skipped', () async {
      final build = await buildWithPending();

      expect(await serviceWith(const []).uploadPending(), isTrue);

      final record = ArchivedBuild.load(build.directory)!.uploads["flaky"]!;
      expect(record.status, UploadStatus.skipped);
      expect(record.message, contains("no longer configured"));
      // Nothing pending holds the run back from pruning any more.
      expect(archiveService().prune(1).removed, isEmpty);
      expect(ArchivedBuild.load(build.directory)!.hasPendingUploads, isFalse);
    });

    test('a damaged archive leaves its uploads pending', () async {
      final build = await buildWithPending();
      File(build.zipOf(SymbolKind.mapping)!).writeAsStringSync("not a zip");

      final retried = await serviceWith(const [
        SymbolCommand(name: "flaky", run: "cat {mapping}"),
      ]).uploadPending();

      expect(retried, isFalse);
      final record = ArchivedBuild.load(build.directory)!.uploads["flaky"]!;
      expect(record.status, UploadStatus.pending);
      expect(record.message, contains("could not be extracted"));
    });

    test('only the kinds a destination names are extracted', () async {
      writeMapping();
      write(
        "$project/build/app/intermediates/merged_native_libs/release/"
            "mergeReleaseNativeLibs/out/lib/arm64-v8a/libapp.so",
        "elf",
      );
      final service = serviceWith(const [
        SymbolCommand(
          name: "check",
          run: "test -f {mapping} && test ! -e {dir}/native-libs",
        ),
      ]);
      await service.handleBuild(
        platform: AppPlatform.android,
        target: BuildTarget.store,
        buildParameters: const [],
      );
      await service.uploadArchived();
      final build = archiveService().loadAll().single;
      expect(build.uploads["check"]!.status, UploadStatus.done);
      expect(build.files, contains(SymbolKind.nativeLibs));
    });
  });

  group('pubspec', () {
    PubspecParameters parse(String yaml) =>
        PubspecParameters.fromPubspec(loadYaml(yaml) as Map);

    for (final (label, body) in [
      ("symbols", "    crashlytic: true\n"),
      (
        "newRelic",
        "    newRelic:\n      iosToken: {env: X}\n      regoin: eu\n",
      ),
      ("a token source", "    newRelic:\n      iosToken: {env: X, keys: Y}\n"),
      ("a command", "    commands: [{name: a, run: b, platfrom: ios}]\n"),
    ]) {
      test('an unknown key under $label is rejected', () {
        expect(
          () => parse("uploader:\n  symbols:\n$body"),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              "message",
              contains("unknown key"),
            ),
          ),
        );
      });
    }
  });
}
