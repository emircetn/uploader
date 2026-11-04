import 'dart:io';

import 'package:test/test.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/secret_helper.dart';
import 'package:uploader/src/model/app_detail.dart';
import 'package:uploader/src/model/archived_build.dart';
import 'package:uploader/src/model/pubspec_parameters.dart';
import 'package:uploader/src/model/symbols_config.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/service/symbol/command_destination.dart';
import 'package:uploader/src/service/symbol/new_relic_destination.dart';
import 'package:uploader/src/service/symbol/symbol_archive_service.dart';
import 'package:uploader/src/service/symbol/symbol_service.dart';
import 'package:uploader/src/util/build_parameters.dart';
import 'package:yaml/yaml.dart';

PubspecParameters parse(String yaml) =>
    PubspecParameters.fromPubspec(loadYaml(yaml) as Map);

void write(String path, String content) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// A project as an Android release build with R8, Crashlytics, the NDK and
/// the New Relic plugin leaves it.
void writeAndroidBuild(String root) {
  write("$root/build/app/outputs/mapping/release/mapping.txt", "a -> b:\n");
  write(
    "$root/build/app/generated/res/injectCrashlyticsMappingFileIdRelease/"
        "values/com_google_firebase_crashlytics_mappingfileid.xml",
    "<resources/>",
  );
  write(
    "$root/build/app/intermediates/merged_native_libs/release/"
        "mergeReleaseNativeLibs/out/lib/arm64-v8a/libapp.so",
    "elf",
  );
  write(
    "$root/build/app/generated/java/newrelicConfigRelease/com/newrelic/agent/"
        "android/NewRelicConfig.java",
    'final class NewRelicConfig {\n'
        '    static final String BUILD_ID = "nr-build-1";\n}\n',
  );
}

void main() {
  late Directory temp;
  late String project;
  late String archive;

  setUp(() {
    temp = Directory.systemTemp.createTempSync("uploader_symbols_test_");
    project = "${temp.path}/project";
    archive = "${temp.path}/archive";
    Directory(project).createSync();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('pubspec', () {
    PubspecParameters symbols(String body) =>
        parse("uploader:\n  symbols:\n$body");

    test('symbols stay off unless configured', () {
      expect(parse("uploader:\n  platform: all\n").symbols, isNull);
    });

    test('symbols: true archives with the defaults and uploads nowhere', () {
      final config = parse("uploader:\n  symbols: true\n").symbols!;
      expect(config.archivePath, SymbolsConfig.defaultArchivePath);
      expect(config.keepLast, SymbolsConfig.defaultKeepLast);
      expect(config.crashlytics, isFalse);
      expect(config.newRelic, isNull);
      expect(config.failOnUploadError, isFalse);
    });

    test('every option is read', () {
      final config = symbols('''
    archivePath: release_symbols
    keepLast: 5
    failOnUploadError: true
    crashlytics: true
    newRelic:
      region: eu
      androidToken:
        env: NEW_RELIC_ANDROID_KEY
      iosToken:
        file: .env
        key: NEW_RELIC_IOS_KEY
    commands:
      - name: sentry
        platform: android
        run: sentry-cli upload-proguard {mapping}
''').symbols!;

      expect(config.archivePath, "release_symbols");
      expect(config.keepLast, 5);
      expect(config.failOnUploadError, isTrue);
      expect(config.crashlytics, isTrue);
      expect(config.newRelic!.region, NewRelicRegion.eu);
      expect(
        config.newRelic!.androidToken!.description,
        "environment variable NEW_RELIC_ANDROID_KEY",
      );
      expect(
        config.newRelic!.iosToken!.description,
        "NEW_RELIC_IOS_KEY in .env",
      );
      expect(config.commands.single.name, "sentry");
      expect(config.commands.single.platform, AppPlatform.android);
    });

    test('newRelic without a written token source is rejected', () {
      expect(() => symbols("    newRelic: true\n"), throwsFormatException);
      expect(
        () => symbols("    newRelic: {region: eu}\n"),
        throwsFormatException,
      );
    });

    test('a token source is either env, or file with key', () {
      for (final source in [
        "{file: .env}",
        "{key: B}",
        "{env: A, file: .env, key: B}",
        "NEW_RELIC_ANDROID_KEY",
      ]) {
        expect(
          () => symbols("    newRelic:\n      androidToken: $source\n"),
          throwsFormatException,
          reason: source,
        );
      }
    });

    test('only platforms with a token are uploaded, to the US by default', () {
      final newRelic = symbols(
        "    newRelic:\n      iosToken: {env: NR_IOS}\n",
      ).symbols!.newRelic!;
      expect(newRelic.tokenFor(AppPlatform.android), isNull);
      expect(newRelic.tokenFor(AppPlatform.ios)!.env, "NR_IOS");
      expect(
        newRelic.region.symbolUri.toString(),
        "https://mobile-symbol-upload.newrelic.com/symbol",
      );
    });

    test('an unknown region is rejected', () {
      expect(
        () => symbols(
          "    newRelic:\n      region: mars\n      iosToken: {env: X}\n",
        ),
        throwsFormatException,
      );
    });

    test('a command without run is rejected', () {
      expect(
        () => symbols("    commands: [{name: x}]\n"),
        throwsFormatException,
      );
    });

    test('the archive path expands ~ and resolves relative paths', () {
      const env = {"HOME": "/home/me"};
      expect(
        const SymbolsConfig().resolveArchivePath(
          projectRoot: "/p",
          environment: env,
        ),
        "/home/me/.uploader/archive",
      );
      expect(
        const SymbolsConfig(
          archivePath: "out/",
        ).resolveArchivePath(projectRoot: "/p", environment: env),
        "/p/out",
      );
    });
  });

  group('SecretHelper', () {
    SecretHelper helper([Map<String, String> environment = const {}]) =>
        SecretHelper(projectRoot: project, environment: environment);

    test('expands ~ in a token file path', () {
      write("${temp.path}/home/.config/nr.env", "NR=from-home\n");
      expect(
        helper({
          "HOME": "${temp.path}/home",
        }).resolve(const TokenSource.file(file: "~/.config/nr.env", key: "NR")),
        "from-home",
      );
      // Without a home folder the token is reported missing, not thrown.
      expect(
        helper().resolve(
          const TokenSource.file(file: "~/.config/nr.env", key: "NR"),
        ),
        isNull,
      );
    });

    test('reads an environment variable', () {
      expect(
        helper({"NR": " shell "}).resolve(const TokenSource.env("NR")),
        "shell",
      );
    });

    test('reads a key from a JSON file', () {
      write("$project/defines/prod.json", '{"NR": "from-json"}');
      expect(
        helper().resolve(
          const TokenSource.file(file: "defines/prod.json", key: "NR"),
        ),
        "from-json",
      );
    });

    test('reads a key from .env and .properties lines', () {
      write("$project/.env", 'export NR="from-env"\n# comment\n');
      write(
        "$project/android/app/newrelic.properties",
        "com.newrelic.application_token=AA1-NRMA\n",
      );
      expect(
        helper().resolve(const TokenSource.file(file: ".env", key: "NR")),
        "from-env",
      );
      expect(
        helper().resolve(
          const TokenSource.file(
            file: "android/app/newrelic.properties",
            key: "com.newrelic.application_token",
          ),
        ),
        "AA1-NRMA",
      );
    });

    test('looks nowhere but the configured source', () {
      write("$project/.env", "NR=file\n");
      expect(helper().resolve(const TokenSource.env("NR")), isNull);
      expect(
        helper({
          "NR": "shell",
        }).resolve(const TokenSource.file(file: "missing.env", key: "NR")),
        isNull,
      );
    });

    test('--split-debug-info is read in both spellings', () {
      expect(
        BuildParameters.splitDebugInfoPath(["--split-debug-info=build/sym"]),
        "build/sym",
      );
      expect(
        BuildParameters.splitDebugInfoPath(["--split-debug-info", "out"]),
        "out",
      );
      expect(BuildParameters.splitDebugInfoPath(["--obfuscate"]), isNull);
    });
  });

  group('SymbolArchiveService', () {
    SymbolArchiveService service() => SymbolArchiveService(
      archiveRoot: archive,
      appName: "app",
      projectRoot: project,
    );

    test('collects what an Android release build leaves', () {
      writeAndroidBuild(project);
      write("$project/build/dart_symbols/app.android-arm64.symbols", "x");

      final files = service().collect(
        AppPlatform.android,
        buildParameters: ["--split-debug-info=build/dart_symbols"],
      );

      expect(files.keys, {
        SymbolKind.mapping,
        SymbolKind.crashlyticsMappingId,
        SymbolKind.nativeLibs,
        SymbolKind.dartSymbols,
      });
      expect(service().readNewRelicBuildId(), "nr-build-1");
    });

    test('collects nothing when the build left nothing', () {
      expect(service().collect(AppPlatform.ios), isEmpty);
    });

    test('archives a zip per kind and a manifest that read back', () async {
      writeAndroidBuild(project);
      final archived = await service().archive(
        runId: "20261102-120000",
        version: "1.4.0",
        buildNumber: "87",
        platform: AppPlatform.android,
        target: BuildTarget.store,
        files: service().collect(AppPlatform.android),
        firebaseAppId: "1:2:android:3",
        newRelicBuildId: "nr-build-1",
      );

      expect(
        archived.directory.path,
        "$archive/app/1.4.0+87/20261102-120000/android-store",
      );
      expect(
        archived.directory.listSync().map((e) => e.uri.pathSegments.last),
        unorderedEquals([
          "mapping.txt.zip",
          "crashlytics_mapping_file_id.xml.zip",
          "native-libs.zip",
          "manifest.json",
        ]),
      );

      // The build folder can go; the archive keeps its copy.
      Directory("$project/build").deleteSync(recursive: true);
      final loaded = ArchivedBuild.load(archived.directory)!;
      expect(loaded.fullVersion, "1.4.0+87");
      expect(loaded.firebaseAppId, "1:2:android:3");
      expect(loaded.newRelicBuildId, "nr-build-1");
      expect(() => loaded.pathOf(SymbolKind.mapping), throwsStateError);

      await service().extract(loaded, loaded.files.keys);
      final extracted = loaded.contentDirectory!;
      expect(
        File(loaded.pathOf(SymbolKind.mapping)!).readAsStringSync(),
        "a -> b:\n",
      );
      expect(
        File(
          "${loaded.pathOf(SymbolKind.nativeLibs)}/arm64-v8a/libapp.so",
        ).readAsStringSync(),
        "elf",
      );

      service().release(loaded);
      expect(extracted.existsSync(), isFalse);
    });

    test('dSYMs.zip holds the bundles at its root', () async {
      write(
        "$project/build/ios/archive/Runner.xcarchive/dSYMs/Runner.app.dSYM/"
            "Contents/Info.plist",
        "<plist/>",
      );
      final archived = await service().archive(
        runId: "20261102-120000",
        version: "1.0.0",
        buildNumber: null,
        platform: AppPlatform.ios,
        target: BuildTarget.store,
        files: service().collect(AppPlatform.ios),
      );

      final listing = await Process.run("unzip", [
        "-Z1",
        archived.zipOf(SymbolKind.dsyms)!,
      ]);
      expect(
        "${listing.stdout}".trim().split("\n"),
        contains("Runner.app.dSYM/Contents/Info.plist"),
      );

      await service().extract(archived, archived.files.keys);
      expect(
        File(
          "${archived.pathOf(SymbolKind.dsyms)}/Runner.app.dSYM/Contents/"
          "Info.plist",
        ).existsSync(),
        isTrue,
      );
      service().release(archived);
    });

    test('pruning keeps the newest runs and every run still pending', () async {
      writeAndroidBuild(project);
      final files = service().collect(AppPlatform.android);

      Future<ArchivedBuild> archiveRun(String runId) => service().archive(
        runId: runId,
        version: "1.0.0",
        buildNumber: runId.substring(runId.length - 1),
        platform: AppPlatform.android,
        target: BuildTarget.store,
        files: files,
      );

      final oldPending = (await archiveRun("20260101-000001"))
        ..record(
          "newRelic",
          UploadRecord(status: UploadStatus.pending, at: DateTime(2026)),
        )
        ..save();
      final oldDone = await archiveRun("20260101-000002");
      await archiveRun("20260101-000003");
      await archiveRun("20260101-000004");

      final pruned = service().prune(2);

      expect(pruned.removed, [oldDone.directory.parent.path]);
      expect(pruned.removedPending, isEmpty);
      expect(oldPending.directory.existsSync(), isTrue);
      expect(service().loadAll(), hasLength(3));
    });

    test('pruning keeps no more pending runs than keepLast', () async {
      writeAndroidBuild(project);
      final files = service().collect(AppPlatform.android);

      Future<ArchivedBuild> archivePending(String runId) async =>
          (await service().archive(
              runId: runId,
              version: "1.0.0",
              buildNumber: null,
              platform: AppPlatform.android,
              target: BuildTarget.store,
              files: files,
            ))
            ..record(
              "newRelic",
              UploadRecord(status: UploadStatus.pending, at: DateTime(2026)),
            )
            ..save();

      final oldest = await archivePending("20260101-000001");
      final older = await archivePending("20260101-000002");
      for (final runId in ["20260101-000003", "20260101-000004"]) {
        await archivePending(runId);
      }

      // The newest run stays, and one more held by its pending upload; the
      // older pending runs go.
      final pruned = service().prune(1);

      expect(pruned.removed, [
        older.directory.parent.path,
        oldest.directory.parent.path,
      ]);
      expect(pruned.removedPending, pruned.removed);
      expect(service().loadAll(), hasLength(2));
    });
  });

  group('NewRelicDestination', () {
    test('tags a copy of the mapping with the build id', () {
      final mapping = File("${temp.path}/mapping.txt")
        ..writeAsStringSync("a -> b:");
      expect(NewRelicDestination.hasBuildIdTag(mapping), isFalse);

      final out = Directory("${temp.path}/out")..createSync();
      final tagged = NewRelicDestination.tagMapping(mapping, "id-1", out);

      expect(tagged.readAsStringSync(), "a -> b:\n# NR_BUILD_ID -> id-1\n");
      expect(NewRelicDestination.hasBuildIdTag(tagged), isTrue);
      expect(mapping.readAsStringSync(), "a -> b:");
    });

    test('batches dSYMs by size, a large one on its own', () {
      final batches = NewRelicDestination.batchBySize([
        (name: "a", size: 40),
        (name: "b", size: 50),
        (name: "c", size: 200),
        (name: "d", size: 10),
      ], 100);
      expect(batches, [
        ["a", "b"],
        ["c"],
        ["d"],
      ]);
    });
  });

  group('CommandDestination', () {
    ArchivedBuild build() =>
        ArchivedBuild(
            directory: Directory("/archive/run/android-store"),
            appName: "app",
            version: "1.0.0",
            buildNumber: "3",
            platform: AppPlatform.android,
            target: BuildTarget.store,
            createdAt: DateTime(2026),
            files: {SymbolKind.mapping: "mapping.txt"},
          )
          ..contentDirectory = Directory("/tmp/extracted")
          ..extractedKinds = {SymbolKind.mapping};

    test('substitutes quoted values', () {
      final rendered = CommandDestination.render(
        "upload {mapping} --version {version} --in {dir} {unknown}",
        build(),
      );
      expect(
        rendered.command,
        "upload '/tmp/extracted/mapping.txt' --version '1.0.0' "
        "--in '/archive/run/android-store' {unknown}",
      );
      expect(rendered.missing, isEmpty);
    });

    test('reports files the build does not have', () {
      expect(CommandDestination.render("upload {dsyms}", build()).missing, [
        "dsyms",
      ]);
    });
  });

  group('SymbolService', () {
    SymbolService serviceWith(
      List<SymbolCommand> commands, {
      bool failOnUploadError = false,
    }) => SymbolService(
      config: SymbolsConfig(
        archivePath: archive,
        failOnUploadError: failOnUploadError,
        commands: commands,
      ),
      appDetail: AppDetail(
        appName: "app",
        buildVersion: "1.0.0",
        buildNumber: "7",
      ),
      retryCount: 0,
      projectRoot: project,
      environment: const {},
      startedAt: DateTime(2026, 11, 2, 12),
    );

    test('a failed upload is archived as pending and retried later', () async {
      writeAndroidBuild(project);

      final service = serviceWith(const [
        SymbolCommand(name: "flaky", run: "exit 1"),
      ]);
      expect(
        await service.handleBuild(
          platform: AppPlatform.android,
          target: BuildTarget.store,
          buildParameters: const [],
        ),
        isTrue,
      );
      // The run goes on: the symbols are safe in the archive.
      expect(await service.uploadArchived(), isTrue);
      final archived = SymbolArchiveService(
        archiveRoot: archive,
        appName: "app",
        projectRoot: project,
      ).loadAll().single;
      expect(archived.uploads["flaky"]!.status, UploadStatus.pending);

      Directory("$project/build").deleteSync(recursive: true);

      final retried = await serviceWith(const [
        SymbolCommand(name: "flaky", run: "cp {mapping} {dir}/../retried.txt"),
      ]).uploadPending();

      expect(retried, isTrue);
      expect(
        File(
          "${archived.directory.parent.path}/retried.txt",
        ).readAsStringSync(),
        "a -> b:\n",
      );
      expect(
        ArchivedBuild.load(archived.directory)!.uploads["flaky"]!.status,
        UploadStatus.done,
      );
    });

    test('failOnUploadError fails the run on a pending upload', () async {
      writeAndroidBuild(project);
      final service = serviceWith(const [
        SymbolCommand(name: "flaky", run: "exit 1"),
      ], failOnUploadError: true);
      expect(
        await service.handleBuild(
          platform: AppPlatform.android,
          target: BuildTarget.store,
          buildParameters: const [],
        ),
        isTrue,
      );
      expect(await service.uploadArchived(), isFalse);
    });

    test('a build is only uploaded after the run uploads it', () async {
      writeAndroidBuild(project);
      final service = serviceWith(const [
        SymbolCommand(name: "c", run: "true"),
      ]);
      await service.handleBuild(
        platform: AppPlatform.android,
        target: BuildTarget.store,
        buildParameters: const [],
      );

      // A run that stops here leaves the upload to --upload-symbols.
      final archived = SymbolArchiveService(
        archiveRoot: archive,
        appName: "app",
        projectRoot: project,
      ).loadAll().single;
      expect(archived.uploads["c"]!.status, UploadStatus.pending);

      expect(await service.uploadArchived(), isTrue);
      expect(
        ArchivedBuild.load(archived.directory)!.uploads["c"]!.status,
        UploadStatus.done,
      );
    });

    test('--build-name and --build-number win over pubspec.yaml', () async {
      writeAndroidBuild(project);
      await serviceWith(const []).handleBuild(
        platform: AppPlatform.android,
        target: BuildTarget.store,
        buildParameters: const ["--build-name=2.0.0", "--build-number", "42"],
      );

      final archived = SymbolArchiveService(
        archiveRoot: archive,
        appName: "app",
        projectRoot: project,
      ).loadAll().single;
      expect(archived.fullVersion, "2.0.0+42");
      expect(archived.directory.path, contains("/app/2.0.0+42/"));
    });

    test('a missing archived zip does not stop the other retries', () async {
      final service = serviceWith(const [
        SymbolCommand(name: "flaky", run: "exit 1"),
      ]);
      writeAndroidBuild(project);
      await service.handleBuild(
        platform: AppPlatform.android,
        target: BuildTarget.store,
        buildParameters: const [],
      );
      await service.handleBuild(
        platform: AppPlatform.android,
        target: BuildTarget.appDistribution,
        buildParameters: const [],
      );
      await service.uploadArchived();

      final builds = SymbolArchiveService(
        archiveRoot: archive,
        appName: "app",
        projectRoot: project,
      ).loadAll();
      File(builds.first.zipOf(SymbolKind.mapping)!).deleteSync();

      // The damaged build stays pending; the other one still goes through.
      expect(
        await serviceWith(const [
          SymbolCommand(name: "flaky", run: "test -f {mapping}"),
        ]).uploadPending(),
        isFalse,
      );
      expect(
        ArchivedBuild.load(builds.first.directory)!.hasPendingUploads,
        isTrue,
      );
      expect(
        ArchivedBuild.load(builds.last.directory)!.uploads["flaky"]!.status,
        UploadStatus.done,
      );
    });
  });

  test('a dry run prints shareable commands', () {
    expect(
      ProcessService.displayArguments([
        "-f",
        "build/ios/ipa/Translate AI.ipa",
        "--apiKey",
        "KEY123",
        "--apiIssuer",
        "issuer",
        "--testers",
        "a@x.com, b@x.com",
      ]),
      [
        "-f",
        "'build/ios/ipa/Translate AI.ipa'",
        "--apiKey",
        "***",
        "--apiIssuer",
        "***",
        "--testers",
        "<2 testers>",
      ],
    );
  });
}
