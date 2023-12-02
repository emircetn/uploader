import 'dart:io';

class PathConstants {
  const PathConstants._();

  static String get _basePath => Directory.current.path;

  static const String abbRelativePath =
      "build/app/outputs/bundle/release/app-release.aab";
  static const String apkRelativePath =
      "build/app/outputs/flutter-apk/app-release.apk";
  static String ipaRelativePath(String name) => "build/ios/ipa/$name.ipa";

  static String get abbPath => "$_basePath/$abbRelativePath";
  static String get apkPath => "$_basePath/$abbRelativePath";
  static String ipaPath(String name) => "$_basePath/${ipaRelativePath(name)}";
}
