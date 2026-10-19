import 'package:yaml/yaml.dart';

/// Compares the plugins a build registers with the list the project allows,
/// so a dependency update cannot add native code without anyone noticing.
class PluginAllowlistHelper {
  static const _header =
      "# Every plugin each platform may register. uploader stops a run that "
      "registers\n"
      "# one that is not listed here; add it to this file once the new native "
      "code is\n"
      "# wanted.\n";

  /// The plugin names `.flutter-plugins-dependencies` registers on each of
  /// [platformKeys].
  Map<String, List<String>> registeredPlugins({
    required Map<dynamic, dynamic>? pluginsDependencies,
    required List<String> platformKeys,
  }) {
    final plugins = pluginsDependencies?["plugins"];
    return {
      for (final key in platformKeys)
        key: [
          if (plugins is Map && plugins[key] is List)
            for (final plugin in (plugins[key] as List).whereType<Map>())
              "${plugin["name"]}",
        ]..sort(),
    };
  }

  /// Registered plugins [allowed] does not list, per platform. A platform
  /// [allowed] has no list for is left out; see [unrecordedPlatforms].
  Map<String, List<String>> unexpected({
    required Map<String, List<String>> allowed,
    required Map<String, List<String>> registered,
  }) => _difference(registered, allowed);

  /// Allowed plugins no longer registered, which the list can drop.
  Map<String, List<String>> unregistered({
    required Map<String, List<String>> allowed,
    required Map<String, List<String>> registered,
  }) => _difference(allowed, registered);

  List<String> unrecordedPlatforms({
    required Map<String, List<String>> allowed,
    required Map<String, List<String>> registered,
  }) => registered.keys.where((key) => !allowed.containsKey(key)).toList();

  Map<String, List<String>> decode(String content) {
    final yaml = loadYaml(content);
    if (yaml is! Map) return {};

    return {
      for (final entry in yaml.entries)
        if (entry.value is List)
          "${entry.key}": [for (final name in entry.value) "$name"],
    };
  }

  String encode(Map<String, List<String>> allowed) {
    final content = StringBuffer(_header);
    for (final key in allowed.keys.toList()..sort()) {
      content.writeln("$key:");
      for (final name in allowed[key]!.toList()..sort()) {
        content.writeln("  - $name");
      }
    }
    return "$content";
  }

  Map<String, List<String>> _difference(
    Map<String, List<String>> from,
    Map<String, List<String>> minus,
  ) {
    final difference = <String, List<String>>{};
    for (final key in from.keys) {
      final other = minus[key];
      if (other == null) continue;
      final names = from[key]!.where((name) => !other.contains(name)).toList();
      if (names.isNotEmpty) difference[key] = names;
    }
    return difference;
  }
}
