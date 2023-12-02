import 'package:uploader/src/enum/enums.dart';

class AppDistributionAccountConfig {
  final String? iosId;
  final String? androidId;

  bool checkParameters(AppPlatform platform) =>
      (!platform.availableOnAndroid || androidId != null) &&
      (!platform.availableOnIos || iosId != null);

  AppDistributionAccountConfig({
    this.iosId,
    this.androidId,
  });
}
