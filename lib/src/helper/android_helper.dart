import 'package:uploader/src/config/android/android_account_config.dart';
import 'package:uploader/src/helper/file_helper.dart';
import 'package:uploader/src/util/printer.dart';

class AndroidHelper {
  final _fileHelper = FileHelper();

  Future<AndroidAccountConfig?> getAccountConfig(String path) async {
    final androidAccountConfigFile = await _fileHelper.readFile(
      path,
    );

    if (androidAccountConfigFile == null) {
      Printer.error(
        "android account file could not be read, please check the file location",
      );
      return null;
    }

    final accountConfig = AndroidAccountConfig.fromJson(
      androidAccountConfigFile,
    );

    if (!accountConfig.checkParameters) {
      Printer.error(
        "android account file could not be read, "
        "please check the file content "
        "[${accountConfig.showError}']",
      );
      return null;
    }
    return accountConfig;
  }

  Future<String?> getPackageName() async {
    try {
      const gradlePath = "android/app/build.gradle";
      final lineList = await _fileHelper.readFileLines(gradlePath);

      if (lineList != null) {
        bool defaultConfigFound = false;

        for (var line in lineList) {
          line = line.trim();

          if (line.contains('defaultConfig {')) {
            defaultConfigFound = true;
            continue;
          }

          if (defaultConfigFound) {
            if (line.contains('applicationId')) {
              return line.split('"')[1];
            }
            if (line.contains('}')) {
              break;
            }
          }
        }
      }

      throw Exception("applicationId not found in build.gradle");
    } catch (e) {
      Printer.error("error occurred while reading package name: $e");
      return null;
    }
  }
}
