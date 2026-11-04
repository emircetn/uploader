import "dart:convert";
import "dart:io";

import "package:uploader/src/config/uploader_config.dart";
import "package:uploader/src/enum/enums.dart";
import "package:uploader/src/helper/app_distribution_helper.dart";
import "package:uploader/src/helper/firebase_account_helper.dart";
import "package:uploader/src/helper/parse_helper.dart";
import "package:uploader/src/helper/secret_helper.dart";
import "package:uploader/src/model/app_detail.dart";
import "package:uploader/src/model/symbols_config.dart";
import "package:uploader/src/service/android_upload_service.dart";
import "package:uploader/src/service/ios_upload_service.dart";
import "package:uploader/src/service/plugin_guard_service.dart";
import "package:uploader/src/service/plugin_stub_service.dart";
import "package:uploader/src/service/process_service.dart";
import "package:uploader/src/service/symbol/symbol_service.dart";
import 'package:uploader/src/util/printer.dart';
import "package:uploader/src/util/string_utils.dart";

class UploaderManager {
  final UploaderConfig config;

  final processService = ProcessService();
  final parseHelper = ParseHelper();

  late final pluginStubService = PluginStubService(
    config: config.pluginStubs,
    processService: ProcessService(dryRun: config.isDryRun),
    dryRun: config.isDryRun,
  );

  late final pluginGuardService = PluginGuardService(
    config: config,
    processService: ProcessService(dryRun: config.isDryRun),
  );

  UploaderManager({required this.config});

  Future<bool> startUpload() async {
    final appDetail = await parseHelper.getAppDetails();
    if (appDetail == null) {
      Printer.error("app detail not found");
      return false;
    } else {
      if (!await pluginStubService.recoverInterruptedRun()) return false;

      // Made before the details are confirmed, so an archive path that
      // cannot be resolved stops the run before anything is built.
      final SymbolService? symbolService;
      try {
        symbolService = config.isAudit ? null : _createSymbolService(appDetail);
      } on StateError catch (e) {
        return Printer.error("[symbols] ${e.message}");
      }

      showProjectDetails(
        appDetail,
        crashlytics: await _resolveCrashlyticsTarget(),
      );

      if (config.isDryRun) {
        Printer.warning(
          "DRY RUN: no build will run and nothing will be uploaded.",
        );
      }
      if (config.isAudit) {
        Printer.warning(
          "AUDIT: each platform is built once for code size analysis; "
          "nothing will be stubbed or uploaded.",
        );
      }

      if (!config.cliOptions.skipConfirmation) {
        Printer.warning("Do you approve this information?(y/n): ");

        String? yOrN = stdin.readLineSync(encoding: utf8);
        if (yOrN != "y" && yOrN != "Y") {
          Printer.error("cancelled");
          return false;
        }
      }

      if (!pluginStubService.checkProject()) return false;

      pluginStubService.backUp();
      try {
        final analysis = await pluginGuardService.analyse();
        if (analysis == null) return false;
        if (config.isAudit) return true;

        final isStubbed = await pluginStubService.apply(
          autoStubs: analysis.autoStubs,
          isResolved: analysis.isResolved,
        );
        if (!isStubbed) return false;

        final isSafe = await pluginGuardService.check(
          stubs: pluginStubService.appliedPlans,
          analysis: analysis,
        );
        if (!isSafe) return false;

        try {
          final isUploaded = await _runUploads(symbolService);
          // After the distribution uploads, so a slow or failing crash
          // reporter never holds back a release.
          final isSymbolsUploaded =
              await symbolService?.uploadArchived() ?? true;
          return isUploaded && isSymbolsUploaded;
        } finally {
          symbolService?.prune();
        }
      } finally {
        await pluginStubService.restore();
      }
    }
  }

  SymbolService? _createSymbolService(AppDetail appDetail) {
    final symbols = config.symbols;
    if (symbols == null) return null;
    return SymbolService(
      config: symbols,
      appDetail: appDetail,
      retryCount: config.uploadRetryCount,
      dryRun: config.isDryRun,
    );
  }

  Future<bool> _runUploads(SymbolService? symbolService) async {
    final process = [
      if (config.platform.availableOnAndroid)
        () => AndroidUploadService(
          config,
          symbolService: symbolService,
        ).upload(config.appDistributionConfig?.accountConfig.androidId),
      if (config.platform.availableOnIos)
        () => IosUploadService(
          config,
          symbolService: symbolService,
        ).upload(config.appDistributionConfig?.accountConfig.iosId),
    ];
    if (config.useParallelUpload) {
      final futures = await Future.wait(process.map((p) => p()));
      if (futures.contains(false)) {
        return false;
      }
    } else {
      for (final p in process) {
        final isSuccess = await p();
        if (!isSuccess) return false;
      }
    }
    return true;
  }

  /// What Crashlytics uploads will use, resolved the way the uploads resolve
  /// it, so a wrong Firebase project or account shows before the build.
  Future<CrashlyticsTarget?> _resolveCrashlyticsTarget() async {
    if (config.symbols?.crashlytics != true || config.isAudit) return null;

    final account = await AppDistributionHelper().getAccountConfig(
      config.platform,
    );
    return CrashlyticsTarget(
      androidAppId: account?.androidId,
      iosAppId: account?.iosId,
      account: await FirebaseAccountHelper().describe(Platform.environment),
    );
  }

  void showProjectDetails(
    AppDetail appDetail, {
    CrashlyticsTarget? crashlytics,
  }) {
    final platform = config.platform;
    final uploadType = config.uploadType;

    final info = StringBuffer();

    info.writeln(_formatField("Project Name", appDetail.appName));
    info.writeln(_formatField("Build Name", appDetail.buildVersion));
    info.writeln(_formatField("Build Number", appDetail.buildNumber ?? "-"));
    info.writeln(_formatField("Platform", platform.value));
    info.writeln(_formatField("Upload Type", uploadType.value));

    info.writeln();
    info.writeln("---- Build Parameters ----");
    if (uploadType.availableOnAppDistribution) {
      info.writeln(
        _formatField(
          "App Distribution",
          _formatParameters(
            config.buildParametersFor(BuildTarget.appDistribution),
          ),
        ),
      );
    }
    if (uploadType.availableOnStore) {
      info.writeln(
        _formatField(
          "Store",
          _formatParameters(config.buildParametersFor(BuildTarget.store)),
        ),
      );
    }

    final pluginStubs = config.pluginStubs;
    final strippedPlatforms = pluginStubs.strippedPlatforms;
    if (strippedPlatforms.isNotEmpty || pluginStubs.auto) {
      info.writeln();
      info.writeln("---- Plugin Stubs ----");
      for (final entry in strippedPlatforms.entries) {
        info.writeln(_formatField(entry.key, entry.value.value));
      }
      if (pluginStubs.auto) {
        info.writeln(
          _formatField("Auto", "every plugin the analysis finds unused"),
        );
        if (pluginStubs.keep.isNotEmpty) {
          info.writeln(_formatField("Keep", pluginStubs.keep.join(", ")));
        }
      }
      info.writeln(
        _formatField(
          "Verified",
          config.verifyPluginStubs || pluginStubs.auto
              ? "by a code size analysis build"
              : "no (verifyPluginStubs: false)",
        ),
      );
    }

    final prunedAssets = config.pluginStubs.prunedAssets;
    if (prunedAssets.isNotEmpty) {
      info.writeln();
      info.writeln("---- Pruned Assets ----");
      for (final entry in prunedAssets.entries) {
        info.writeln(_formatField(entry.key, entry.value.join(", ")));
      }
    }

    final prunedFonts = config.pluginStubs.prunedFonts;
    if (prunedFonts.isNotEmpty) {
      info.writeln();
      info.writeln("---- Pruned Fonts ----");
      for (final entry in prunedFonts.entries) {
        info.writeln(_formatField(entry.key, entry.value.join(", ")));
      }
    }

    final symbols = config.symbols;
    if (symbols != null && !config.isAudit) {
      info.writeln();
      info.writeln("---- Symbols ----");
      info.writeln(_formatField("Archive", _archivePath(symbols)));
      info.writeln(
        _formatField(
          "Upload To",
          symbols.destinationNames.isEmpty
              ? "(none, archive only)"
              : symbols.destinationNames.join(", "),
        ),
      );
      if (crashlytics != null) {
        String appId(String? id, String file) =>
            id == null ? "NOT FOUND in $file" : "$id ($file)";

        if (platform.availableOnAndroid) {
          info.writeln(
            _formatField(
              "Crashlytics android",
              appId(
                crashlytics.androidAppId,
                "android/app/google-services.json",
              ),
            ),
          );
        }
        if (platform.availableOnIos) {
          info.writeln(
            _formatField(
              "Crashlytics ios",
              appId(
                crashlytics.iosAppId,
                "ios/Runner/GoogleService-Info.plist",
              ),
            ),
          );
        }
        info.writeln(
          _formatField(
            "Firebase account",
            crashlytics.account ?? "NOT LOGGED IN (run `firebase login`)",
          ),
        );
      }
      if (symbols.newRelic case final newRelic?) {
        for (final platform in [AppPlatform.android, AppPlatform.ios]) {
          final source = newRelic.tokenFor(platform);
          if (source == null || !platform.isIn(config.platform)) continue;
          info.writeln(
            _formatField(
              "New Relic ${platform.value} token",
              "${source.description} (${_hasToken(source) ? "found" : "NOT FOUND"})",
            ),
          );
        }
      }
      info.writeln(
        _formatField(
          "On Upload Failure",
          symbols.failOnUploadError ? "fail the run" : "warn, retry later",
        ),
      );
    }

    final allowedPluginsPath = config.allowedPluginsPath;
    if (allowedPluginsPath != null) {
      info.writeln();
      info.writeln(_formatField("Allowed Plugins", allowedPluginsPath));
    }

    if (uploadType.availableOnAppDistribution) {
      final distributionConfig = config.appDistributionConfig!;

      info.writeln();
      info.writeln("---- App Distribution Details ----");

      if (platform.availableOnAndroid) {
        info.writeln(
          _formatField(
            "Android Firebase App Id",
            distributionConfig.accountConfig.androidId!,
          ),
        );

        info.writeln(
          _formatField(
            "Android Build Type",
            distributionConfig.androidBuildType.value,
          ),
        );

        info.writeln(
          _formatField(
            "Android Testers",
            StringUtils.truncate(distributionConfig.formattedAndroidTesters),
          ),
        );

        info.writeln(
          _formatField(
            "Android Groups",
            StringUtils.truncate(distributionConfig.formattedAndroidGroups),
          ),
        );
      }

      if (platform.availableOnIos) {
        info.writeln(
          _formatField(
            "iOS Firebase App Id",
            distributionConfig.accountConfig.iosId!,
          ),
        );

        info.writeln(
          _formatField(
            "iOS Testers",
            StringUtils.truncate(distributionConfig.formattedIosTesters),
          ),
        );

        info.writeln(
          _formatField(
            "iOS Groups",
            StringUtils.truncate(distributionConfig.formattedIosGroups),
          ),
        );
      }

      info.writeln();
      info.writeln("---- Release Notes ----");
      info.writeln(distributionConfig.formattedReleaseNotes);
    }

    if (uploadType.availableOnStore && platform.availableOnAndroid) {
      final playStoreConfig = config.playStoreConfig!;

      info.writeln();
      info.writeln("---- Play Console Details ----");
      info.writeln(_formatField("Track", playStoreConfig.track.value));
      info.writeln(
        _formatField("Release Status", playStoreConfig.releaseStatus.value),
      );
    }

    Printer.info("$info");
  }

  String _archivePath(SymbolsConfig symbols) {
    try {
      return symbols.resolveArchivePath(
        projectRoot: Directory.current.path,
        environment: Platform.environment,
      );
    } on StateError {
      return symbols.archivePath;
    }
  }

  /// Whether the token is where [source] says, without printing it.
  bool _hasToken(TokenSource source) =>
      SecretHelper(
        projectRoot: Directory.current.path,
        environment: Platform.environment,
      ).resolve(source) !=
      null;

  String _formatParameters(List<String> parameters) =>
      parameters.isEmpty ? "(none)" : parameters.join(" ");

  String _formatField(String label, String value) {
    return "$label: ".padRight(25) + value;
  }
}

class CrashlyticsTarget {
  final String? androidAppId;
  final String? iosAppId;
  final String? account;

  const CrashlyticsTarget({this.androidAppId, this.iosAppId, this.account});
}
