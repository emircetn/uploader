import 'package:uploader/src/config/android/android_config.dart';
import 'package:uploader/src/config/app_distribution/app_distribution_config.dart';
import 'package:uploader/src/config/ios/ios_config.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/cli_options.dart';
import 'package:uploader/src/model/plugin_stub_config.dart';

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

  /// Environment variables every build process receives.
  final Map<String, String>? extraBuildEnvironment;

  /// Environment variables only that target's builds receive, on top of
  /// [extraBuildEnvironment].
  final Map<String, String>? appDistributionExtraBuildEnvironment;
  final Map<String, String>? storeExtraBuildEnvironment;

  final bool useParallelUpload;
  final bool enableLogFileCreation;

  final int uploadRetryCount;

  final PluginStubConfig pluginStubs;
  final String? allowedPluginsPath;
  final bool verifyPluginStubs;

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
    this.extraBuildEnvironment,
    this.appDistributionExtraBuildEnvironment,
    this.storeExtraBuildEnvironment,
    required this.useParallelUpload,
    required this.enableLogFileCreation,
    this.uploadRetryCount = 2,
    this.pluginStubs = const PluginStubConfig(),
    this.allowedPluginsPath,
    this.verifyPluginStubs = true,
    this.cliOptions = const CliOptions(),
  });

  bool get isDryRun => cliOptions.dryRun;

  bool get isAudit => cliOptions.audit;

  /// The targets a run builds, each with its own [buildParametersFor].
  List<BuildTarget> get builtTargets => [
    if (uploadType.availableOnAppDistribution) BuildTarget.appDistribution,
    if (uploadType.availableOnStore) BuildTarget.store,
  ];

  /// The full parameter list a build for [target] is run with. Merging lives
  /// here so no caller has to remember the order.
  List<String> buildParametersFor(BuildTarget target) => [
    ...?extraBuildParameters,
    ...?switch (target) {
      BuildTarget.appDistribution => appDistributionExtraBuildParameters,
      BuildTarget.store => storeExtraBuildParameters,
    },
  ];

  /// The environment a build for [target] runs with, on top of the shell's.
  /// A target's own value wins over [extraBuildEnvironment].
  Map<String, String> buildEnvironmentFor(BuildTarget target) => {
    ...?extraBuildEnvironment,
    ...?switch (target) {
      BuildTarget.appDistribution => appDistributionExtraBuildEnvironment,
      BuildTarget.store => storeExtraBuildEnvironment,
    },
  };
}
