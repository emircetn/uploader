import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// The files of the Flutter project a run builds, by their path relative to
/// [projectRoot].
class ProjectFileHelper {
  final String projectRoot;

  const ProjectFileHelper(this.projectRoot);

  String path(String relativePath) => "$projectRoot/$relativePath";

  File file(String relativePath) => File(path(relativePath));

  /// Null when the file is missing or holds no JSON object.
  Map<dynamic, dynamic>? readJson(String relativePath) {
    final file = this.file(relativePath);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Null when the file is missing or holds no YAML map.
  Map<dynamic, dynamic>? readYaml(String relativePath) {
    final file = this.file(relativePath);
    if (!file.existsSync()) return null;
    final decoded = loadYaml(file.readAsStringSync());
    return decoded is Map ? decoded : null;
  }
}
