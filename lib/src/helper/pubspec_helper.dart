import 'dart:io';

import 'package:uploader/src/model/pubspec_parameters.dart';
import 'package:uploader/src/util/printer.dart';
import 'package:yaml/yaml.dart';

class PubspecHelper {
  final _pubspecPath = "./pubspec.yaml";

  Map<dynamic, dynamic>? _loadPubspecFile() {
    final String pubspecString = File(_pubspecPath).readAsStringSync();
    final Map? pubspecMap = loadYaml(pubspecString);
    return pubspecMap;
  }

  PubspecParameters? getPubspecParameters() {
    try {
      final pubspecMap = _loadPubspecFile();
      if (pubspecMap == null || pubspecMap['uploader'] == null) return null;

      return PubspecParameters.fromPubspec(pubspecMap);
    } catch (e) {
      Printer.error("$e");
      return null;
    }
  }
}
