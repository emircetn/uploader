enum IPAType { adHoc, appStore }

enum AndroidBuildType {
  abb(value: "abb"),
  apk(value: "apk");

  final String value;

  const AndroidBuildType({required this.value});

  bool get isApk => this == apk;
  bool get isAbb => this == abb;
}

enum AppPlatform {
  ios(value: "ios"),
  android(value: "android"),
  all(value: "all");

  final String value;

  const AppPlatform({required this.value});

  bool get availableOnAndroid => this != ios;
  bool get availableOnIos => this != android;
}

enum UploadType {
  appDistributionOnly(value: "appDistributionOnly"),
  storeOnly(value: "storeOnly"),
  all(value: "all");

  final String value;

  const UploadType({required this.value});

  bool get availableOnAppDistribution => this != storeOnly;
}

enum Track {
  internal(value: "internal"),
  alpha(value: "alpha"),
  beta(value: "beta");

  final String value;

  const Track({required this.value});
}
