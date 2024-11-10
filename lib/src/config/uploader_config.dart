import 'package:uploader/src/config/android/android_account_config.dart';
import 'package:uploader/src/config/android/android_config.dart';
import 'package:uploader/src/config/app_distribution/app_distribution_account_config.dart';
import 'package:uploader/src/config/app_distribution/app_distribution_config.dart';
import 'package:uploader/src/config/ios/ios_account_config.dart';
import 'package:uploader/src/config/ios/ios_config.dart';
import 'package:uploader/src/enum/enums.dart';

class UploaderConfig {
  final UploadType uploadType;
  final AppPlatform platform;
  final IosConfig? iosConfig;
  final AndroidConfig? androidConfig;
  final AppDistributionConfig? appDistributionConfig;
  final List<String>? extraBuildParameters;

  UploaderConfig({
    required this.uploadType,
    required this.platform,
    this.iosConfig,
    this.androidConfig,
    this.appDistributionConfig,
    this.extraBuildParameters,
  });

  factory UploaderConfig.test() {
    return UploaderConfig(
      uploadType: UploadType.all,
      platform: AppPlatform.all,
      iosConfig: IosConfig(
        ipaName: "ipaName",
        accountConfig: IosAccountConfig(
          authKey: "authKey",
          issuerId: "issuerId",
        ),
      ),
      androidConfig: AndroidConfig(
        skslPath: "test",
        packageName: "test",
        track: AndroidTrack.internal,
        accountConfig: AndroidAccountConfig(
          clientEmail: "clientEmail",
          clientId: "clientId",
          privateKey: "privateKey",
        ),
      ),
      appDistributionConfig: AppDistributionConfig(
        accountConfig: AppDistributionAccountConfig(
          androidId: "androidId",
          iosId: "iosId",
        ),
        androidTesters: ["test"],
        iosTesters: ["test"],
        releaseNotes: [
          "test",
          "test",
        ],
      ),
    );
  }
}
