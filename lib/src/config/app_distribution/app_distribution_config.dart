import 'package:uploader/src/config/app_distribution/app_distribution_account_config.dart';
import 'package:uploader/src/enum/enums.dart';

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

  String get formattedReleaseNotes =>
      releaseNotes == null ? "-" : releaseNotes!.join('\n');

  String get formattedIosTesters {
    if (iosTesters == null) return "";
    return iosTesters!.join(", ");
  }

  String get formattedAndroidTesters {
    if (androidTesters == null) return "";
    return androidTesters!.join(", ");
  }
}
