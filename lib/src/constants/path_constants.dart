import 'dart:io';

class PathConstants {
  const PathConstants._();

  static String get _basePath => Directory.current.path;

  static const String abbRelativePath =
      "build/app/outputs/bundle/release/app-release.aab";
  static const String apkRelativePath =
      "build/app/outputs/flutter-apk/app-release.apk";
  static String ipaRelativePath(String name) => "build/ios/ipa/$name.ipa";

  static const String uploaderBuildRelativePath = "build/uploader";
  static const String pluginStubsRelativePath =
      "$uploaderBuildRelativePath/plugin_stubs";
  static const String pluginStubBackupRelativePath =
      "$uploaderBuildRelativePath/plugin_stub_backup";
  static String codeSizeRelativePath(String platformKey) =>
      "$uploaderBuildRelativePath/code_size/$platformKey";
  static const String pubspecOverridesRelativePath = "pubspec_overrides.yaml";
  static const String packageConfigRelativePath =
      ".dart_tool/package_config.json";
  static const String flutterPluginsDependenciesRelativePath =
      ".flutter-plugins-dependencies";

  /// Files a stubbed resolve or build rewrites and a run puts back.
  static const List<String> pluginStubRestoredFiles = [
    "pubspec.lock",
    "ios/Podfile.lock",
    "ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    "ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    pubspecOverridesRelativePath,
  ];

  static String get abbPath => "$_basePath/$abbRelativePath";
  static String get apkPath => "$_basePath/$apkRelativePath";
  static String ipaPath(String name) => "$_basePath/${ipaRelativePath(name)}";
}
