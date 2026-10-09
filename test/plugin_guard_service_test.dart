import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uploader/src/config/uploader_config.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/plugin_stub_helper.dart';
import 'package:uploader/src/model/cli_options.dart';
import 'package:uploader/src/model/plugin_stub_config.dart';
import 'package:uploader/src/service/plugin_guard_service.dart';
import 'package:uploader/src/service/process_service.dart';

/// Stands in for `flutter build --analyze-size`: it writes a summary in which
/// [reachedPackages] kept a called function.
class FakeProcessService extends ProcessService {
  final String summaryFolder;
  final Set<String> reachedPackages;

  /// Packages reached only by a build given the key as a parameter.
  final Map<String, Set<String>> reachedByParameter;

  final List<AppPlatform> analysedPlatforms = [];
  final List<List<String>> analysisParameters = [];
  int pubGetCount = 0;

  FakeProcessService({
    required this.summaryFolder,
    this.reachedPackages = const {},
    this.reachedByParameter = const {},
  });

  @override
  Future<bool> pubGet() async {
    pubGetCount++;
    return true;
  }

  @override
  Future<String?> buildForCodeSize({
    required AppPlatform platform,
    required String codeSizeDirectory,
    List<String>? extraBuildParameters,
  }) async {
    final parameters = extraBuildParameters ?? const [];
    analysedPlatforms.add(platform);
    analysisParameters.add(parameters);
    final reached = {
      ...reachedPackages,
      for (final parameter in parameters) ...?reachedByParameter[parameter],
    };

    Map<String, dynamic> function(String name) => {
      "n": name,
      "children": [
        {"n": "<Code>", "value": 100},
      ],
    };
    final summary = File("$summaryFolder/${platform.value}.json")
      ..writeAsStringSync(
        jsonEncode({
          "n": "Root",
          "children": [
            {
              "n": "App (Dart AOT)",
              "children": [
                for (final name in reached)
                  {
                    "n": "package:$name",
                    "children": [function("call")],
                  },
                {
                  "n": "package:workmanager",
                  "children": [function("registerWith")],
                },
              ],
            },
          ],
        }),
      );
    return summary.path;
  }
}

void main() {
  late Directory sandbox;
  late String projectRoot;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync("plugin_guard_test");
    projectRoot = "${sandbox.path}/app";
    Directory(projectRoot).createSync();

    final workmanagerRoot = "${sandbox.path}/workmanager";
    File("$workmanagerRoot/lib/workmanager.dart")
      ..createSync(recursive: true)
      ..writeAsStringSync("const channel = MethodChannel('workmanager');\n");
    File("$workmanagerRoot/pubspec.yaml").writeAsStringSync(
      "name: workmanager\n"
      "flutter:\n"
      "  plugin:\n"
      "    platforms:\n"
      "      android:\n"
      "        package: dev.fluttercommunity.workmanager\n",
    );

    File("$projectRoot/.flutter-plugins-dependencies").writeAsStringSync(
      jsonEncode({
        "plugins": {
          "ios": [
            {"name": "url_launcher_ios", "path": "${sandbox.path}/none"},
            {"name": "workmanager", "path": workmanagerRoot},
          ],
          "android": [
            {"name": "url_launcher_android", "path": "${sandbox.path}/none"},
            {"name": "workmanager", "path": workmanagerRoot},
          ],
        },
        "dependencyGraph": [],
      }),
    );
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  UploaderConfig configWith({
    UploadType uploadType = UploadType.store,
    AppPlatform platform = AppPlatform.all,
    PluginStubConfig pluginStubs = const PluginStubConfig(),
    String? allowedPluginsPath,
    bool verifyPluginStubs = true,
    bool audit = false,
    bool dryRun = false,
    List<String>? extraBuildParameters,
    List<String>? appDistributionExtraBuildParameters,
  }) => UploaderConfig(
    uploadType: uploadType,
    platform: platform,
    useParallelUpload: false,
    enableLogFileCreation: false,
    pluginStubs: pluginStubs,
    allowedPluginsPath: allowedPluginsPath,
    verifyPluginStubs: verifyPluginStubs,
    extraBuildParameters: extraBuildParameters,
    appDistributionExtraBuildParameters: appDistributionExtraBuildParameters,
    cliOptions: CliOptions(audit: audit, dryRun: dryRun),
  );

  FakeProcessService fakeProcess({
    Set<String> reachedPackages = const {},
    Map<String, Set<String>> reachedByParameter = const {},
  }) => FakeProcessService(
    summaryFolder: sandbox.path,
    reachedPackages: reachedPackages,
    reachedByParameter: reachedByParameter,
  );

  PluginGuardService guardWith(
    UploaderConfig config, {
    FakeProcessService? process,
  }) => PluginGuardService(
    config: config,
    processService: process ?? fakeProcess(),
    projectRoot: projectRoot,
  );

  PluginStubPlan stubOf(String name, AppPlatform platform) => PluginStubPlan(
    name: name,
    strippedPlatform: platform,
    pubspec: const {},
    droppedImplementations: const [],
    removesNativeCode: true,
  );

  /// Runs the guard the way a run does, with [stubs] applied in between.
  Future<bool> runGuard(
    PluginGuardService guard, {
    List<PluginStubPlan> stubs = const [],
  }) async {
    final analysis = await guard.analyse();
    if (analysis == null) return false;
    return guard.check(stubs: stubs, analysis: analysis);
  }

  File projectFile(String relativePath) => File("$projectRoot/$relativePath");

  group('allowed plugins', () {
    test('a missing file records the registered plugins and passes', () async {
      final process = fakeProcess();
      final guard = guardWith(
        configWith(allowedPluginsPath: "tool/allowed_plugins.yaml"),
        process: process,
      );

      expect(await runGuard(guard), isTrue);
      expect(
        projectFile("tool/allowed_plugins.yaml").readAsStringSync(),
        contains("  - url_launcher_ios"),
      );
      expect(process.pubGetCount, 1);
      expect(process.analysedPlatforms, isEmpty);
    });

    test('a plugin missing from the file stops the run', () async {
      projectFile(
        "allowed.yaml",
      ).writeAsStringSync("ios: []\nandroid:\n  - url_launcher_android\n");
      final guard = guardWith(configWith(allowedPluginsPath: "allowed.yaml"));

      expect(await runGuard(guard), isFalse);
    });

    test('a dry run does not write the file', () async {
      final guard = guardWith(
        configWith(
          platform: AppPlatform.ios,
          allowedPluginsPath: "allowed.yaml",
          dryRun: true,
        ),
      );

      expect(await runGuard(guard), isTrue);
      expect(projectFile("allowed.yaml").existsSync(), isFalse);
    });
  });

  group('stub reachability', () {
    test('a stub nothing reaches passes', () async {
      final process = fakeProcess();
      final guard = guardWith(
        configWith(
          pluginStubs: const PluginStubConfig(all: ["workmanager"]),
          extraBuildParameters: ["--obfuscate", "--dart-define=A=1"],
        ),
        process: process,
      );

      expect(
        await runGuard(guard, stubs: [stubOf("workmanager", AppPlatform.all)]),
        isTrue,
      );
      expect(process.analysedPlatforms, [AppPlatform.android, AppPlatform.ios]);
      expect(process.analysisParameters.first, ["--dart-define=A=1"]);
    });

    test('a stub the Dart code still reaches stops the run', () async {
      final guard = guardWith(
        configWith(
          pluginStubs: const PluginStubConfig(ios: ["google_sign_in"]),
        ),
        process: fakeProcess(reachedPackages: {"google_sign_in"}),
      );

      expect(
        await runGuard(
          guard,
          stubs: [stubOf("google_sign_in", AppPlatform.ios)],
        ),
        isFalse,
      );
    });

    test('only the platforms a stub strips are analysed', () async {
      final process = fakeProcess();
      final guard = guardWith(
        configWith(
          pluginStubs: const PluginStubConfig(ios: ["google_sign_in"]),
        ),
        process: process,
      );

      await runGuard(guard, stubs: [stubOf("google_sign_in", AppPlatform.ios)]);

      expect(process.analysedPlatforms, [AppPlatform.ios]);
    });

    test(
      'a stub on a platform the run does not build is not analysed',
      () async {
        final process = fakeProcess();
        final guard = guardWith(
          configWith(
            platform: AppPlatform.android,
            pluginStubs: const PluginStubConfig(ios: ["google_sign_in"]),
          ),
          process: process,
        );

        expect(
          await runGuard(
            guard,
            stubs: [stubOf("google_sign_in", AppPlatform.ios)],
          ),
          isTrue,
        );
        expect(process.analysedPlatforms, isEmpty);
      },
    );

    test('verifyPluginStubs: false skips the analysis build', () async {
      final process = fakeProcess(reachedPackages: {"google_sign_in"});
      final guard = guardWith(
        configWith(
          pluginStubs: const PluginStubConfig(all: ["google_sign_in"]),
          verifyPluginStubs: false,
        ),
        process: process,
      );

      expect(
        await runGuard(
          guard,
          stubs: [stubOf("google_sign_in", AppPlatform.all)],
        ),
        isTrue,
      );
      expect(process.analysedPlatforms, isEmpty);
    });

    test(
      'a stub only the App Distribution parameters reach stops the run',
      () async {
        final process = fakeProcess(
          reachedByParameter: {
            "--dart-define=ADS=1": {"workmanager"},
          },
        );
        final guard = guardWith(
          configWith(
            uploadType: UploadType.all,
            platform: AppPlatform.ios,
            pluginStubs: const PluginStubConfig(ios: ["workmanager"]),
            appDistributionExtraBuildParameters: ["--dart-define=ADS=1"],
          ),
          process: process,
        );

        expect(
          await runGuard(
            guard,
            stubs: [stubOf("workmanager", AppPlatform.ios)],
          ),
          isFalse,
        );
        expect(process.analysisParameters, [
          ["--dart-define=ADS=1"],
          <String>[],
        ]);
      },
    );

    test('targets with the same analysis parameters are built once', () async {
      final process = fakeProcess();
      final guard = guardWith(
        configWith(
          uploadType: UploadType.all,
          platform: AppPlatform.ios,
          pluginStubs: const PluginStubConfig(ios: ["workmanager"]),
          appDistributionExtraBuildParameters: ["--obfuscate"],
        ),
        process: process,
      );

      await runGuard(guard, stubs: [stubOf("workmanager", AppPlatform.ios)]);

      expect(process.analysedPlatforms, [AppPlatform.ios]);
    });

    test('an audit analyses every built platform', () async {
      final process = fakeProcess();
      final guard = guardWith(
        configWith(audit: true, verifyPluginStubs: false),
        process: process,
      );

      expect(await runGuard(guard), isTrue);
      expect(process.analysedPlatforms, [AppPlatform.android, AppPlatform.ios]);
    });
  });

  group('automatic stubs', () {
    test('a plugin unused on every platform is stubbed on all', () async {
      final process = fakeProcess();
      final guard = guardWith(
        configWith(pluginStubs: const PluginStubConfig(auto: true)),
        process: process,
      );

      final analysis = await guard.analyse();

      expect(analysis!.autoStubs, {"workmanager": AppPlatform.all});
      expect(process.analysedPlatforms, [AppPlatform.android, AppPlatform.ios]);
    });

    test('a reached plugin is not stubbed', () async {
      final guard = guardWith(
        configWith(pluginStubs: const PluginStubConfig(auto: true)),
        process: fakeProcess(reachedPackages: {"workmanager"}),
      );

      expect((await guard.analyse())!.autoStubs, isEmpty);
    });

    test('a kept plugin is not stubbed', () async {
      final guard = guardWith(
        configWith(
          pluginStubs: const PluginStubConfig(
            auto: true,
            keep: ["workmanager"],
          ),
        ),
      );

      expect((await guard.analyse())!.autoStubs, isEmpty);
    });

    test(
      'a plugin the app imports natively stays on that platform only',
      () async {
        projectFile("ios/Runner/AppDelegate.swift")
          ..createSync(recursive: true)
          ..writeAsStringSync("import Flutter\nimport workmanager\n");
        projectFile(
            "android/app/src/main/kotlin/GeneratedPluginRegistrant.java",
          )
          ..createSync(recursive: true)
          ..writeAsStringSync("import dev.fluttercommunity.workmanager.X;\n");
        final guard = guardWith(
          configWith(pluginStubs: const PluginStubConfig(auto: true)),
        );

        expect((await guard.analyse())!.autoStubs, {
          "workmanager": AppPlatform.android,
        });
      },
    );

    test('a configured stub is not stubbed again automatically', () async {
      final guard = guardWith(
        configWith(
          pluginStubs: const PluginStubConfig(auto: true, ios: ["workmanager"]),
        ),
      );

      expect((await guard.analyse())!.autoStubs, isEmpty);
    });

    test('a dry run builds nothing and stubs nothing', () async {
      final process = fakeProcess();
      final guard = guardWith(
        configWith(
          pluginStubs: const PluginStubConfig(auto: true),
          dryRun: true,
        ),
        process: process,
      );

      expect((await guard.analyse())!.autoStubs, isEmpty);
      expect(process.pubGetCount, 0);
    });
  });

  test('a project without guards does nothing', () async {
    final process = fakeProcess();
    final guard = guardWith(configWith(), process: process);

    expect(await runGuard(guard), isTrue);
    expect(process.pubGetCount, 0);
    expect(process.analysedPlatforms, isEmpty);
  });
}
