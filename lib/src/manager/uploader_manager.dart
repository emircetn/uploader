import "dart:convert";
import "dart:io";

import "package:uploader/src/config/uploader_config.dart";
import "package:uploader/src/enum/enums.dart";
import "package:uploader/src/helper/parse_helper.dart";
import "package:uploader/src/model/app_detail.dart";
import "package:uploader/src/service/android_upload_service.dart";
import "package:uploader/src/service/ios_upload_service.dart";
import "package:uploader/src/service/plugin_guard_service.dart";
import "package:uploader/src/service/plugin_stub_service.dart";
import "package:uploader/src/service/process_service.dart";
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

      showProjectDetails(appDetail);

      if (config.isDryRun) {
        Printer.warning(
          "DRY RUN: no build will run and nothing will be uploaded.",
        );
      }
      if (config.isAudit) {
        Printer.warning(
          "AUDIT: each platform is built once for code size analysis; "
          "nothing will be uploaded.",
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

      pluginStubService.backUp();
      try {
        final analysis = await pluginGuardService.analyse();
        if (analysis == null) return false;

        final isStubbed = await pluginStubService.apply(
          autoStubs: analysis.autoStubs,
        );
        if (!isStubbed) return false;

        final isSafe = await pluginGuardService.check(
          stubs: pluginStubService.appliedPlans,
          analysis: analysis,
        );
        if (!isSafe) return false;
        if (config.isAudit) return true;
        return await _runUploads();
      } finally {
        await pluginStubService.restore();
      }
    }
  }

  Future<bool> _runUploads() async {
    final process = [
      if (config.platform.availableOnAndroid)
        () => AndroidUploadService(
          config,
        ).upload(config.appDistributionConfig?.accountConfig.androidId),
      if (config.platform.availableOnIos)
        () => IosUploadService(
          config,
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

  void showProjectDetails(AppDetail appDetail) {
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

  String _formatParameters(List<String> parameters) =>
      parameters.isEmpty ? "(none)" : parameters.join(" ");

  String _formatField(String label, String value) {
    return "$label: ".padRight(25) + value;
  }
}
