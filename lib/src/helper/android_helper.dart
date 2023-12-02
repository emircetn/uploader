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
}
