import 'package:uploader/src/config/ios/ios_account_config.dart';
import 'package:uploader/src/helper/file_helper.dart';
import 'package:uploader/src/util/printer.dart';

class IosHelper {
  final _fileHelper = FileHelper();
  Future<IosAccountConfig?> getAccountConfig(String path) async {
    final iosAccountConfigFile = await _fileHelper.readFile(path);

    if (iosAccountConfigFile == null) {
      Printer.error(
        "ios account file could not be read, please check the file location",
      );
      return null;
    }

    final accountConfig = IosAccountConfig.fromJson(
      iosAccountConfigFile,
    );

    if (!accountConfig.checkParameters) {
      Printer.error(
        "ios account file could not be read, "
        "please check the file content "
        "[${accountConfig.showError}']",
      );
      return null;
    }
    return accountConfig;
  }

  Future<String?> getIpaName() async {
    try {
      const plistPath = "ios/Runner/Info.plist";
      const cFBundleNameKey = "CFBundleName";
      const initTag = "<string>";
      const lastTag = "</string>";

      final lineList = await _fileHelper.readFileLines(plistPath);

      final index =
          lineList.indexWhere((element) => element.contains(cFBundleNameKey));

      final line = lineList[index + 1];

      final ipaName =
          line.substring(initTag.length + 1, line.length - lastTag.length);

      return ipaName;
    } catch (e) {
      return null;
    }
  }
}
