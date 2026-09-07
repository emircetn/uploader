import 'package:uploader/src/config/android/android_account_config.dart';
import 'package:uploader/src/enum/enums.dart';

final class AndroidConfig {
  final String packageName;
  final AndroidTrack track;
  final String? skslPath;
  final AndroidAccountConfig? accountConfig;
  final ReleaseStatus releaseStatus;

  AndroidConfig({
    required this.packageName,
    this.track = AndroidTrack.internal,
    required this.skslPath,
    this.accountConfig,
    this.releaseStatus = ReleaseStatus.completed,
  });
}
