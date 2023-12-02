import 'package:uploader/config/android/android_account_config.dart';
import 'package:uploader/enum/enums.dart';

final class AndroidConfig {
  final String packageName;
  final Track track;
  final String? skslPath;
  final AndroidAccountConfig accountConfig;

  AndroidConfig({
    required this.packageName,
    this.track = Track.internal,
    required this.skslPath,
    required this.accountConfig,
  });
}
