import "dart:convert";
import "dart:io";

import "package:uploader/src/config/uploader_config.dart";
import "package:uploader/src/helper/parse_helper.dart";
import "package:uploader/src/model/app_detail.dart";
import "package:uploader/src/service/android_upload_service.dart";
import "package:uploader/src/service/ios_upload_service.dart";
import "package:uploader/src/service/process_service.dart";
import 'package:uploader/src/util/printer.dart';

class UploaderManager {
  final UploaderConfig config;

  final processService = ProcessService();
  final parseHelper = ParseHelper();

  UploaderManager({required this.config});

  Future<bool> startUpload() async {
    final appDetail = await parseHelper.getAppDetails();
    if (appDetail == null) {
      Printer.error("app detail not found");
      return false;
    } else {
      showProjectDetails(appDetail);

      Printer.warning("Do you approve this information?(y/n): ");

      String? yOrN = stdin.readLineSync(encoding: utf8);
      if (yOrN != "y" && yOrN != "Y") return false;

      final futures = await Future.wait([
        if (config.platform.availableOnAndroid)
          AndroidUploadService(config).upload(
            config.appDistributionConfig?.accountConfig.androidId,
          ),
        if (config.platform.availableOnIos)
          IosUploadService(config).upload(
            config.appDistributionConfig?.accountConfig.iosId,
          ),
      ]);

      if (futures.contains(false)) {
        return false;
      }

      return true;
    }
  }

  void showProjectDetails(AppDetail appDetail) {
    final platform = config.platform;
    final uploadType = config.uploadType;

    StringBuffer info = StringBuffer(
      "Project Name: ${appDetail.appName}\n"
      "Build Name: ${appDetail.buildVersion}\n"
      "Build Number: ${appDetail.buildNumber}\n"
      "Platform: ${platform.value}\n"
      "Upload Type: ${uploadType.value}\n",
    );

    if (uploadType.availableOnAppDistribution) {
      final distributionConfig = config.appDistributionConfig!;

      if (platform.availableOnAndroid) {
        info.write(
          "Android Firebase App Id: ${distributionConfig.accountConfig.androidId}\n",
        );
        info.write(
          "Android Testers: "
          "[${distributionConfig.formattedAndroidTesters}]\n",
        );
      }
      if (platform.availableOnIos) {
        info.write(
          "Ios Firebase App Id: ${distributionConfig.accountConfig.iosId}\n",
        );
        info.write(
          "App Distribution Android Build Type : "
          "[${distributionConfig.androidBuildType.value}]\n",
        );
        info.write(
          "IOS Testers: "
          "[${distributionConfig.formattedIosTesters}]\n",
        );
      }
      info.write(
        "Release Notes: "
        "\n${distributionConfig.formattedReleaseNotes}\n",
      );
    }

    Printer.info("$info");
  }
}
