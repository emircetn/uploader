import 'dart:io';

import 'package:test/test.dart';
import 'package:uploader/src/helper/code_size_helper.dart';
import 'package:uploader/src/helper/plugin_audit_helper.dart';

void main() {
  final helper = PluginAuditHelper();
  late Directory cache;

  /// A plugin package whose lib/ holds [dart], or no lib/ at all when null.
  /// [iosDefault] is the federated implementation it names for iOS.
  Map<String, dynamic> plugin(
    String name, {
    String? dart,
    String? iosDefault,
    String? androidDefault,
  }) {
    final root = "${cache.path}/$name";
    Directory(root).createSync(recursive: true);
    if (dart != null) {
      File("$root/lib/$name.dart")
        ..createSync(recursive: true)
        ..writeAsStringSync(dart);
    }
    final defaults = {"ios": iosDefault, "android": androidDefault};
    if (defaults.values.any((value) => value != null)) {
      File("$root/pubspec.yaml").writeAsStringSync(
        "name: $name\n"
        "flutter:\n"
        "  plugin:\n"
        "    platforms:\n"
        "${[for (final MapEntry(:key, :value) in defaults.entries)
          if (value != null) "      $key:\n        default_package: $value\n"].join()}",
      );
    }
    return {"name": name, "path": root};
  }

  const channelPlugin =
      "import 'package:flutter/services.dart';\n"
      "const channel = MethodChannel('x');\n";

  const reachable = PackageCode(bytes: 5000, functions: ["signIn"]);
  const remnant = PackageCode(bytes: 300, functions: []);

  setUp(() => cache = Directory.systemTemp.createTempSync("plugin_audit"));
  tearDown(() => cache.deleteSync(recursive: true));

  PluginReach reachOf(List<PluginAuditEntry> entries, String name) =>
      entries.firstWhere((entry) => entry.name == name).reach;

  test('each plugin gets the verdict its code supports', () {
    final entries = helper.audit(
      plugins: [
        plugin(
          "google_sign_in",
          dart: "import 'package:google_sign_in_platform_interface/x.dart';",
        ),
        plugin("google_sign_in_ios", dart: channelPlugin),
        plugin("url_launcher_ios", dart: channelPlugin),
        plugin("media_kit_libs_ios_video"),
        plugin("firebase_messaging", dart: channelPlugin),
        plugin("audio_session", dart: channelPlugin),
        plugin("just_audio", dart: channelPlugin),
      ],
      dependencyGraph: [
        {
          "name": "google_sign_in",
          "dependencies": ["google_sign_in_ios"],
        },
        {
          "name": "just_audio",
          "dependencies": ["audio_session"],
        },
      ],
      code: {
        "google_sign_in": remnant,
        "url_launcher_ios": reachable,
        "just_audio": reachable,
      },
    );

    expect(reachOf(entries, "google_sign_in"), PluginReach.unused);
    expect(reachOf(entries, "google_sign_in_ios"), PluginReach.unused);
    expect(reachOf(entries, "url_launcher_ios"), PluginReach.live);
    expect(
      reachOf(entries, "media_kit_libs_ios_video"),
      PluginReach.nativeOnly,
    );
    expect(
      reachOf(entries, "firebase_messaging"),
      PluginReach.startupSideEffects,
    );
    expect(reachOf(entries, "audio_session"), PluginReach.usedByKeptPlugin);
  });

  test(
    'plugins the app imports or keeps stay, and so do their dependencies',
    () {
      final graph = [
        {
          "name": "google_mobile_ads",
          "dependencies": ["webview_flutter_wkwebview"],
        },
        {
          "name": "firebase_messaging",
          "dependencies": ["unused_helper"],
        },
      ];
      final plugins = [
        plugin("google_mobile_ads", dart: channelPlugin),
        plugin("webview_flutter_wkwebview", dart: channelPlugin),
        plugin("workmanager", dart: channelPlugin),
        plugin("firebase_messaging", dart: channelPlugin),
        plugin("unused_helper", dart: channelPlugin),
        plugin("dead", dart: channelPlugin),
      ];
      final entries = helper.audit(
        plugins: plugins,
        dependencyGraph: graph,
        code: const {},
        usedByApp: {"google_mobile_ads"},
        kept: {"workmanager"},
      );

      expect(reachOf(entries, "google_mobile_ads"), PluginReach.usedByApp);
      expect(
        reachOf(entries, "webview_flutter_wkwebview"),
        PluginReach.usedByKeptPlugin,
      );
      expect(reachOf(entries, "workmanager"), PluginReach.kept);
      expect(reachOf(entries, "unused_helper"), PluginReach.usedByKeptPlugin);
      expect(
        helper.suggestedStubs(
          platformKey: "ios",
          entries: entries,
          plugins: plugins,
          dependencyGraph: graph,
        ),
        ["dead"],
      );
    },
  );

  test('a library without channels or a platform interface is native only', () {
    final entries = helper.audit(
      plugins: [plugin("libs_only", dart: "library libs_only;\n")],
      dependencyGraph: const [],
      code: const {},
    );

    expect(entries.single.reach, PluginReach.nativeOnly);
  });

  test('only the top unused plugin of a federated group is suggested', () {
    final graph = [
      {
        "name": "google_sign_in",
        "dependencies": ["google_sign_in_ios", "google_sign_in_android"],
      },
    ];
    final plugins = [
      plugin(
        "google_sign_in",
        dart: channelPlugin,
        iosDefault: "google_sign_in_ios",
      ),
      plugin("google_sign_in_ios", dart: channelPlugin),
      plugin("workmanager", dart: channelPlugin),
    ];
    final entries = helper.audit(
      plugins: plugins,
      dependencyGraph: graph,
      code: const {},
    );

    expect(
      helper.suggestedStubs(
        platformKey: "ios",
        entries: entries,
        plugins: plugins,
        dependencyGraph: graph,
      ),
      ["google_sign_in", "workmanager"],
    );
  });

  test('an implementation the other built platform shares is suggested, '
      'since stubbing its plugin on one platform keeps it in the graph', () {
    final graph = [
      {
        "name": "foo",
        "dependencies": ["foo_mobile"],
      },
    ];
    final plugins = [
      plugin(
        "foo",
        dart: channelPlugin,
        iosDefault: "foo_mobile",
        androidDefault: "foo_mobile",
      ),
      plugin("foo_mobile", dart: channelPlugin),
    ];
    final entries = helper.audit(
      plugins: plugins,
      dependencyGraph: graph,
      code: const {},
    );

    expect(
      helper.suggestedStubs(
        platformKey: "ios",
        entries: entries,
        plugins: plugins,
        dependencyGraph: graph,
      ),
      ["foo", "foo_mobile"],
    );
  });

  test('a plain dependency of an unused plugin is suggested too, since '
      'stubbing the plugin leaves it in the graph', () {
    final graph = [
      {
        "name": "just_audio",
        "dependencies": ["audio_session"],
      },
      {
        "name": "live_activities",
        "dependencies": ["flutter_app_group_directory"],
      },
    ];
    final plugins = [
      plugin("just_audio", dart: channelPlugin),
      plugin("audio_session", dart: channelPlugin),
      plugin("live_activities", dart: channelPlugin),
      plugin("flutter_app_group_directory", dart: channelPlugin),
    ];
    final entries = helper.audit(
      plugins: plugins,
      dependencyGraph: graph,
      code: const {},
    );

    expect(
      helper.suggestedStubs(
        platformKey: "ios",
        entries: entries,
        plugins: plugins,
        dependencyGraph: graph,
      ),
      [
        "audio_session",
        "flutter_app_group_directory",
        "just_audio",
        "live_activities",
      ],
    );
  });

  test('an implementation another unused plugin depends on directly is '
      'suggested, since that plugin keeps it in the graph', () {
    final graph = [
      {
        "name": "google_sign_in",
        "dependencies": ["google_sign_in_ios"],
      },
      {
        "name": "sign_in_helper",
        "dependencies": ["google_sign_in_ios"],
      },
    ];
    final plugins = [
      plugin(
        "google_sign_in",
        dart: channelPlugin,
        iosDefault: "google_sign_in_ios",
      ),
      plugin("google_sign_in_ios", dart: channelPlugin),
      plugin("sign_in_helper", dart: channelPlugin),
    ];
    final entries = helper.audit(
      plugins: plugins,
      dependencyGraph: graph,
      code: const {},
    );

    expect(
      helper.suggestedStubs(
        platformKey: "ios",
        entries: entries,
        plugins: plugins,
        dependencyGraph: graph,
      ),
      ["google_sign_in", "google_sign_in_ios", "sign_in_helper"],
    );
  });

  test('a mediation adapter of a live ads plugin stays, and so does what '
      'the adapter depends on', () {
    final graph = [
      {
        "name": "gma_mediation_applovin",
        "dependencies": ["google_mobile_ads", "applovin_helper"],
      },
      {
        "name": "gma_mediation_unity",
        "dependencies": ["gma_mediation_applovin"],
      },
      {
        "name": "google_mobile_ads",
        "dependencies": ["webview_flutter_android"],
      },
    ];
    final plugins = [
      plugin("google_mobile_ads", dart: channelPlugin),
      plugin("webview_flutter_android", dart: channelPlugin),
      plugin("gma_mediation_applovin", dart: channelPlugin),
      plugin("gma_mediation_unity", dart: channelPlugin),
      plugin("applovin_helper", dart: channelPlugin),
      plugin("dead", dart: channelPlugin),
    ];
    final entries = helper.audit(
      plugins: plugins,
      dependencyGraph: graph,
      code: const {"google_mobile_ads": reachable},
    );

    expect(
      reachOf(entries, "gma_mediation_applovin"),
      PluginReach.extendsKeptPlugin,
    );
    expect(
      reachOf(entries, "gma_mediation_unity"),
      PluginReach.extendsKeptPlugin,
    );
    expect(reachOf(entries, "applovin_helper"), PluginReach.usedByKeptPlugin);
    expect(
      reachOf(entries, "webview_flutter_android"),
      PluginReach.usedByKeptPlugin,
    );
    expect(
      helper.suggestedStubs(
        platformKey: "android",
        entries: entries,
        plugins: plugins,
        dependencyGraph: graph,
      ),
      ["dead"],
    );
  });

  test('a plugin that both a staying plugin needs and that extends one still '
      'protects what extends it', () {
    final graph = [
      {
        "name": "ads_wrapper",
        "dependencies": ["mediation_core"],
      },
      {
        "name": "mediation_core",
        "dependencies": ["google_mobile_ads"],
      },
      {
        "name": "mediation_adapter",
        "dependencies": ["mediation_core"],
      },
    ];
    final entries = helper.audit(
      plugins: [
        plugin("ads_wrapper", dart: channelPlugin),
        plugin("mediation_core", dart: channelPlugin),
        plugin("google_mobile_ads", dart: channelPlugin),
        plugin("mediation_adapter", dart: channelPlugin),
      ],
      dependencyGraph: graph,
      code: const {"ads_wrapper": reachable, "google_mobile_ads": reachable},
    );

    expect(reachOf(entries, "mediation_core"), PluginReach.extendsKeptPlugin);
    expect(
      reachOf(entries, "mediation_adapter"),
      PluginReach.extendsKeptPlugin,
    );
  });

  test('a shared native library or a plugin kept for a dependent protects '
      'nothing that depends on it', () {
    final graph = [
      {
        "name": "image_picker_android",
        "dependencies": ["flutter_plugin_android_lifecycle"],
      },
      {
        "name": "google_mobile_ads",
        "dependencies": ["webview_flutter_android"],
      },
      {
        "name": "webview_flutter",
        "dependencies": ["webview_flutter_android"],
      },
    ];
    final plugins = [
      plugin("flutter_plugin_android_lifecycle"),
      plugin("image_picker_android", dart: channelPlugin),
      plugin("google_mobile_ads", dart: channelPlugin),
      plugin("webview_flutter_android", dart: channelPlugin),
      plugin("webview_flutter", dart: channelPlugin),
    ];
    final entries = helper.audit(
      plugins: plugins,
      dependencyGraph: graph,
      code: const {"google_mobile_ads": reachable},
    );

    expect(
      reachOf(entries, "flutter_plugin_android_lifecycle"),
      PluginReach.nativeOnly,
    );
    expect(
      reachOf(entries, "webview_flutter_android"),
      PluginReach.usedByKeptPlugin,
    );
    expect(
      helper.suggestedStubs(
        platformKey: "android",
        entries: entries,
        plugins: plugins,
        dependencyGraph: graph,
      ),
      ["image_picker_android", "webview_flutter"],
    );
  });

  test('the report lists live plugins first, the largest on top', () {
    final entries = helper.audit(
      plugins: [
        plugin("small", dart: channelPlugin),
        plugin("big", dart: channelPlugin),
        plugin("dead", dart: channelPlugin),
      ],
      dependencyGraph: const [],
      code: {
        "small": const PackageCode(bytes: 10, functions: ["a"]),
        "big": const PackageCode(bytes: 9000, functions: ["b"]),
      },
    );

    expect(entries.map((entry) => entry.name), ["big", "small", "dead"]);
    expect(
      helper.formatReport(
        platformKey: "ios",
        entries: entries,
        suggestedStubs: ["dead"],
      ),
      contains("can be stubbed on ios: dead"),
    );
  });
}
