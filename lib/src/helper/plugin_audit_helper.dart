import 'dart:io';

import 'package:uploader/src/helper/code_size_helper.dart';
import 'package:uploader/src/helper/plugin_stub_helper.dart';
import 'package:uploader/src/util/string_utils.dart';
import 'package:yaml/yaml.dart';

enum PluginReach {
  live(label: "live"),
  unused(label: "unused: no Dart code reaches it"),
  usedByApp(label: "the app's native code imports it"),
  nativeOnly(label: "native only, check by hand"),
  usedByKeptPlugin(label: "a plugin that stays depends on it"),
  extendsKeptPlugin(label: "depends on a plugin that stays, which may load it"),
  startupSideEffects(label: "runs at startup, never stubbed"),
  kept(label: "kept by pluginStubs.keep");

  final String label;

  const PluginReach({required this.label});
}

class PluginAuditEntry {
  final String name;
  final PluginReach reach;
  final int bytes;

  /// A few of the functions the snapshot kept, to show why it is live.
  final List<String> functions;

  const PluginAuditEntry({
    required this.name,
    required this.reach,
    required this.bytes,
    this.functions = const [],
  });
}

/// Decides, per registered plugin, whether any Dart code can still call it.
///
/// A plugin whose Dart API the AOT compiler dropped can never be called from
/// Dart, so its native side only costs size. The verdict is only that strong
/// for plugins that are reached from Dart at all, which is why only plugins
/// found [PluginReach.unused] may be stubbed: packages without a Dart entry
/// point have their native code loaded by another package, the app's native
/// code may call a plugin directly, SDKs may do their work at startup, every
/// plugin that stays may link the native code of those it depends on, and a
/// plugin depending on one that is used or kept may be loaded by it natively.
class PluginAuditHelper {
  static const _startupSideEffectPlugins = [
    "firebase_",
    "facebook_app_events",
    "appsflyer_sdk",
    "adapty_flutter",
    "newrelic_mobile",
  ];

  static final _dartEntryPoint = RegExp(
    r"MethodChannel|EventChannel|BasicMessageChannel|BinaryMessenger|"
    r"dart:ffi|DynamicLibrary|registerWith|_platform_interface/|"
    r"PlatformInterface|package:flutter/services\.dart",
  );

  /// [plugins] are the `plugins.<platform>` entries of
  /// `.flutter-plugins-dependencies` and [dependencyGraph] its
  /// `dependencyGraph`. [usedByApp] are the plugins the app's native code
  /// imports and [kept] those the config keeps.
  List<PluginAuditEntry> audit({
    required List<Map<dynamic, dynamic>> plugins,
    required List<Map<dynamic, dynamic>> dependencyGraph,
    required Map<String, PackageCode> code,
    Set<String> usedByApp = const {},
    Set<String> kept = const {},
  }) {
    final reaches = {
      for (final plugin in plugins)
        "${plugin["name"]}": _reachOf(
          plugin,
          code: code,
          usedByApp: usedByApp,
          kept: kept,
        ),
    };

    _protectAroundStayingPlugins(
      reaches,
      dependencies: _dependenciesByPlugin(dependencyGraph),
    );

    final entries = [
      for (final MapEntry(key: name, value: reach) in reaches.entries)
        _entryFor(name, reach: reach, code: code),
    ];
    return entries..sort(_byReachThenSize);
  }

  static const _possibleLoaders = {
    PluginReach.live,
    PluginReach.usedByApp,
    PluginReach.startupSideEffects,
    PluginReach.kept,
    PluginReach.extendsKeptPlugin,
  };

  /// Turns the unused plugins of [reaches] a staying plugin needs into
  /// staying ones, until nothing changes: what a staying plugin depends on,
  /// since it may link that native code, and what depends on a plugin that is
  /// used or kept for itself, since that plugin's native SDK may load it by
  /// class name the way Google Mobile Ads loads its mediation adapters.
  ///
  /// Shared native libraries such as `flutter_plugin_android_lifecycle` and
  /// plugins kept only for a dependent load nothing, so they protect nothing
  /// that depends on them.
  void _protectAroundStayingPlugins(
    Map<String, PluginReach> reaches, {
    required Map<String, List<String>> dependencies,
  }) {
    bool stays(String name) =>
        reaches[name] != null && reaches[name] != PluginReach.unused;
    bool mayLoad(String name) => _possibleLoaders.contains(reaches[name]);

    var changed = true;
    while (changed) {
      changed = false;
      final neededByStaying = {
        for (final name in reaches.keys.where(stays))
          ..._transitiveDependencies(name, dependencies),
      };
      for (final MapEntry(key: name, value: reach)
          in reaches.entries.toList()) {
        if (reach != PluginReach.unused &&
            reach != PluginReach.usedByKeptPlugin) {
          continue;
        }

        final protection = (dependencies[name] ?? const []).any(mayLoad)
            ? PluginReach.extendsKeptPlugin
            : neededByStaying.contains(name)
            ? PluginReach.usedByKeptPlugin
            : reach;
        if (protection == reach) continue;

        reaches[name] = protection;
        changed = true;
      }
    }
  }

  /// The unused plugins of [platformKey], leaving out the federated
  /// implementations that stubbing their app-facing plugin drops anyway.
  ///
  /// A stub only drops the `default_package` of the platforms it strips, and
  /// keeps one another built platform still uses, so an implementation is
  /// left out only when every plugin depending on it is unused and names it
  /// as its `default_package` on [platformKey] alone. Any other dependency
  /// stays in the graph and stays registered unless it is stubbed itself.
  List<String> suggestedStubs({
    required String platformKey,
    required List<PluginAuditEntry> entries,
    required List<Map<dynamic, dynamic>> plugins,
    required List<Map<dynamic, dynamic>> dependencyGraph,
  }) {
    final dependencies = _dependenciesByPlugin(dependencyGraph);
    final unused = entries
        .where((entry) => entry.reach == PluginReach.unused)
        .map((entry) => entry.name)
        .toSet();
    final paths = {
      for (final plugin in plugins) "${plugin["name"]}": plugin["path"],
    };
    final defaultPackages = {
      for (final name in unused)
        name: {
          for (final key in builtPlatformKeys)
            key: _defaultPackageOf(paths[name], platformKey: key),
        },
    };

    bool dropsOnlyHere(String dependent, String implementation) {
      final defaults = defaultPackages[dependent];
      if (defaults == null || defaults[platformKey] != implementation) {
        return false;
      }
      return defaults.entries.every(
        (entry) => entry.key == platformKey || entry.value != implementation,
      );
    }

    bool droppedWithItsPlugin(String name) {
      final dependents = [
        for (final MapEntry(key: dependent, value: names)
            in dependencies.entries)
          if (names.contains(name)) dependent,
      ];
      return dependents.isNotEmpty &&
          dependents.every((dependent) => dropsOnlyHere(dependent, name));
    }

    return unused.where((name) => !droppedWithItsPlugin(name)).toList()..sort();
  }

  /// [stubsAutomatically] tells the report the suggestions are being stubbed
  /// rather than only suggested.
  String formatReport({
    required String platformKey,
    required List<PluginAuditEntry> entries,
    required List<String> suggestedStubs,
    bool stubsAutomatically = false,
  }) {
    final report = StringBuffer(
      "[audit] ${entries.length} plugins registered on $platformKey\n",
    );
    for (final entry in entries) {
      final size = entry.bytes == 0 ? "" : StringUtils.formatBytes(entry.bytes);
      report.writeln(
        "  ${entry.name.padRight(40)} ${size.padLeft(9)}  ${entry.reach.label}",
      );
    }
    report.write(
      suggestedStubs.isEmpty
          ? "[audit] nothing to stub on $platformKey"
          : "[audit] ${stubsAutomatically ? "stubbing" : "can be stubbed"} "
                "on $platformKey: ${suggestedStubs.join(", ")}",
    );
    return "$report";
  }

  PluginReach _reachOf(
    Map<dynamic, dynamic> plugin, {
    required Map<String, PackageCode> code,
    required Set<String> usedByApp,
    required Set<String> kept,
  }) {
    final name = "${plugin["name"]}";
    final path = plugin["path"];

    if (_startupSideEffectPlugins.any(name.startsWith)) {
      return PluginReach.startupSideEffects;
    }
    if (code[name]?.isReachable ?? false) return PluginReach.live;
    if (kept.contains(name)) return PluginReach.kept;
    if (usedByApp.contains(name)) return PluginReach.usedByApp;
    if (path is! String || !_hasDartEntryPoint(path)) {
      return PluginReach.nativeOnly;
    }
    return PluginReach.unused;
  }

  PluginAuditEntry _entryFor(
    String name, {
    required PluginReach reach,
    required Map<String, PackageCode> code,
  }) {
    final packageCode = code[name];
    return PluginAuditEntry(
      name: name,
      reach: reach,
      bytes: packageCode?.bytes ?? 0,
      functions: packageCode?.functions.take(5).toList() ?? const [],
    );
  }

  bool _hasDartEntryPoint(String packageRoot) {
    final lib = Directory("$packageRoot/lib");
    if (!lib.existsSync()) return false;

    return lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith(".dart"))
        .any((file) => _dartEntryPoint.hasMatch(file.readAsStringSync()));
  }

  String? _defaultPackageOf(
    dynamic packageRoot, {
    required String platformKey,
  }) {
    if (packageRoot is! String) return null;
    final pubspec = File("$packageRoot/pubspec.yaml");
    if (!pubspec.existsSync()) return null;

    dynamic value = loadYaml(pubspec.readAsStringSync());
    for (final key in ["flutter", "plugin", "platforms", platformKey]) {
      if (value is! Map) return null;
      value = value[key];
    }
    final defaultPackage = value is Map ? value["default_package"] : null;
    return defaultPackage is String ? defaultPackage : null;
  }

  Map<String, List<String>> _dependenciesByPlugin(
    List<Map<dynamic, dynamic>> dependencyGraph,
  ) => {
    for (final node in dependencyGraph)
      "${node["name"]}": [
        for (final dependency in (node["dependencies"] as List?) ?? const [])
          "$dependency",
      ],
  };

  Set<String> _transitiveDependencies(
    String name,
    Map<String, List<String>> dependencies,
  ) {
    final found = <String>{};
    final pending = [...?dependencies[name]];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (found.add(next)) pending.addAll(dependencies[next] ?? const []);
    }
    return found;
  }

  int _byReachThenSize(PluginAuditEntry a, PluginAuditEntry b) {
    final byReach = a.reach.index.compareTo(b.reach.index);
    return byReach != 0 ? byReach : b.bytes.compareTo(a.bytes);
  }
}
