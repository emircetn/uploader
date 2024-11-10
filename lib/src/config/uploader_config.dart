import 'package:uploader/src/config/android/android_config.dart';
import 'package:uploader/src/config/app_distribution/app_distribution_config.dart';
import 'package:uploader/src/config/ios/ios_config.dart';
import 'package:uploader/src/enum/enums.dart';

class UploaderConfig {
  final UploadType uploadType;
  final AppPlatform platform;
  final IosConfig? iosConfig;
  final AndroidConfig? androidConfig;
  final AppDistributionConfig? appDistributionConfig;
  final List<String>? extraBuildParameters;
  final bool useParallelUpload;
  final bool enableLogFileCreation;

  UploaderConfig({
    required this.uploadType,
    required this.platform,
    this.iosConfig,
    this.androidConfig,
    this.appDistributionConfig,
    this.extraBuildParameters,
    required this.useParallelUpload,
    required this.enableLogFileCreation,
  });
}
