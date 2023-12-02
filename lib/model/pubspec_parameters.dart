import 'package:collection/collection.dart';
import 'package:uploader/enum/enums.dart';

class PubspecParameters {
  //general
  final UploadType? uploadType;
  final AppPlatform? platform;

  //ios
  final String? iosConfigPath;

  //android
  final String? androidConfigPath;
  final String? androidPackageName;
  final Track androidTrack;
  final String? androidSkslPath;

  //appDistribution
  final AndroidBuildType appDistributionAndroidBuildType;
  final List<String>? appDistributionAndroidTesters;
  final List<String>? appDistributionIosTesters;
  final List<String>? appDistributionReleaseNotes;
  final List<String>? extraBuildParameters;

  bool get checkIosParameters => checkString(iosConfigPath);

  bool get checkAndroidParameters =>
      checkString(androidConfigPath) && checkString(androidPackageName);

  PubspecParameters({
    required this.uploadType,
    required this.platform,
    required this.iosConfigPath,
    required this.androidConfigPath,
    this.androidTrack = Track.internal,
    required this.androidPackageName,
    required this.androidSkslPath,
    this.appDistributionAndroidBuildType = AndroidBuildType.abb,
    required this.appDistributionAndroidTesters,
    required this.appDistributionIosTesters,
    required this.appDistributionReleaseNotes,
    required this.extraBuildParameters,
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
          ? Track.internal
          : Track.values.firstWhereOrNull(
                  (track) => track.value == androidConfigMap["track"]) ??
              Track.internal,
      androidSkslPath:
          androidConfigMap == null ? null : androidConfigMap["skslPath"],
      appDistributionAndroidBuildType: appDistributionConfig == null
          ? AndroidBuildType.abb
          : AndroidBuildType.values.firstWhereOrNull((buildType) =>
                  buildType.value ==
                  appDistributionConfig["androidBuildType"]) ??
              AndroidBuildType.abb,
      appDistributionIosTesters: appDistributionConfig == null
          ? null
          : _parseIterableToList<String>(
              appDistributionConfig['iosTesters'],
            ),
      appDistributionAndroidTesters: appDistributionConfig == null
          ? null
          : _parseIterableToList<String>(
              appDistributionConfig['androidTesters'],
            ),
      appDistributionReleaseNotes: appDistributionConfig == null
          ? null
          : _parseIterableToList<String>(
              appDistributionConfig['releaseNotes'],
            ),
      extraBuildParameters: appDistributionConfig == null
          ? null
          : _parseIterableToList<String>(
              uploaderMap['extraBuildParameters'],
            ),
    );
  }

  static List<T>? _parseIterableToList<T>(Iterable<dynamic>? elements) {
    return elements == null ? null : List<T>.from(elements);
  }

  bool checkString(String? value) {
    return value != null && value.isNotEmpty;
  }
}
