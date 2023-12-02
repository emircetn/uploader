import "dart:convert";
import "dart:io";

import "package:uploader/config/uploader_config.dart";
import "package:uploader/helper/parse_helper.dart";
import "package:uploader/model/app_detail.dart";
import "package:uploader/service/android_upload_service.dart";
import "package:uploader/service/ios_upload_service.dart";
import "package:uploader/service/process_service.dart";
import "package:uploader/util/printer.dart";

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

      Printer.warning("Bu bilgileri onaylıyor musun?(y/n): ");

      String? yOrN = stdin.readLineSync(encoding: utf8);
      if (yOrN != "y" && yOrN != "Y") return false;

      if (config.platform.availableOnAndroid) {
        final isSuccess = await AndroidUploadService(config).upload(
          config.appDistributionConfig?.accountConfig.androidId,
        );
        if (isSuccess) {
          Printer.success("UPLOAD PROCESS COMPLETED FOR ANDROID", bold: true);
        }
      }
      if (config.platform.availableOnIos) {
        final isSuccess = await IosUploadService(config).upload(
          config.appDistributionConfig?.accountConfig.iosId,
        );
        if (isSuccess) {
          Printer.success("UPLOAD PROCESS COMPLETED FOR IOS", bold: true);
        }
      }
    }

    return true;
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
          "Release Notes: "
          "${distributionConfig.showReleaseNotes}",
        );
      }
    }

    Printer.info("$info");
  }
}
