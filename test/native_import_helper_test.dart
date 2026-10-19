import 'dart:io';

import 'package:test/test.dart';
import 'package:uploader/src/helper/native_import_helper.dart';

void main() {
  final helper = NativeImportHelper();
  late Directory sandbox;

  setUp(() => sandbox = Directory.systemTemp.createTempSync("native_import"));
  tearDown(() => sandbox.deleteSync(recursive: true));

  Map<String, dynamic> plugin(String name, {String? androidPackage}) {
    final root = "${sandbox.path}/cache/$name";
    File("$root/pubspec.yaml")
      ..createSync(recursive: true)
      ..writeAsStringSync(
        androidPackage == null
            ? "name: $name\n"
            : "name: $name\n"
                  "flutter:\n"
                  "  plugin:\n"
                  "    platforms:\n"
                  "      android:\n"
                  "        package: $androidPackage\n",
      );
    return {"name": name, "path": root};
  }

  void writeSource(String relativePath, String content) =>
      File("${sandbox.path}/app/$relativePath")
        ..createSync(recursive: true)
        ..writeAsStringSync(content);

  Set<String> importedOn(
    String platformKey,
    List<Map<String, dynamic>> plugins,
  ) => helper.importedPlugins(
    platformKey: platformKey,
    plugins: plugins,
    sources: helper.appSources(
      projectRoot: "${sandbox.path}/app",
      platformKey: platformKey,
    ),
  );

  test('Swift and Objective-C imports of a plugin module are found', () {
    writeSource(
      "ios/Runner/AppDelegate.swift",
      "import Flutter\nimport google_mobile_ads\n",
    );
    writeSource(
      "ios/Runner/Ads/NativeAd.m",
      "#import <firebase_messaging/FLTFirebaseMessagingPlugin.h>\n",
    );

    expect(
      importedOn("ios", [
        plugin("google_mobile_ads"),
        plugin("firebase_messaging"),
        plugin("google_mobile_ads_extra"),
        plugin("url_launcher_ios"),
      ]),
      {"google_mobile_ads", "firebase_messaging"},
    );
  });

  test('the generated plugin registrant does not count as a use', () {
    writeSource(
      "ios/Runner/GeneratedPluginRegistrant.m",
      "@import url_launcher_ios;\n",
    );
    writeSource(
      "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
      "import io.flutter.plugins.urllauncher.UrlLauncherPlugin;\n",
    );

    expect(importedOn("ios", [plugin("url_launcher_ios")]), isEmpty);
    expect(
      importedOn("android", [
        plugin(
          "url_launcher_android",
          androidPackage: "io.flutter.plugins.urllauncher",
        ),
      ]),
      isEmpty,
    );
  });

  test('an Android plugin is found by the package its pubspec declares', () {
    writeSource(
      "android/app/src/main/kotlin/com/app/MainActivity.kt",
      "import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin\n",
    );

    expect(
      importedOn("android", [
        plugin(
          "google_mobile_ads",
          androidPackage: "io.flutter.plugins.googlemobileads",
        ),
        plugin(
          "url_launcher_android",
          androidPackage: "io.flutter.plugins.urllauncher",
        ),
        plugin("no_package"),
      ]),
      {"google_mobile_ads"},
    );
  });

  test('an app without native sources imports nothing', () {
    expect(importedOn("ios", [plugin("url_launcher_ios")]), isEmpty);
  });
}
