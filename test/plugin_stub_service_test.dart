import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/plugin_stub_helper.dart';
import 'package:uploader/src/model/plugin_stub_config.dart';
import 'package:uploader/src/service/plugin_stub_service.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:yaml/yaml.dart';

/// Stands in for `flutter pub get`: it writes the package config and plugin
/// list pub and Flutter would produce for the current overrides.
class FakeProcessService extends ProcessService {
  final String projectRoot;
  final String cachedFooRoot;

  /// Simulates another dependency keeping `foo_ios` in the graph.
  final bool keepsImplementation;

  int pubGetCount = 0;

  FakeProcessService({
    required this.projectRoot,
    required this.cachedFooRoot,
    this.keepsImplementation = false,
  });

  @override
  Future<bool> pubGet() async {
    pubGetCount++;
    final overrides = File("$projectRoot/pubspec_overrides.yaml");
    final isStubbed =
        overrides.existsSync() &&
        overrides.readAsStringSync().contains("plugin_stubs/foo");

    final fooRoot = isStubbed
        ? "../build/uploader/plugin_stubs/foo/"
        : Uri.directory(cachedFooRoot).toString();
    File("$projectRoot/.dart_tool/package_config.json")
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          "configVersion": 2,
          "packages": [
            {"name": "foo", "rootUri": fooRoot, "packageUri": "lib/"},
          ],
        }),
      );

    final iosPlugins = [
      if (!isStubbed || keepsImplementation) "foo_ios",
      "kept_plugin",
    ];
    File("$projectRoot/.flutter-plugins-dependencies").writeAsStringSync(
      jsonEncode({
        "plugins": {
          "ios": [
            for (final name in iosPlugins) {"name": name},
          ],
          "android": [
            {"name": "foo_android"},
          ],
        },
      }),
    );

    if (isStubbed) {
      File("$projectRoot/pubspec.lock").writeAsStringSync("stubbed lock\n");
    }
    return true;
  }
}

void main() {
  late Directory sandbox;
  late String projectRoot;
  late String cachedFooRoot;

  const pubspec = '''
name: app
dependency_overrides:
  camera: 0.11.2
''';

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync("plugin_stub_test");
    projectRoot = "${sandbox.path}/app";
    cachedFooRoot = "${sandbox.path}/cache/foo";

    File("$projectRoot/pubspec.yaml")
      ..createSync(recursive: true)
      ..writeAsStringSync(pubspec);
    File("$projectRoot/pubspec.lock").writeAsStringSync("original lock\n");
    File("$projectRoot/ios/Podfile.lock")
      ..createSync(recursive: true)
      ..writeAsStringSync("original pods\n");

    File("$cachedFooRoot/pubspec.yaml")
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: foo
version: 1.0.0
dependencies:
  foo_ios: ^1.0.0
  foo_android: ^1.0.0
flutter:
  plugin:
    platforms:
      ios:
        default_package: foo_ios
      android:
        default_package: foo_android
''');
    File("$cachedFooRoot/lib/foo.dart")
      ..createSync(recursive: true)
      ..writeAsStringSync("void foo() {}\n");
    File("$cachedFooRoot/ios/Classes/Foo.m")
      ..createSync(recursive: true)
      ..writeAsStringSync("// native\n");
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  PluginStubService serviceWith(
    FakeProcessService processService, {
    bool dryRun = false,
  }) => PluginStubService(
    config: const PluginStubConfig(ios: ["foo"]),
    processService: processService,
    dryRun: dryRun,
    projectRoot: projectRoot,
  );

  FakeProcessService fakeProcess({bool keepsImplementation = false}) =>
      FakeProcessService(
        projectRoot: projectRoot,
        cachedFooRoot: cachedFooRoot,
        keepsImplementation: keepsImplementation,
      );

  File projectFile(String relativePath) => File("$projectRoot/$relativePath");

  test('a run stubs the plugin and restores every file afterwards', () async {
    final process = fakeProcess();
    final service = serviceWith(process);

    expect(await service.apply(), isTrue);

    final overrides = loadYaml(
      projectFile("pubspec_overrides.yaml").readAsStringSync(),
    );
    expect(overrides["dependency_overrides"]["camera"], "0.11.2");
    expect(
      overrides["dependency_overrides"]["foo"]["path"],
      "build/uploader/plugin_stubs/foo",
    );

    final stubRoot = "build/uploader/plugin_stubs/foo";
    final stubPubspec = loadYaml(
      projectFile("$stubRoot/pubspec.yaml").readAsStringSync(),
    );
    expect(stubPubspec["flutter"]["plugin"]["platforms"].keys, ["android"]);
    expect(stubPubspec["dependencies"].keys, ["foo_android"]);
    expect(projectFile("$stubRoot/lib/foo.dart").existsSync(), isTrue);
    expect(Directory("$projectRoot/$stubRoot/ios").existsSync(), isFalse);

    await service.restore();

    expect(projectFile("pubspec.lock").readAsStringSync(), "original lock\n");
    expect(
      projectFile("ios/Podfile.lock").readAsStringSync(),
      "original pods\n",
    );
    expect(projectFile("pubspec_overrides.yaml").existsSync(), isFalse);
    expect(
      Directory("$projectRoot/build/uploader/plugin_stubs").existsSync(),
      isFalse,
    );
    expect(process.pubGetCount, 3);
  });

  test('a project pubspec_overrides.yaml is the base and comes back', () async {
    const ownOverrides = "dependency_overrides:\n  intl: 0.20.2\n";
    projectFile("pubspec_overrides.yaml").writeAsStringSync(ownOverrides);
    final service = serviceWith(fakeProcess());

    expect(await service.apply(), isTrue);

    final overrides = loadYaml(
      projectFile("pubspec_overrides.yaml").readAsStringSync(),
    )["dependency_overrides"];
    expect(overrides["intl"], "0.20.2");
    expect(overrides.containsKey("camera"), isFalse);

    await service.restore();

    expect(
      projectFile("pubspec_overrides.yaml").readAsStringSync(),
      ownOverrides,
    );
  });

  test(
    'a plugin still registered fails the run and restores the project',
    () async {
      final service = serviceWith(fakeProcess(keepsImplementation: true));

      expect(await service.apply(), isFalse);

      expect(projectFile("pubspec.lock").readAsStringSync(), "original lock\n");
      expect(projectFile("pubspec_overrides.yaml").existsSync(), isFalse);
    },
  );

  test(
    'a package outside the graph fails before anything is stubbed',
    () async {
      final service = PluginStubService(
        config: const PluginStubConfig(all: ["missing"]),
        processService: fakeProcess(),
        projectRoot: projectRoot,
      );

      expect(await service.apply(), isFalse);
      expect(projectFile("pubspec_overrides.yaml").existsSync(), isFalse);
    },
  );

  test('the next run restores what a killed run left behind', () async {
    final killed = serviceWith(fakeProcess());
    expect(await killed.apply(), isTrue);

    final nextRun = serviceWith(fakeProcess());
    expect(await nextRun.recoverInterruptedRun(), isTrue);

    expect(projectFile("pubspec.lock").readAsStringSync(), "original lock\n");
    expect(projectFile("pubspec_overrides.yaml").existsSync(), isFalse);
    expect(
      Directory("$projectRoot/build/uploader/plugin_stub_backup").existsSync(),
      isFalse,
    );

    await killed.restore();
  });

  test('a marker without a backup removes the generated overrides', () async {
    projectFile(
      "pubspec_overrides.yaml",
    ).writeAsStringSync("$pluginStubOverridesMarker\n{}\n");

    expect(await serviceWith(fakeProcess()).recoverInterruptedRun(), isTrue);
    expect(projectFile("pubspec_overrides.yaml").existsSync(), isFalse);
  });

  test('a dry run touches nothing', () async {
    final process = fakeProcess();
    final service = serviceWith(process, dryRun: true);

    expect(await service.apply(), isTrue);
    await service.restore();

    expect(process.pubGetCount, 0);
    expect(projectFile("pubspec_overrides.yaml").existsSync(), isFalse);
    expect(Directory("$projectRoot/build").existsSync(), isFalse);
  });

  test('pruned assets get a copy that keeps the native side', () async {
    File("$cachedFooRoot/pubspec.yaml").writeAsStringSync(
      "${File("$cachedFooRoot/pubspec.yaml").readAsStringSync()}"
      "  assets:\n    - assets/\n",
    );
    for (final asset in ["assets/paywall.mp4", "assets/logo.png"]) {
      File("$cachedFooRoot/$asset")
        ..createSync(recursive: true)
        ..writeAsStringSync("bytes");
    }
    final service = PluginStubService(
      config: const PluginStubConfig(
        prunedAssets: {
          "foo": ["assets/*.mp4"],
        },
      ),
      processService: fakeProcess(),
      projectRoot: projectRoot,
    );

    expect(await service.apply(), isTrue);

    final stubRoot = "build/uploader/plugin_stubs/foo";
    final stubPubspec = loadYaml(
      projectFile("$stubRoot/pubspec.yaml").readAsStringSync(),
    );
    expect(stubPubspec["flutter"]["assets"], ["assets/logo.png"]);
    expect(stubPubspec["flutter"]["plugin"]["platforms"].keys, [
      "ios",
      "android",
    ]);
    expect(Directory("$projectRoot/$stubRoot/ios").existsSync(), isTrue);
    expect(service.appliedPlans.single.prunedAssets, ["assets/paywall.mp4"]);

    await service.restore();
  });

  test('pruned fonts get a copy without the listed families', () async {
    File("$cachedFooRoot/pubspec.yaml").writeAsStringSync(
      "${File("$cachedFooRoot/pubspec.yaml").readAsStringSync()}"
      "  fonts:\n"
      "    - family: FooThin\n"
      "      fonts:\n"
      "        - asset: fonts/thin.ttf\n"
      "    - family: FooRegular\n"
      "      fonts:\n"
      "        - asset: fonts/regular.ttf\n",
    );
    final service = PluginStubService(
      config: const PluginStubConfig(
        prunedFonts: {
          "foo": ["FooThin"],
        },
      ),
      processService: fakeProcess(),
      projectRoot: projectRoot,
    );

    expect(await service.apply(), isTrue);

    final stubPubspec = loadYaml(
      projectFile(
        "build/uploader/plugin_stubs/foo/pubspec.yaml",
      ).readAsStringSync(),
    );
    expect(
      (stubPubspec["flutter"]["fonts"] as List).map((font) => font["family"]),
      ["FooRegular"],
    );
    expect(service.appliedPlans.single.prunedFonts, ["FooThin"]);

    await service.restore();
  });

  test('an automatic stub is applied like a configured one', () async {
    final service = PluginStubService(
      config: const PluginStubConfig(auto: true),
      processService: fakeProcess(),
      projectRoot: projectRoot,
    );

    expect(await service.apply(autoStubs: {"foo": AppPlatform.ios}), isTrue);
    expect(service.appliedPlans.single.name, "foo");
    expect(service.appliedPlans.single.strippedPlatform, AppPlatform.ios);

    await service.restore();
  });

  test(
    'an automatic stub a configured stub took out of the graph is skipped',
    () async {
      final service = serviceWith(fakeProcess());

      expect(
        await service.apply(autoStubs: {"foo_ios": AppPlatform.ios}),
        isTrue,
      );
      expect(service.appliedPlans.map((plan) => plan.name), ["foo"]);

      await service.restore();
    },
  );

  test(
    'files the analysis build rewrites come back even with nothing stubbed',
    () async {
      final service = PluginStubService(
        config: const PluginStubConfig(auto: true),
        processService: fakeProcess(),
        projectRoot: projectRoot,
      );

      service.backUp();
      projectFile("ios/Podfile.lock").writeAsStringSync("analysis pods\n");
      expect(await service.apply(), isTrue);
      await service.restore();

      expect(
        projectFile("ios/Podfile.lock").readAsStringSync(),
        "original pods\n",
      );
    },
  );

  test('a second run of the same service is restored too', () async {
    final service = serviceWith(fakeProcess());

    for (var run = 0; run < 2; run++) {
      expect(await service.apply(), isTrue);
      expect(projectFile("pubspec_overrides.yaml").existsSync(), isTrue);
      await service.restore();

      expect(projectFile("pubspec_overrides.yaml").existsSync(), isFalse);
      expect(projectFile("pubspec.lock").readAsStringSync(), "original lock\n");
      expect(service.appliedPlans, isEmpty);
    }
  });

  test('a project without stubs is left alone', () async {
    final process = fakeProcess();
    final service = PluginStubService(
      config: const PluginStubConfig(),
      processService: process,
      projectRoot: projectRoot,
    );

    expect(await service.recoverInterruptedRun(), isTrue);
    expect(await service.apply(), isTrue);
    await service.restore();

    expect(process.pubGetCount, 0);
  });
}
