import 'package:uploader/src/config/android/android_account_config.dart';
import 'package:uploader/src/config/android/android_config.dart';
import 'package:uploader/src/config/app_distribution/app_distribution_config.dart';
import 'package:uploader/src/config/ios/ios_account_config.dart';
import 'package:uploader/src/config/ios/ios_config.dart';
import 'package:uploader/src/config/uploader_config.dart';
import 'package:uploader/src/constants/pubspec_keys.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/android_helper.dart';
import 'package:uploader/src/helper/app_distribution_helper.dart';
import 'package:uploader/src/helper/file_helper.dart';
import 'package:uploader/src/helper/ios_helper.dart';
import 'package:uploader/src/model/pubspec_parameters.dart';
import 'package:uploader/src/util/printer.dart';

class UploadHelper {
  final _fileHelper = FileHelper();
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

    if (platform.availableOnIos &&
        uploadType.availableOnStore &&
        !pubspecParameters.checkIosStoreParameters) {
      return Printer.error(
        "ios config is missing or incorrect\n"
        "check ${PubspecKeys.testFlightConfig} -> ${PubspecKeys.path} parameter",
      );
    }
    if (platform.availableOnAndroid &&
        uploadType.availableOnStore &&
        !pubspecParameters.checkAndroidStoreParameters) {
      return Printer.error(
        "android config is missing or incorrect\n"
        "check ${PubspecKeys.playStoreConfig} -> ${PubspecKeys.path} parameter",
      );
    }

    return true;
  }

  Future<UploaderConfig?> createUploaderConfig(
    PubspecParameters pubspecParameters,
  ) async {
    final platform = pubspecParameters.platform!;
    final uploadType = pubspecParameters.uploadType!;

    AndroidConfig? playStoreConfig;
    IosConfig? iosConfig;
    AppDistributionConfig? appDistributionConfig;

    if (platform.availableOnAndroid) {
      final androidHelper = AndroidHelper();

      AndroidAccountConfig? androidAccountConfig;

      if (uploadType.availableOnStore) {
        final playStoreConfigPath = pubspecParameters.playStoreConfigPath!;
        androidAccountConfig = await androidHelper.getAccountConfig(
          playStoreConfigPath,
        );

        if (androidAccountConfig == null) {
          Printer.error(
            "process cannot continue because android account config information could not be obtained",
          );
          return null;
        }
      }

      final packageName = await androidHelper.getPackageName();

      if (packageName == null) {
        Printer.error("process cannot continue because package name not found");
        return null;
      }

      playStoreConfig = AndroidConfig(
        packageName: packageName,
        track: pubspecParameters.androidTrack,
        skslPath: pubspecParameters.androidSkslPath,
        accountConfig: androidAccountConfig,
      );
    }

    if (platform.availableOnIos) {
      final iosHelper = IosHelper();
      final testFlightConfigPath = pubspecParameters.testFlightConfigPath!;
      String? ipaName = await iosHelper.getIpaName();

      if (ipaName == null) {
        Printer.error("process cannot continue because ipa name not found");
        return null;
      }

      IosAccountConfig? iosAccountConfig;

      if (uploadType.availableOnStore) {
        iosAccountConfig = await iosHelper.getAccountConfig(
          testFlightConfigPath,
        );

        if (iosAccountConfig == null) {
          Printer.error(
            "process cannot continue because ios account config information could not be obtained",
          );
          return null;
        }
      }
      iosConfig = IosConfig(
        ipaName: ipaName,
        accountConfig: iosAccountConfig,
      );
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

      List<String>? releaseNotes;
      if (pubspecParameters.appDistributionReleaseNotesPath != null) {
        releaseNotes = await _fileHelper.readFileLines(
          pubspecParameters.appDistributionReleaseNotesPath!,
        );

        if (releaseNotes == null) {
          Printer.error(
            "process cannot continue because release notes could not be obtained",
          );
          return null;
        }
      }
      List<String>? iosTesters;
      if (platform.availableOnIos &&
          pubspecParameters.appDistributionIosTesters != null) {
        iosTesters = await appDistributionHelper
            .getTesters(pubspecParameters.appDistributionIosTesters!);
        if (iosTesters == null) {
          Printer.error(
            "process cannot continue because ios testers could not be obtained",
          );
          return null;
        }
      }

      List<String>? androidTesters;
      if (platform.availableOnAndroid &&
          pubspecParameters.appDistributionAndroidTesters != null) {
        androidTesters = await appDistributionHelper
            .getTesters(pubspecParameters.appDistributionAndroidTesters!);
        if (androidTesters == null) {
          Printer.error(
            "process cannot continue because android testers could not be obtained",
          );
          return null;
        }
      }

      appDistributionConfig = AppDistributionConfig(
        accountConfig: appDistributionAccountConfig,
        androidBuildType: pubspecParameters.appDistributionAndroidBuildType,
        androidTesters: androidTesters,
        iosTesters: iosTesters,
        releaseNotes: releaseNotes,
      );
    }
    return UploaderConfig(
      uploadType: uploadType,
      platform: platform,
      playStoreConfig: playStoreConfig,
      iosConfig: iosConfig,
      appDistributionConfig: appDistributionConfig,
      extraBuildParameters: pubspecParameters.extraBuildParameters,
      useParallelUpload: pubspecParameters.useParallelUpload,
      enableLogFileCreation: pubspecParameters.enableLogFileCreation,
    );
  }
}
