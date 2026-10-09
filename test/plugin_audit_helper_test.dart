import 'dart:io';

import 'package:test/test.dart';
import 'package:uploader/src/helper/code_size_helper.dart';
import 'package:uploader/src/helper/plugin_audit_helper.dart';

void main() {
  final helper = PluginAuditHelper();
  late Directory cache;

  /// A plugin package whose lib/ holds [dart], or no lib/ at all when null.
  Map<String, dynamic> plugin(String name, {String? dart}) {
    final root = "${cache.path}/$name";
    Directory(root).createSync(recursive: true);
    if (dart != null) {
      File("$root/lib/$name.dart")
        ..createSync(recursive: true)
        ..writeAsStringSync(dart);
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
      final entries = helper.audit(
        plugins: [
          plugin("google_mobile_ads", dart: channelPlugin),
          plugin("webview_flutter_wkwebview", dart: channelPlugin),
          plugin("workmanager", dart: channelPlugin),
          plugin("firebase_messaging", dart: channelPlugin),
          plugin("unused_helper", dart: channelPlugin),
          plugin("dead", dart: channelPlugin),
        ],
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
      expect(helper.suggestedStubs(entries: entries, dependencyGraph: graph), [
        "dead",
      ]);
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
    final entries = helper.audit(
      plugins: [
        plugin("google_sign_in", dart: channelPlugin),
        plugin("google_sign_in_ios", dart: channelPlugin),
        plugin("workmanager", dart: channelPlugin),
      ],
      dependencyGraph: graph,
      code: const {},
    );

    expect(helper.suggestedStubs(entries: entries, dependencyGraph: graph), [
      "google_sign_in",
      "workmanager",
    ]);
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
