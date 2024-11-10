import 'package:collection/collection.dart';
import 'package:uploader/src/enum/enums.dart';

class PubspecParameters {
  //general
  final UploadType? uploadType;
  final AppPlatform? platform;

  //ios
  final String? iosConfigPath;

  //android
  final String? androidConfigPath;
  final String? androidPackageName;
  final AndroidTrack androidTrack;
  final String? androidSkslPath;

  //appDistribution
  final AndroidBuildType appDistributionAndroidBuildType;
  final String? appDistributionAndroidTestersPath;
  final String? appDistributionIosTestersPath;
  final String? appDistributionReleaseNotesPath;

  //other
  final List<String>? extraBuildParameters;
  final bool useParallelUpload;

  bool get checkIosParameters => checkString(iosConfigPath);

  bool get checkAndroidParameters =>
      checkString(androidConfigPath) && checkString(androidPackageName);

  PubspecParameters({
    required this.uploadType,
    required this.platform,
    required this.iosConfigPath,
    required this.androidConfigPath,
    this.androidTrack = AndroidTrack.internal,
    required this.androidPackageName,
    required this.androidSkslPath,
    this.appDistributionAndroidBuildType = AndroidBuildType.abb,
    required this.appDistributionAndroidTestersPath,
    required this.appDistributionIosTestersPath,
    required this.appDistributionReleaseNotesPath,
    required this.extraBuildParameters,
    required this.useParallelUpload,
  });

  factory PubspecParameters.fromPubspec(Map<dynamic, dynamic> map) {
    final uploaderMap = map['uploader'];
    final androidConfigMap = uploaderMap["androidConfig"];
    final iosConfigMap = uploaderMap["iosConfig"];
    final appDistributionConfig = uploaderMap["appDistributionConfig"];

    return PubspecParameters(
      uploadType: uploaderMap == null
          ? null
          : UploadType.values.firstWhereOrNull(
              (uploadType) => uploadType.value == uploaderMap["uploadType"]),
      platform: uploaderMap == null
          ? null
          : AppPlatform.values.firstWhereOrNull(
              (platform) => platform.value == uploaderMap["platform"]),
      iosConfigPath: iosConfigMap == null ? null : iosConfigMap["path"],
      androidConfigPath:
          androidConfigMap == null ? null : androidConfigMap["path"],
      androidPackageName:
          androidConfigMap == null ? null : androidConfigMap["packageName"],
      androidTrack: androidConfigMap == null
          ? AndroidTrack.internal
          : AndroidTrack.values.firstWhereOrNull(
                  (track) => track.value == androidConfigMap["track"]) ??
              AndroidTrack.internal,
      androidSkslPath:
          androidConfigMap == null ? null : androidConfigMap["skslPath"],
      appDistributionAndroidBuildType: appDistributionConfig == null
          ? AndroidBuildType.abb
          : AndroidBuildType.values.firstWhereOrNull((buildType) =>
                  buildType.value ==
                  appDistributionConfig["androidBuildType"]) ??
              AndroidBuildType.abb,
      appDistributionIosTestersPath: appDistributionConfig == null
          ? null
          : appDistributionConfig['iosTestersPath'],
      appDistributionAndroidTestersPath: appDistributionConfig == null
          ? null
          : appDistributionConfig['androidTestersPath'],
      appDistributionReleaseNotesPath: appDistributionConfig == null
          ? null
          : appDistributionConfig['releaseNotesPath'],
      extraBuildParameters:
          _parseIterableToList<String>(uploaderMap['extraBuildParameters']),
      useParallelUpload:
          uploaderMap == null ? true : uploaderMap['useParallelUpload'] ?? true,
    );
  }

  static List<T>? _parseIterableToList<T>(Iterable<dynamic>? elements) {
    return elements == null ? null : List<T>.from(elements);
  }

  bool checkString(String? value) {
    return value != null && value.isNotEmpty;
  }
}
