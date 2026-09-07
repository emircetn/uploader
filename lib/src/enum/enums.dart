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
  appDistribution(value: "appDistribution"),
  store(value: "store"),
  all(value: "all");

  final String value;

  const UploadType({required this.value});
  bool get availableOnStore => this != appDistribution;
  bool get availableOnAppDistribution => this != store;
}

enum AndroidTrack {
  internal(value: "internal"),
  alpha(value: "alpha"),
  beta(value: "beta");

  final String value;

  const AndroidTrack({required this.value});
}

enum ReleaseStatus {
  draft(value: "draft"),
  completed(value: "completed");

  final String value;

  const ReleaseStatus({required this.value});
}

/// The two things a run can produce a build for.
///
/// [UploadType] is not usable here: its `all` value means "both targets", not
/// a target of its own.
enum BuildTarget { appDistribution, store }
