import 'dart:io';

import 'package:uploader/src/model/app_detail.dart';
import 'package:yaml/yaml.dart';

class ParseHelper {
  final String pubspecPath;

  ParseHelper({this.pubspecPath = "pubspec.yaml"});

  Future<AppDetail?> getAppDetails() async {
    try {
      final content = await File(pubspecPath).readAsString();
      final pubspec = loadYaml(content);

      if (pubspec is! Map) return null;

      final name = pubspec['name'];
      final version = pubspec['version'];

      if (name is! String || name.isEmpty) return null;
      if (version == null) return null;

      final versionAndBuildNumber = "$version".split("+");

      return AppDetail(
        appName: name,
        buildVersion: versionAndBuildNumber.first,
        buildNumber: versionAndBuildNumber.length > 1
            ? versionAndBuildNumber[1]
            : null,
      );
    } catch (e) {
      return null;
    }
  }
}
