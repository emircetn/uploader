import 'dart:io';

import 'package:uploader/helper/file_helper.dart';
import 'package:uploader/model/app_detail.dart';

class ParseHelper {
  final fileHelper = FileHelper();

  Future<AppDetail?> getAppDetails() async {
    try {
      var yamlFile = File("pubspec.yaml");
      var yamlContent = yamlFile.readAsStringSync();
      var lines = yamlContent.split("\n");

      String? projectName;
      String? buildVersion;
      String? buildNumber;

      for (var line in lines) {
        if (projectName != null &&
            buildVersion != null &&
            buildNumber != null) {
          break;
        }
        if (line.contains("name:")) {
          projectName = line.split(":")[1].trim();
        }

        if (line.contains("version:")) {
          final buildNumberAndNumber = line.split(":")[1].trim();
          buildVersion = buildNumberAndNumber.split("+")[0];
          buildNumber = buildNumberAndNumber.split("+")[1];
        }
      }

      return AppDetail(
        appName: projectName!,
        buildVersion: buildVersion!,
        buildNumber: buildNumber!,
      );
    } catch (e) {
      return null;
    }
  }
}
