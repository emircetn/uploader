import 'package:uploader/config/android/android_config.dart';
import 'package:uploader/config/app_distribution/app_distribution_config.dart';
import 'package:uploader/config/ios/ios_config.dart';
import 'package:uploader/model/pubspec_parameters.dart';
import 'package:uploader/config/uploader_config.dart';
import 'package:uploader/enum/enums.dart';
import 'package:uploader/helper/android_helper.dart';
import 'package:uploader/helper/app_distribution_helper.dart';
import 'package:uploader/helper/ios_helper.dart';
import 'package:uploader/util/printer.dart';

class UploadHelper {
  bool checkPubspecParameters(PubspecParameters pubspecParameters) {
    final platform = pubspecParameters.platform;
    final uploadType = pubspecParameters.uploadType;

    if (platform == null) {
      return Printer.error(
        "platform cannot be empty.\n"
        "supported values are: ${AppPlatform.values.map((platform) => platform.value)}",
      );
    }

    if (uploadType == null) {
      return Printer.error(
        "upload type cannot be empty.\n"
        "supported values are: ${UploadType.values.map((uploadType) => uploadType.value)}",
      );
    }

    if (platform.availableOnIos && !pubspecParameters.checkIosParameters) {
      return Printer.error("ios config is missing or incorrect");
    }
    if (platform.availableOnAndroid &&
        !pubspecParameters.checkAndroidParameters) {
      return Printer.error("android config is missing or incorrect");
    }

    return true;
  }

  Future<UploaderConfig?> createUploaderConfig(
    PubspecParameters pubspecParameters,
  ) async {
    final platform = pubspecParameters.platform!;
    final uploadType = pubspecParameters.uploadType!;

    AndroidConfig? androidConfig;
    IosConfig? iosConfig;
    AppDistributionConfig? appDistributionConfig;

    if (platform.availableOnAndroid) {
      final androidHelper = AndroidHelper();

      final androidConfigPath = pubspecParameters.androidConfigPath!;

      final androidAccountConfig = await androidHelper.getAccountConfig(
        androidConfigPath,
      );

      if (androidAccountConfig == null) {
        Printer.error(
          "process cannot continue because android account config information could not be obtained",
        );
        return null;
      }

      androidConfig = AndroidConfig(
        packageName: pubspecParameters.androidPackageName!,
        track: pubspecParameters.androidTrack,
        skslPath: pubspecParameters.androidSkslPath,
        accountConfig: androidAccountConfig,
      );
    }

    if (platform.availableOnIos) {
      final iosHelper = IosHelper();
      final iosConfigPath = pubspecParameters.iosConfigPath!;
      String? ipaName = await iosHelper.getIpaName();

      if (ipaName == null) {
        Printer.error("process cannot continue because ipa name not found");
        return null;
      }

      final iosAccountConfig = await iosHelper.getAccountConfig(
        iosConfigPath,
      );

      if (iosAccountConfig == null) {
        Printer.error(
          "process cannot continue because ios account config information could not be obtained",
        );
        return null;
      }

      iosConfig = IosConfig(ipaName: ipaName, accountConfig: iosAccountConfig);
    }

    if (uploadType.availableOnAppDistribution) {
      final appDistributionHelper = AppDistributionHelper();

      final appDistributionAccountConfig =
          await appDistributionHelper.getAccountConfig(platform);

      if (appDistributionAccountConfig == null ||
          !appDistributionAccountConfig.checkParameters(platform)) {
        Printer.error(
          "process cannot continue because app distribution config information could not be obtained",
        );
        return null;
      }

      appDistributionConfig = AppDistributionConfig(
        accountConfig: appDistributionAccountConfig,
        androidBuildType: pubspecParameters.appDistributionAndroidBuildType,
        androidTesters: pubspecParameters.appDistributionAndroidTesters,
        iosTesters: pubspecParameters.appDistributionIosTesters,
        releaseNotes: pubspecParameters.appDistributionReleaseNotes,
      );
    }
    return UploaderConfig(
      uploadType: uploadType,
      platform: platform,
      androidConfig: androidConfig,
      iosConfig: iosConfig,
      appDistributionConfig: appDistributionConfig,
    );
  }
}
