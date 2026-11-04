import 'dart:convert';
import 'dart:io';

import 'package:uploader/src/model/symbols_config.dart';
import 'package:uploader/src/util/path_utils.dart';

/// Reads a token from the one place `pubspec.yaml` names for it. Nothing is
/// searched for: a token that is not where the configuration says is
/// reported as missing.
class SecretHelper {
  final String projectRoot;
  final Map<String, String> environment;

  SecretHelper({required this.projectRoot, required this.environment});

  String? resolve(TokenSource source) {
    final env = source.env;
    if (env != null) {
      final value = environment[env]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final String path;
    try {
      path = PathUtils.resolve(
        source.file!,
        projectRoot: projectRoot,
        environment: environment,
      );
    } on StateError {
      return null;
    }
    return readKeyFromFile(path, source.key!);
  }

  /// The value of [key] in a JSON object or a `KEY=value` file, or null when
  /// the file or the key is missing.
  static String? readKeyFromFile(String path, String key) {
    final file = File(path);
    if (!file.existsSync()) return null;

    final String content;
    try {
      content = file.readAsStringSync();
    } on FileSystemException {
      return null;
    }

    final value = parseKeyValues(content)[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Reads a JSON object, or failing that `KEY=value` lines as `.env` and
  /// `.properties` files write them.
  static Map<String, String> parseKeyValues(String content) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith("{")) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return {
            for (final MapEntry(:key, :value) in decoded.entries)
              if (value != null) "$key": "$value",
          };
        }
      } on FormatException {
        // Not JSON after all; read it as lines below.
      }
    }

    final values = <String, String>{};
    for (var line in const LineSplitter().convert(content)) {
      line = line.trim();
      if (line.isEmpty || line.startsWith("#") || line.startsWith("!")) {
        continue;
      }
      if (line.startsWith("export ")) line = line.substring(7).trimLeft();

      final separator = line.indexOf("=");
      if (separator <= 0) continue;

      final key = line.substring(0, separator).trim();
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      values[key] = value;
    }
    return values;
  }
}
