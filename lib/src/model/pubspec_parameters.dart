import 'package:collection/collection.dart';
import 'package:uploader/src/constants/pubspec_keys.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/data_source.dart';
import 'package:uploader/src/model/plugin_stub_config.dart';

class PubspecParameters {
  //general
  final UploadType? uploadType;
  final AppPlatform? platform;

  //ios
  final String? testFlightConfigPath;

  //android
  final String? playStoreConfigPath;
  final AndroidTrack androidTrack;
  final String? androidSkslPath;
  final ReleaseStatus androidReleaseStatus;

  //appDistribution
  final AndroidBuildType appDistributionAndroidBuildType;
  final DataSource? appDistributionAndroidTesters;
  final DataSource? appDistributionIosTesters;
  final List<String>? appDistributionAndroidGroups;
  final List<String>? appDistributionIosGroups;
  final String? appDistributionReleaseNotesPath;

  //other
  final List<String>? extraBuildParameters;

  /// Applied on top of [extraBuildParameters] for that target's builds only.
  final List<String>? appDistributionExtraBuildParameters;
  final List<String>? storeExtraBuildParameters;

  final bool useParallelUpload;
  final bool enableLogFileCreation;
  final int uploadRetryCount;

  final PluginStubConfig pluginStubs;

  /// A file listing every plugin each platform may register. Unset means the
  /// registered plugins are not checked.
  final String? allowedPluginsPath;

  /// Whether a run proves, from a code size analysis build, that no Dart code
  /// can still reach a stubbed plugin before it builds anything it uploads.
  final bool verifyPluginStubs;

  bool get checkIosStoreParameters => checkString(testFlightConfigPath);

  bool get checkAndroidStoreParameters => checkString(playStoreConfigPath);

  PubspecParameters({
    required this.uploadType,
    required this.platform,
    required this.testFlightConfigPath,
    required this.playStoreConfigPath,
    this.androidTrack = AndroidTrack.internal,
    required this.androidSkslPath,
    this.androidReleaseStatus = ReleaseStatus.completed,
    this.appDistributionAndroidBuildType = AndroidBuildType.abb,
    required this.appDistributionAndroidTesters,
    required this.appDistributionIosTesters,
    this.appDistributionAndroidGroups,
    this.appDistributionIosGroups,
    required this.appDistributionReleaseNotesPath,
    required this.extraBuildParameters,
    this.appDistributionExtraBuildParameters,
    this.storeExtraBuildParameters,
    required this.useParallelUpload,
    required this.enableLogFileCreation,
    this.uploadRetryCount = 2,
    this.pluginStubs = const PluginStubConfig(),
    this.allowedPluginsPath,
    this.verifyPluginStubs = true,
  });

  factory PubspecParameters.fromPubspec(Map<dynamic, dynamic> map) {
    final uploaderMap = map[PubspecKeys.uploader];
    final playStoreConfigMap = uploaderMap?[PubspecKeys.playStoreConfig];
    final testFlightConfigMap = uploaderMap?[PubspecKeys.testFlightConfig];

    final appDistributionConfig =
        uploaderMap?[PubspecKeys.appDistributionConfig];
    final androidTestersMap =
        appDistributionConfig?[PubspecKeys.androidTesters];
    final iosTestersMap = appDistributionConfig?[PubspecKeys.iosTesters];

    return PubspecParameters(
      uploadType: uploaderMap == null
          ? null
          : UploadType.values.firstWhereOrNull(
              (uploadType) =>
                  uploadType.value == uploaderMap[PubspecKeys.uploadType],
            ),
      platform: uploaderMap == null
          ? null
          : AppPlatform.values.firstWhereOrNull(
              (platform) => platform.value == uploaderMap[PubspecKeys.platform],
            ),
      testFlightConfigPath: testFlightConfigMap?[PubspecKeys.path],
      playStoreConfigPath: playStoreConfigMap?[PubspecKeys.path],
      androidTrack:
          AndroidTrack.values.firstWhereOrNull(
            (track) => track.value == playStoreConfigMap?[PubspecKeys.track],
          ) ??
          AndroidTrack.internal,
      androidSkslPath: playStoreConfigMap?[PubspecKeys.skslPath],
      androidReleaseStatus:
          ReleaseStatus.values.firstWhereOrNull(
            (status) =>
                status.value == playStoreConfigMap?[PubspecKeys.releaseStatus],
          ) ??
          ReleaseStatus.completed,
      appDistributionAndroidBuildType:
          AndroidBuildType.values.firstWhereOrNull(
            (buildType) =>
                buildType.value ==
                appDistributionConfig?[PubspecKeys.androidBuildType],
          ) ??
          AndroidBuildType.abb,
      appDistributionIosTesters: iosTestersMap == null
          ? null
          : DataSource(
              url: iosTestersMap[PubspecKeys.url],
              path: iosTestersMap[PubspecKeys.path],
            ),
      appDistributionAndroidTesters: androidTestersMap == null
          ? null
          : DataSource(
              url: androidTestersMap[PubspecKeys.url],
              path: androidTestersMap[PubspecKeys.path],
            ),
      appDistributionAndroidGroups: _parseIterableToList<String>(
        appDistributionConfig?[PubspecKeys.androidGroups],
      ),
      appDistributionIosGroups: _parseIterableToList<String>(
        appDistributionConfig?[PubspecKeys.iosGroups],
      ),
      appDistributionReleaseNotesPath:
          appDistributionConfig?[PubspecKeys.releaseNotesPath],
      extraBuildParameters: _parseIterableToList<String>(
        uploaderMap?[PubspecKeys.extraBuildParameters],
      ),
      appDistributionExtraBuildParameters: _parseIterableToList<String>(
        uploaderMap?[PubspecKeys.appDistributionExtraBuildParameters],
      ),
      storeExtraBuildParameters: _parseIterableToList<String>(
        uploaderMap?[PubspecKeys.storeExtraBuildParameters],
      ),
      useParallelUpload: uploaderMap?[PubspecKeys.useParallelUpload] ?? true,
      enableLogFileCreation:
          uploaderMap?[PubspecKeys.enableLogFileCreation] ?? false,
      uploadRetryCount: _parseRetryCount(
        uploaderMap?[PubspecKeys.uploadRetryCount],
      ),
      pluginStubs: _parsePluginStubs(
        uploaderMap?[PubspecKeys.pluginStubs],
        prunedAssets: uploaderMap?[PubspecKeys.prunedAssets],
        prunedFonts: uploaderMap?[PubspecKeys.prunedFonts],
      ),
      allowedPluginsPath: uploaderMap?[PubspecKeys.allowedPluginsPath],
      verifyPluginStubs: uploaderMap?[PubspecKeys.verifyPluginStubs] ?? true,
    );
  }

  static PluginStubConfig _parsePluginStubs(
    Map<dynamic, dynamic>? map, {
    Map<dynamic, dynamic>? prunedAssets,
    Map<dynamic, dynamic>? prunedFonts,
  }) {
    return PluginStubConfig(
      all: _parseIterableToList<String>(map?[PubspecKeys.all]) ?? const [],
      ios: _parseIterableToList<String>(map?[PubspecKeys.ios]) ?? const [],
      android:
          _parseIterableToList<String>(map?[PubspecKeys.android]) ?? const [],
      prunedAssets: _parseListsByPackage(
        prunedAssets,
        key: PubspecKeys.prunedAssets,
      ),
      prunedFonts: _parseListsByPackage(
        prunedFonts,
        key: PubspecKeys.prunedFonts,
      ),
      auto: map?[PubspecKeys.auto] ?? false,
      keep: _parseIterableToList<String>(map?[PubspecKeys.keep]) ?? const [],
    );
  }

  static Map<String, List<String>> _parseListsByPackage(
    Map<dynamic, dynamic>? map, {
    required String key,
  }) => {
    for (final MapEntry(key: package, :value) in (map ?? const {}).entries)
      "$package": switch (value) {
        Iterable() => _parseIterableToList<String>(value)!,
        _ => throw FormatException(
          "uploader.$key.$package must be a list, such as [$value]",
        ),
      },
  };

  static List<T>? _parseIterableToList<T>(Iterable<dynamic>? elements) {
    return elements == null ? null : List<T>.from(elements);
  }

  /// A negative count would mean "never run at all", so it is clamped away.
  static int _parseRetryCount(dynamic value) {
    final count = value is num ? value.toInt() : null;
    if (count == null || count < 0) return 2;
    return count;
  }

  bool checkString(String? value) {
    return value != null && value.isNotEmpty;
  }
}
