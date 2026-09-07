import 'package:uploader/src/config/android/android_config.dart';
import 'package:uploader/src/config/app_distribution/app_distribution_config.dart';
import 'package:uploader/src/config/ios/ios_config.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/cli_options.dart';

class UploaderConfig {
  final UploadType uploadType;
  final AppPlatform platform;
  final IosConfig? iosConfig;
  final AndroidConfig? playStoreConfig;
  final AppDistributionConfig? appDistributionConfig;

  /// Parameters every build receives.
  final List<String>? extraBuildParameters;

  /// Parameters only that target's builds receive, on top of
  /// [extraBuildParameters].
  final List<String>? appDistributionExtraBuildParameters;
  final List<String>? storeExtraBuildParameters;

  final bool useParallelUpload;
  final bool enableLogFileCreation;

  final int uploadRetryCount;

  final CliOptions cliOptions;

  UploaderConfig({
    required this.uploadType,
    required this.platform,
    this.iosConfig,
    this.playStoreConfig,
    this.appDistributionConfig,
    this.extraBuildParameters,
    this.appDistributionExtraBuildParameters,
    this.storeExtraBuildParameters,
    required this.useParallelUpload,
    required this.enableLogFileCreation,
    this.uploadRetryCount = 2,
    this.cliOptions = const CliOptions(),
  });

  bool get isDryRun => cliOptions.dryRun;

  /// The full parameter list a build for [target] is run with. Merging lives
  /// here so no caller has to remember the order.
  List<String> buildParametersFor(BuildTarget target) => [
    ...?extraBuildParameters,
    ...?switch (target) {
      BuildTarget.appDistribution => appDistributionExtraBuildParameters,
      BuildTarget.store => storeExtraBuildParameters,
    },
  ];
}
