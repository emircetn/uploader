import 'package:collection/collection.dart';
import 'package:uploader/src/constants/pubspec_keys.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/data_source.dart';
import 'package:uploader/src/model/plugin_stub_config.dart';
import 'package:uploader/src/model/symbols_config.dart';

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

  /// Environment variables every build process receives, such as a
  /// `FLUTTER_XCODE_` build setting.
  final Map<String, String>? extraBuildEnvironment;

  /// Applied on top of [extraBuildEnvironment] for that target's builds only.
  final Map<String, String>? appDistributionExtraBuildEnvironment;
  final Map<String, String>? storeExtraBuildEnvironment;

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

  /// Symbol archiving and upload after each build. Null when `symbols` is
  /// not configured, which leaves runs exactly as they were.
  final SymbolsConfig? symbols;

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
    this.extraBuildEnvironment,
    this.appDistributionExtraBuildEnvironment,
    this.storeExtraBuildEnvironment,
    required this.useParallelUpload,
    required this.enableLogFileCreation,
    this.uploadRetryCount = 2,
    this.pluginStubs = const PluginStubConfig(),
    this.allowedPluginsPath,
    this.verifyPluginStubs = true,
    this.symbols,
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
      extraBuildEnvironment: _parseEnvironment(
        uploaderMap?[PubspecKeys.extraBuildEnvironment],
      ),
      appDistributionExtraBuildEnvironment: _parseEnvironment(
        uploaderMap?[PubspecKeys.appDistributionExtraBuildEnvironment],
      ),
      storeExtraBuildEnvironment: _parseEnvironment(
        uploaderMap?[PubspecKeys.storeExtraBuildEnvironment],
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
      symbols: _parseSymbols(uploaderMap?[PubspecKeys.symbols]),
    );
  }

  static SymbolsConfig? _parseSymbols(dynamic value) {
    if (value == null || value == false) return null;
    if (value == true) return const SymbolsConfig();
    if (value is! Map) {
      throw const FormatException(
        "uploader.symbols must be true or a map, such as {crashlytics: true}",
      );
    }

    _checkKeys(value, "symbols", const {
      PubspecKeys.archivePath,
      PubspecKeys.keepLast,
      PubspecKeys.failOnUploadError,
      PubspecKeys.crashlytics,
      PubspecKeys.newRelic,
      PubspecKeys.commands,
    });

    final keepLast = value[PubspecKeys.keepLast];
    if (keepLast != null && keepLast is! int) {
      throw FormatException(
        "uploader.symbols.keepLast must be a whole number, not $keepLast",
      );
    }

    return SymbolsConfig(
      archivePath:
          _parseString(value[PubspecKeys.archivePath], "symbols.archivePath") ??
          SymbolsConfig.defaultArchivePath,
      keepLast: keepLast ?? SymbolsConfig.defaultKeepLast,
      failOnUploadError: value[PubspecKeys.failOnUploadError] == true,
      crashlytics: value[PubspecKeys.crashlytics] == true,
      newRelic: _parseNewRelic(value[PubspecKeys.newRelic]),
      commands: _parseSymbolCommands(value[PubspecKeys.commands]),
    );
  }

  static NewRelicSymbolsConfig? _parseNewRelic(dynamic value) {
    if (value == null || value == false) return null;
    if (value is! Map) {
      throw const FormatException(
        "uploader.symbols.newRelic must say where each platform's token is "
        "read from, such as:\n"
        "  newRelic:\n"
        "    androidToken: {env: NEW_RELIC_ANDROID_KEY}\n"
        "    iosToken: {file: .env, key: NEW_RELIC_IOS_KEY}",
      );
    }

    _checkKeys(value, "symbols.newRelic", const {
      PubspecKeys.region,
      PubspecKeys.androidToken,
      PubspecKeys.iosToken,
    });

    final regionValue = value[PubspecKeys.region];
    final region = regionValue == null
        ? NewRelicRegion.us
        : NewRelicRegion.values.firstWhereOrNull(
            (region) => region.value == regionValue,
          );
    if (region == null) {
      throw FormatException(
        "uploader.symbols.newRelic.region must be one of "
        "${NewRelicRegion.values.map((region) => region.value).join(", ")}, "
        "not $regionValue",
      );
    }

    final androidToken = _parseTokenSource(
      value[PubspecKeys.androidToken],
      "symbols.newRelic.androidToken",
    );
    final iosToken = _parseTokenSource(
      value[PubspecKeys.iosToken],
      "symbols.newRelic.iosToken",
    );
    if (androidToken == null && iosToken == null) {
      throw const FormatException(
        "uploader.symbols.newRelic needs androidToken, iosToken or both",
      );
    }

    return NewRelicSymbolsConfig(
      region: region,
      androidToken: androidToken,
      iosToken: iosToken,
    );
  }

  static TokenSource? _parseTokenSource(dynamic value, String key) {
    if (value == null) return null;
    if (value is! Map) {
      throw FormatException(
        "uploader.$key must be {env: NAME} or {file: path, key: NAME}",
      );
    }

    _checkKeys(value, key, const {
      PubspecKeys.env,
      PubspecKeys.file,
      PubspecKeys.key,
    });

    final env = _parseString(value[PubspecKeys.env], "$key.env");
    final file = _parseString(value[PubspecKeys.file], "$key.file");
    final fileKey = _parseString(value[PubspecKeys.key], "$key.key");

    if (env != null && file == null && fileKey == null) {
      return TokenSource.env(env);
    }
    if (env == null && file != null && fileKey != null) {
      return TokenSource.file(file: file, key: fileKey);
    }
    throw FormatException(
      "uploader.$key must be either {env: NAME} or {file: path, key: NAME}",
    );
  }

  static List<SymbolCommand> _parseSymbolCommands(dynamic value) {
    if (value == null) return const [];
    if (value is! Iterable) {
      throw const FormatException(
        "uploader.symbols.commands must be a list of {name, run, platform}",
      );
    }

    final commands = <SymbolCommand>[];
    for (final (index, command) in value.indexed) {
      final key = "symbols.commands[$index]";
      if (command is! Map) {
        throw FormatException("uploader.$key must be a map with name and run");
      }
      _checkKeys(command, key, const {
        PubspecKeys.name,
        PubspecKeys.run,
        PubspecKeys.platform,
      });

      final run = _parseString(command[PubspecKeys.run], "$key.run");
      if (run == null) throw FormatException("uploader.$key.run is required");

      commands.add(
        SymbolCommand(
          name:
              _parseString(command[PubspecKeys.name], "$key.name") ??
              "command ${index + 1}",
          run: run,
          platform: _parseCommandPlatform(command[PubspecKeys.platform], index),
        ),
      );
    }
    return commands;
  }

  static AppPlatform _parseCommandPlatform(dynamic value, int index) {
    if (value == null) return AppPlatform.all;
    return AppPlatform.values.firstWhereOrNull(
          (platform) => platform.value == value,
        ) ??
        (throw FormatException(
          "uploader.symbols.commands[$index].platform must be one of "
          "${AppPlatform.values.map((platform) => platform.value).join(", ")}, "
          "not $value",
        ));
  }

  /// Rejects keys [map] should not have, so a typo such as `crashlytic:`
  /// stops the run instead of quietly turning a feature off.
  static void _checkKeys(Map map, String key, Set<String> allowed) {
    final unknown = map.keys
        .map((k) => "$k")
        .where((k) => !allowed.contains(k));
    if (unknown.isNotEmpty) {
      throw FormatException(
        "uploader.$key has unknown key(s) ${unknown.join(", ")}; "
        "allowed: ${allowed.join(", ")}",
      );
    }
  }

  static String? _parseString(dynamic value, String key) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException("uploader.$key must be a non-empty string");
    }
    return value.trim();
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

  /// YAML reads `YES` and `1` as a bool and an int; a process environment
  /// takes strings, so every value is written back as text.
  static Map<String, String>? _parseEnvironment(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    return {
      for (final MapEntry(:key, :value) in map.entries)
        '$key': value is bool ? (value ? 'YES' : 'NO') : '$value',
    };
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
