import 'package:collection/collection.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/data_source.dart';

class PubspecParameters {
  //general
  final UploadType? uploadType;
  final AppPlatform? platform;

  //ios
  final String? testFlightConfigPath;

  //android
  final String? playStoreConfigPath;
  final String? androidPackageName;
  final AndroidTrack androidTrack;
  final String? androidSkslPath;

  //appDistribution
  final AndroidBuildType appDistributionAndroidBuildType;
  final DataSource? appDistributionAndroidTesters;
  final DataSource? appDistributionIosTesters;
  final String? appDistributionReleaseNotesPath;

  //other
  final List<String>? extraBuildParameters;
  final bool useParallelUpload;
  final bool enableLogFileCreation;

  bool get checkIosStoreParameters => checkString(testFlightConfigPath);

  bool get checkAndroidStoreParameters =>
      checkString(playStoreConfigPath) && checkString(androidPackageName);

  PubspecParameters({
    required this.uploadType,
    required this.platform,
    required this.testFlightConfigPath,
    required this.playStoreConfigPath,
    this.androidTrack = AndroidTrack.internal,
    required this.androidPackageName,
    required this.androidSkslPath,
    this.appDistributionAndroidBuildType = AndroidBuildType.abb,
    required this.appDistributionAndroidTesters,
    required this.appDistributionIosTesters,
    required this.appDistributionReleaseNotesPath,
    required this.extraBuildParameters,
    required this.useParallelUpload,
    required this.enableLogFileCreation,
  });

  factory PubspecParameters.fromPubspec(Map<dynamic, dynamic> map) {
    final uploaderMap = map['uploader'];
    final playStoreConfigMap = uploaderMap["playStoreConfig"];
    final testFlightConfigMap = uploaderMap["testFlightConfig"];

    final appDistributionConfig = uploaderMap["appDistributionConfig"];
    final androidTestersMap = appDistributionConfig?['androidTesters'];
    final iosTestersMap = appDistributionConfig?['iosTesters'];

    return PubspecParameters(
      uploadType: uploaderMap == null
          ? null
          : UploadType.values.firstWhereOrNull(
              (uploadType) => uploadType.value == uploaderMap["uploadType"]),
      platform: uploaderMap == null
          ? null
          : AppPlatform.values.firstWhereOrNull(
              (platform) => platform.value == uploaderMap["platform"]),
      testFlightConfigPath:
          testFlightConfigMap == null ? null : testFlightConfigMap["path"],
      playStoreConfigPath:
          playStoreConfigMap == null ? null : playStoreConfigMap["path"],
      androidPackageName:
          playStoreConfigMap == null ? null : playStoreConfigMap["packageName"],
      androidTrack: playStoreConfigMap == null
          ? AndroidTrack.internal
          : AndroidTrack.values.firstWhereOrNull(
                  (track) => track.value == playStoreConfigMap["track"]) ??
              AndroidTrack.internal,
      androidSkslPath:
          playStoreConfigMap == null ? null : playStoreConfigMap["skslPath"],
      appDistributionAndroidBuildType: appDistributionConfig == null
          ? AndroidBuildType.abb
          : AndroidBuildType.values.firstWhereOrNull((buildType) =>
                  buildType.value ==
                  appDistributionConfig["androidBuildType"]) ??
              AndroidBuildType.abb,
      appDistributionIosTesters: iosTestersMap == null
          ? null
          : DataSource(
              url: iosTestersMap?['url'],
              path: iosTestersMap?['path'],
            ),
      appDistributionAndroidTesters: androidTestersMap == null
          ? null
          : DataSource(
              url: androidTestersMap?['url'],
              path: androidTestersMap?['path'],
            ),
      appDistributionReleaseNotesPath: appDistributionConfig == null
          ? null
          : appDistributionConfig['releaseNotesPath'],
      extraBuildParameters:
          _parseIterableToList<String>(uploaderMap['extraBuildParameters']),
      useParallelUpload:
          uploaderMap == null ? true : uploaderMap['useParallelUpload'] ?? true,
      enableLogFileCreation: uploaderMap == null
          ? false
          : uploaderMap['enableLogFileCreation'] ?? false,
    );
  }

  static List<T>? _parseIterableToList<T>(Iterable<dynamic>? elements) {
    return elements == null ? null : List<T>.from(elements);
  }

  bool checkString(String? value) {
    return value != null && value.isNotEmpty;
  }
}
