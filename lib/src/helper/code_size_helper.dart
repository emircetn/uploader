import 'dart:math';

/// What one package left in a Dart AOT snapshot.
class PackageCode {
  final int bytes;

  /// The functions the snapshot kept, leaving out the plugin registration a
  /// plugin keeps even when nothing calls it.
  final List<String> functions;

  const PackageCode({required this.bytes, required this.functions});

  /// True when some Dart code can still call into the package, so a stub of
  /// it would throw at runtime.
  bool get isReachable => functions.isNotEmpty;
}

/// Reads the summary `flutter build --analyze-size` writes to
/// `~/.flutter-devtools`.
class CodeSizeHelper {
  static final _summaryLine = RegExp(
    r"A summary of your .+ analysis can be found at: (\S+\.json)",
  );

  /// What every plugin keeps without being called: `registerWith`, the
  /// object it allocates there and the platform instance it sets.
  static final _registrationRemnant = RegExp(
    r"^(registerWith|init:_token|set:platform|set:instance|Allocate .+|new [^.]*\.)$",
  );

  static const _codeLeaves = {"<Code>", "<Function>"};

  static const _valueFlags = {
    "--split-debug-info",
    "--target-platform",
    "--code-size-directory",
    "--export-method",
    "--export-options-plist",
    "--bundle-sksl-path",
  };

  static const _switchFlags = {
    "--obfuscate",
    "--analyze-size",
    "--split-per-abi",
    "--no-codesign",
  };

  /// The summary path in a line of `flutter build --analyze-size` output.
  String? summaryPathIn(String line) => _summaryLine.firstMatch(line)?[1];

  /// [parameters] without the flags an analysis build cannot take:
  /// `--split-debug-info` is rejected next to `--analyze-size`,
  /// `--obfuscate` hides the symbol names the analysis reads, and the
  /// artifact flags belong to the release builds.
  List<String> analysisParameters(List<String> parameters) {
    final kept = <String>[];
    for (var i = 0; i < parameters.length; i++) {
      final parameter = parameters[i];
      final flag = parameter.split("=").first;

      if (_switchFlags.contains(flag)) continue;
      if (_valueFlags.contains(flag)) {
        final takesNextToken =
            !parameter.contains("=") &&
            i + 1 < parameters.length &&
            !parameters[i + 1].startsWith("-");
        if (takesNextToken) i++;
        continue;
      }
      kept.add(parameter);
    }
    return kept;
  }

  /// The packages the snapshot in [summary] kept code for, by package name.
  /// Null when [summary] has no Dart AOT snapshot in it.
  Map<String, PackageCode>? packagesIn(Map<dynamic, dynamic> summary) {
    final snapshot = _findSnapshot(summary);
    if (snapshot == null) return null;

    final bytes = <String, int>{};
    final functions = <String, List<String>>{};

    for (final node in _children(snapshot)) {
      final nodeName = node["n"];
      if (nodeName is! String || !nodeName.startsWith("package:")) continue;

      final package = nodeName.substring("package:".length).split("/").first;
      bytes[package] = (bytes[package] ?? 0) + _bytes(node);
      _collectFunctions(node, functions.putIfAbsent(package, () => []));
    }

    return {
      for (final package in bytes.keys)
        package: PackageCode(
          bytes: bytes[package]!,
          functions: functions[package]!,
        ),
    };
  }

  /// What [snapshots] of the same app, built with different parameters, kept
  /// together: a package reached by any of them is reached.
  Map<String, PackageCode> merge(List<Map<String, PackageCode>> snapshots) {
    final bytes = <String, int>{};
    final functions = <String, Set<String>>{};

    for (final snapshot in snapshots) {
      for (final MapEntry(key: package, value: code) in snapshot.entries) {
        bytes[package] = max(bytes[package] ?? 0, code.bytes);
        functions.putIfAbsent(package, () => {}).addAll(code.functions);
      }
    }

    return {
      for (final package in bytes.keys)
        package: PackageCode(
          bytes: bytes[package]!,
          functions: functions[package]!.toList(),
        ),
    };
  }

  Map<dynamic, dynamic>? _findSnapshot(Map<dynamic, dynamic> node) {
    final name = node["n"];
    if (name is String && name.endsWith("(Dart AOT)")) return node;

    for (final child in _children(node)) {
      final snapshot = _findSnapshot(child);
      if (snapshot != null) return snapshot;
    }
    return null;
  }

  void _collectFunctions(Map<dynamic, dynamic> node, List<String> functions) {
    for (final child in _children(node)) {
      final name = child["n"];
      if (name is! String || _registrationRemnant.hasMatch(name)) continue;

      final isFunction = _children(
        child,
      ).any((leaf) => _codeLeaves.contains(leaf["n"]));
      if (isFunction) {
        functions.add(name);
      } else {
        _collectFunctions(child, functions);
      }
    }
  }

  /// Only leaves carry a size; a node weighs what its leaves do.
  int _bytes(Map<dynamic, dynamic> node) {
    final children = _children(node);
    if (children.isEmpty) {
      final value = node["value"];
      return value is int ? value : 0;
    }
    return children.fold(0, (total, child) => total + _bytes(child));
  }

  Iterable<Map<dynamic, dynamic>> _children(Map<dynamic, dynamic> node) {
    final children = node["children"];
    return children is List ? children.whereType<Map>() : const [];
  }
}
