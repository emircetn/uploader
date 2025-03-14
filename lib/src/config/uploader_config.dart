import 'package:uploader/src/config/android/play_store_config.dart';
import 'package:uploader/src/config/app_distribution/app_distribution_config.dart';
import 'package:uploader/src/config/ios/test_flight_config.dart';
import 'package:uploader/src/enum/enums.dart';

class UploaderConfig {
  final UploadType uploadType;
  final AppPlatform platform;
  final TestFlightConfig? testFlightConfig;
  final PlayStoreConfig? playStoreConfig;
  final AppDistributionConfig? appDistributionConfig;
  final List<String>? extraBuildParameters;
  final bool useParallelUpload;
  final bool enableLogFileCreation;

  UploaderConfig({
    required this.uploadType,
    required this.platform,
    this.testFlightConfig,
    this.playStoreConfig,
    this.appDistributionConfig,
    this.extraBuildParameters,
    required this.useParallelUpload,
    required this.enableLogFileCreation,
  });
}
