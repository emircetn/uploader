import 'dart:io';

import 'package:test/test.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/plugin_stub_helper.dart';
import 'package:uploader/src/model/plugin_stub_config.dart';
import 'package:yaml/yaml.dart';

void main() {
  final helper = PluginStubHelper();

  Map<String, dynamic> federatedPubspec() => {
    "name": "foo",
    "version": "1.2.3",
    "environment": {"sdk": ">=3.0.0 <4.0.0"},
    "resolution": "workspace",
    "dependencies": {
      "flutter": {"sdk": "flutter"},
      "foo_platform_interface": "^1.0.0",
      "foo_ios": "^1.0.0",
      "foo_android": "^1.0.0",
      "foo_shared": {"path": "../foo_shared"},
    },
    "dev_dependencies": {"test": "any"},
    "flutter": {
      "plugin": {
        "platforms": {
          "ios": {"default_package": "foo_ios"},
          "android": {"default_package": "foo_android"},
        },
      },
      "assets": ["assets/"],
    },
  };

  group('planStub', () {
    test(
      'stubbing every platform drops the plugin and its implementations',
      () {
        final plan = helper.planStub(
          name: "foo",
          pubspec: federatedPubspec(),
          strippedPlatform: AppPlatform.all,
          packageRoot: "/cache/foo",
        );

        expect(plan.removesNativeCode, isTrue);
        expect(plan.pubspec["flutter"], {
          "assets": ["assets/"],
        });
        expect(plan.droppedImplementations, ["foo_ios", "foo_android"]);
        expect(
          (plan.pubspec["dependencies"] as Map).keys,
          containsAll(["flutter", "foo_platform_interface"]),
        );
        expect(
          (plan.pubspec["dependencies"] as Map).keys,
          isNot(contains("foo_ios")),
        );
      },
    );

    test('stubbing one platform keeps the other one registered', () {
      final plan = helper.planStub(
        name: "foo",
        pubspec: federatedPubspec(),
        strippedPlatform: AppPlatform.ios,
        packageRoot: "/cache/foo",
      );

      expect(plan.pubspec["flutter"]["plugin"]["platforms"], {
        "android": {"default_package": "foo_android"},
      });
      expect(plan.droppedImplementations, ["foo_ios"]);
      expect(
        (plan.pubspec["dependencies"] as Map).keys,
        contains("foo_android"),
      );
      expect(plan.strippedPlatformKeys, ["ios"]);
    });

    test('an implementation another platform still uses is kept', () {
      final pubspec = federatedPubspec();
      pubspec["flutter"]["plugin"]["platforms"] = {
        "ios": {"default_package": "foo_foundation"},
        "macos": {"default_package": "foo_foundation"},
      };
      pubspec["dependencies"]["foo_foundation"] = "^1.0.0";

      final plan = helper.planStub(
        name: "foo",
        pubspec: pubspec,
        strippedPlatform: AppPlatform.ios,
        packageRoot: "/cache/foo",
      );

      expect(plan.droppedImplementations, isEmpty);
      expect(
        (plan.pubspec["dependencies"] as Map).keys,
        contains("foo_foundation"),
      );
    });

    test('an inline plugin loses only the stripped platform', () {
      final plan = helper.planStub(
        name: "bar",
        pubspec: {
          "name": "bar",
          "flutter": {
            "plugin": {
              "platforms": {
                "ios": {"pluginClass": "BarPlugin"},
                "android": {"package": "com.bar", "pluginClass": "BarPlugin"},
              },
            },
          },
        },
        strippedPlatform: AppPlatform.android,
        packageRoot: "/cache/bar",
      );

      expect(plan.removesNativeCode, isTrue);
      expect(plan.pubspec["flutter"]["plugin"]["platforms"].keys, ["ios"]);
      expect(plan.droppedImplementations, isEmpty);
    });

    test('a package without native code on that platform changes nothing', () {
      final pureDart = helper.planStub(
        name: "baz",
        pubspec: {"name": "baz"},
        strippedPlatform: AppPlatform.all,
        packageRoot: "/cache/baz",
      );
      final androidOnly = helper.planStub(
        name: "qux",
        pubspec: {
          "name": "qux",
          "flutter": {
            "plugin": {
              "platforms": {
                "android": {"package": "com.qux", "pluginClass": "Qux"},
              },
            },
          },
        },
        strippedPlatform: AppPlatform.ios,
        packageRoot: "/cache/qux",
      );

      expect(pureDart.removesNativeCode, isFalse);
      expect(androidOnly.removesNativeCode, isFalse);
      expect(androidOnly.pubspec["flutter"]["plugin"], isNotNull);
    });

    test('a plugin without a platforms map is only stubbed on every '
        'platform', () {
      Map<String, dynamic> legacy() => {
        "name": "old",
        "flutter": {
          "plugin": {"androidPackage": "com.old", "pluginClass": "OldPlugin"},
        },
      };

      final onIos = helper.planStub(
        name: "old",
        pubspec: legacy(),
        strippedPlatform: AppPlatform.ios,
        packageRoot: "/cache/old",
      );
      final everywhere = helper.planStub(
        name: "old",
        pubspec: legacy(),
        strippedPlatform: AppPlatform.all,
        packageRoot: "/cache/old",
      );

      expect(onIos.removesNativeCode, isFalse);
      expect(onIos.pubspec["flutter"]["plugin"], isNotNull);
      expect(everywhere.removesNativeCode, isTrue);
      expect(everywhere.pubspec["flutter"], isEmpty);
    });

    test('the copy still finds relative path dependencies', () {
      final plan = helper.planStub(
        name: "foo",
        pubspec: federatedPubspec(),
        strippedPlatform: AppPlatform.all,
        packageRoot: "/repo/packages/foo",
      );

      expect(plan.pubspec["dependencies"]["foo_shared"], {
        "path": "/repo/packages/foo_shared",
      });
    });

    test('workspace and dev only keys are dropped', () {
      final plan = helper.planStub(
        name: "foo",
        pubspec: federatedPubspec(),
        strippedPlatform: AppPlatform.all,
        packageRoot: "/cache/foo",
      );

      expect(plan.pubspec.containsKey("resolution"), isFalse);
      expect(plan.pubspec.containsKey("dev_dependencies"), isFalse);
      expect(plan.pubspec["version"], "1.2.3");
    });

    test('reads a pubspec parsed from YAML', () {
      final pubspec = loadYaml('''
name: foo
version: 1.0.0
dependencies:
  foo_ios: ^1.0.0
flutter:
  plugin:
    platforms:
      ios:
        default_package: foo_ios
''');

      final plan = helper.planStub(
        name: "foo",
        pubspec: pubspec,
        strippedPlatform: AppPlatform.ios,
        packageRoot: "/cache/foo",
      );

      expect(plan.droppedImplementations, ["foo_ios"]);
      expect(loadYaml(helper.encodePubspec(plan.pubspec))["name"], "foo");
    });
  });

  group('mergeOverrides', () {
    test('keeps the project overrides and lets a stub win', () {
      final overrides = helper.mergeOverrides(
        baseOverrides: {
          "camera": "0.11.2",
          "foo": {
            "git": {"url": "https://example.com/foo.git"},
          },
        },
        stubPaths: {"foo": "build/uploader/plugin_stubs/foo"},
      );

      expect(overrides, {
        "camera": "0.11.2",
        "foo": {"path": "build/uploader/plugin_stubs/foo"},
      });
    });

    test('the overrides file is marked and parses as YAML', () {
      final file = helper.encodeOverridesFile({
        "foo": {"path": "build/uploader/plugin_stubs/foo"},
      });

      expect(file.split("\n").first, pluginStubOverridesMarker);
      expect(
        loadYaml(file)["dependency_overrides"]["foo"]["path"],
        "build/uploader/plugin_stubs/foo",
      );
    });
  });

  group('packageRoot', () {
    final packageConfigUri = Uri.file("/app/.dart_tool/package_config.json");
    final packageConfig = {
      "packages": [
        {"name": "foo", "rootUri": "file:///cache/foo-1.0.0/"},
        {"name": "bar", "rootUri": "../build/uploader/plugin_stubs/bar/"},
      ],
    };

    test('resolves absolute and relative roots', () {
      expect(
        helper.packageRoot(
          packageConfig: packageConfig,
          packageConfigUri: packageConfigUri,
          name: "foo",
        ),
        "/cache/foo-1.0.0",
      );
      expect(
        helper.packageRoot(
          packageConfig: packageConfig,
          packageConfigUri: packageConfigUri,
          name: "bar",
        ),
        "/app/build/uploader/plugin_stubs/bar",
      );
    });

    test('a package outside the graph has no root', () {
      expect(
        helper.packageRoot(
          packageConfig: packageConfig,
          packageConfigUri: packageConfigUri,
          name: "missing",
        ),
        isNull,
      );
    });
  });

  group('remainingRegistrations', () {
    final plan = helper.planStub(
      name: "foo",
      pubspec: federatedPubspec(),
      strippedPlatform: AppPlatform.ios,
      packageRoot: "/cache/foo",
    );

    Map<String, dynamic> pluginsWith({
      List<String> ios = const [],
      List<String> android = const [],
    }) => {
      "plugins": {
        "ios": [
          for (final name in ios) {"name": name},
        ],
        "android": [
          for (final name in android) {"name": name},
        ],
      },
    };

    test('passes once the stub and its implementation are gone', () {
      expect(
        helper.remainingRegistrations(
          pluginsDependencies: pluginsWith(
            ios: ["other"],
            android: ["foo_android"],
          ),
          plans: [plan],
        ),
        isEmpty,
      );
    });

    test('reports an implementation another dependency keeps', () {
      expect(
        helper.remainingRegistrations(
          pluginsDependencies: pluginsWith(ios: ["foo_ios"]),
          plans: [plan],
        ),
        ["foo_ios (ios)"],
      );
    });

    test('an app with no plugins left passes', () {
      expect(
        helper.remainingRegistrations(pluginsDependencies: null, plans: [plan]),
        isEmpty,
      );
    });
  });

  group('PluginStubConfig', () {
    test('a package listed for both platforms is stripped everywhere', () {
      const config = PluginStubConfig(
        all: ["a"],
        ios: ["b", "c"],
        android: ["c", "d"],
      );

      expect(config.strippedPlatforms, {
        "a": AppPlatform.all,
        "b": AppPlatform.ios,
        "c": AppPlatform.all,
        "d": AppPlatform.android,
      });
    });

    test('an empty config strips nothing', () {
      expect(const PluginStubConfig().isEmpty, isTrue);
    });

    test('pruned assets alone make the config non-empty', () {
      const config = PluginStubConfig(
        ios: ["a"],
        prunedAssets: {
          "b": ["assets/**"],
        },
      );

      expect(config.isEmpty, isFalse);
      expect(config.packageNames, {"a", "b"});
    });
  });

  group('pruned assets', () {
    late Directory packageRoot;

    void writeAsset(String relativePath, int bytes) {
      File("${packageRoot.path}/$relativePath")
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(bytes, 0));
    }

    setUp(() {
      packageRoot = Directory.systemTemp.createTempSync("pruned_assets_test");
      writeAsset("assets/videos/intro.mp4", 1000);
      writeAsset("assets/videos/2.0x/intro.mp4", 500);
      writeAsset("assets/videos/outro.mp4", 300);
      writeAsset("assets/images/logo.png", 10);
      writeAsset("assets/config.json", 5);
    });

    tearDown(() => packageRoot.deleteSync(recursive: true));

    PluginStubPlan pruning(List<dynamic> assets, List<String> patterns) =>
        helper.planStub(
          name: "purchases",
          pubspec: {
            "name": "purchases",
            "flutter": {"assets": assets},
          },
          strippedPlatform: null,
          packageRoot: packageRoot.path,
          assetPatterns: patterns,
        );

    test('a folder entry is replaced by the files it keeps', () {
      final plan = pruning(
        ["assets/videos/", "assets/images/"],
        ["assets/videos/intro.mp4"],
      );

      expect(plan.pubspec["flutter"]["assets"], [
        "assets/videos/outro.mp4",
        "assets/images/",
      ]);
      expect(plan.prunedAssets, ["assets/videos/intro.mp4"]);
    });

    test('resolution variants count towards the pruned size', () {
      final plan = pruning(["assets/videos/"], ["assets/videos/intro.mp4"]);

      expect(plan.prunedAssetBytes, 1500);
    });

    test('a fully pruned folder leaves the assets list', () {
      final plan = pruning(["assets/videos/"], ["assets/videos/**"]);

      expect(plan.pubspec["flutter"].containsKey("assets"), isFalse);
      expect(plan.prunedAssets, [
        "assets/videos/intro.mp4",
        "assets/videos/outro.mp4",
      ]);
      expect(plan.changesPackage, isTrue);
    });

    test('a file entry is dropped when it matches', () {
      final plan = pruning(
        ["assets/config.json", "assets/images/"],
        ["**/*.json"],
      );

      expect(plan.pubspec["flutter"]["assets"], ["assets/images/"]);
    });

    test('a map entry keeps its flavors on every file it expands to', () {
      final plan = pruning(
        [
          {
            "path": "assets/videos/",
            "flavors": ["paid"],
          },
        ],
        ["assets/videos/intro.mp4"],
      );

      expect(plan.pubspec["flutter"]["assets"], [
        {
          "path": "assets/videos/outro.mp4",
          "flavors": ["paid"],
        },
      ]);
    });

    test('patterns that match nothing change nothing', () {
      final plan = pruning(["assets/videos/"], ["assets/fonts/**"]);

      expect(plan.pubspec["flutter"]["assets"], ["assets/videos/"]);
      expect(plan.changesPackage, isFalse);
    });

    test('pruning assets of a plugin leaves its native side alone', () {
      final plan = helper.planStub(
        name: "foo",
        pubspec: federatedPubspec(),
        strippedPlatform: null,
        packageRoot: packageRoot.path,
        assetPatterns: ["assets/*.json"],
      );

      expect(plan.removesNativeCode, isFalse);
      expect(plan.strippedPlatformKeys, isEmpty);
      expect(plan.pubspec["flutter"]["plugin"]["platforms"].keys, [
        "ios",
        "android",
      ]);
      expect(plan.prunedAssets, ["assets/config.json"]);
      expect(plan.pubspec["flutter"].containsKey("assets"), isFalse);
    });

    test('a folder entry covers only the files directly inside it', () {
      final plan = pruning(["assets/"], ["assets/videos/**"]);

      expect(plan.pubspec["flutter"]["assets"], ["assets/"]);
      expect(plan.prunedAssets, isEmpty);
    });
  });
}
