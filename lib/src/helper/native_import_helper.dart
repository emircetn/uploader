import 'dart:io';

import 'package:yaml/yaml.dart';

/// Finds the plugins the app's own native code uses, which no code size
/// analysis can see: a plugin the Dart code never calls may still be called
/// from `AppDelegate` or `MainActivity`.
class NativeImportHelper {
  static const _sourceFoldersByPlatform = {
    "ios": ["ios/Runner"],
    "android": ["android/app/src"],
  };

  static const _sourceExtensionsByPlatform = {
    "ios": [".swift", ".m", ".mm", ".h"],
    "android": [".kt", ".java"],
  };

  /// Flutter writes it into the app and it imports every plugin.
  static const _generatedRegistrant = "GeneratedPluginRegistrant";

  /// The native sources of the app itself on [platformKey], without the
  /// generated plugin registrant.
  List<String> appSources({
    required String projectRoot,
    required String platformKey,
  }) {
    final extensions = _sourceExtensionsByPlatform[platformKey] ?? const [];
    return [
      for (final folder in _sourceFoldersByPlatform[platformKey] ?? const [])
        ..._sourcesIn(
          Directory("$projectRoot/$folder"),
          extensions: extensions,
        ),
    ];
  }

  /// The names of [plugins], the `plugins.<platform>` entries of
  /// `.flutter-plugins-dependencies`, that [sources] import. An iOS plugin is
  /// imported by its module, which is the plugin name; an Android one by the
  /// package its pubspec declares.
  Set<String> importedPlugins({
    required String platformKey,
    required List<Map<dynamic, dynamic>> plugins,
    required List<String> sources,
  }) {
    if (sources.isEmpty) return const {};

    final imported = <String>{};
    for (final plugin in plugins) {
      final name = "${plugin["name"]}";
      final pattern = switch (platformKey) {
        "ios" => _iosImport(name),
        "android" => _androidImport(plugin["path"]),
        _ => null,
      };
      if (pattern != null && sources.any(pattern.hasMatch)) imported.add(name);
    }
    return imported;
  }

  RegExp _iosImport(String module) {
    final name = RegExp.escape(module);
    return RegExp(
      '^\\s*(?:@?import\\s+$name\\b|#(?:import|include)\\s+[<"]$name/)',
      multiLine: true,
    );
  }

  RegExp? _androidImport(dynamic packageRoot) {
    if (packageRoot is! String) return null;
    final package = _androidPackageOf(packageRoot);
    if (package == null) return null;
    return RegExp("\\b${RegExp.escape(package)}\\.");
  }

  String? _androidPackageOf(String packageRoot) {
    final pubspec = File("$packageRoot/pubspec.yaml");
    if (!pubspec.existsSync()) return null;

    dynamic value = loadYaml(pubspec.readAsStringSync());
    for (final key in [
      "flutter",
      "plugin",
      "platforms",
      "android",
      "package",
    ]) {
      if (value is! Map) return null;
      value = value[key];
    }
    return value is String ? value : null;
  }

  List<String> _sourcesIn(
    Directory folder, {
    required List<String> extensions,
  }) {
    if (!folder.existsSync()) return const [];

    return folder
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => extensions.any(file.path.endsWith))
        .where(
          (file) =>
              !file.uri.pathSegments.last.startsWith(_generatedRegistrant),
        )
        .map((file) => file.readAsStringSync())
        .toList();
  }
}
