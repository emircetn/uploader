import 'package:uploader/enum/enums.dart';
import 'package:uploader/config/app_distribution/app_distribution_account_config.dart';

final class AppDistributionConfig {
  final AppDistributionAccountConfig accountConfig;
  final AndroidBuildType androidBuildType;
  final List<String>? iosTesters;
  final List<String>? androidTesters;
  final List<String>? releaseNotes;

  AppDistributionConfig({
    required this.accountConfig,
    this.androidBuildType = AndroidBuildType.abb,
    required this.androidTesters,
    required this.iosTesters,
    required this.releaseNotes,
  });

  String? get showReleaseNotes =>
      releaseNotes == null ? null : "\n* ${releaseNotes!.join('\n* ')}";
}
