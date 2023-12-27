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
  iosOnly(value: "iosOnly"),
  androidOnly(value: "androidOnly"),
  all(value: "all");

  final String value;

  const AppPlatform({required this.value});

  bool get availableOnAndroid => this != iosOnly;
  bool get availableOnIos => this != androidOnly;
}

enum UploadType {
  appDistribution(value: "appDistribution"),
  store(value: "store"),
  all(value: "all");

  final String value;

  const UploadType({required this.value});

  bool get availableOnAppDistribution => this != store;
}

enum Track {
  internal(value: "internal"),
  alpha(value: "alpha"),
  beta(value: "beta");

  final String value;

  const Track({required this.value});
}
