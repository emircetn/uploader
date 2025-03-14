import 'package:uploader/src/config/android/android_account_config.dart';
import 'package:uploader/src/enum/enums.dart';

final class PlayStoreConfig {
  final String packageName;
  final AndroidTrack track;
  final String? skslPath;
  final AndroidAccountConfig? accountConfig;

  PlayStoreConfig({
    required this.packageName,
    this.track = AndroidTrack.internal,
    required this.skslPath,
    this.accountConfig,
  });
}
