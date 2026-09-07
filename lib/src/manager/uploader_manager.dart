import "dart:convert";
import "dart:io";

import "package:uploader/src/config/uploader_config.dart";
import "package:uploader/src/enum/enums.dart";
import "package:uploader/src/helper/parse_helper.dart";
import "package:uploader/src/model/app_detail.dart";
import "package:uploader/src/service/android_upload_service.dart";
import "package:uploader/src/service/ios_upload_service.dart";
import "package:uploader/src/service/process_service.dart";
import 'package:uploader/src/util/printer.dart';
import "package:uploader/src/util/string_utils.dart";

class UploaderManager {
  final UploaderConfig config;

  final processService = ProcessService();
  final parseHelper = ParseHelper();

  UploaderManager({required this.config});

  Future<bool> startUpload() async {
    final appDetail = await parseHelper.getAppDetails();
    if (appDetail == null) {
      Printer.error("app detail not found");
      return false;
    } else {
      showProjectDetails(appDetail);

      if (config.isDryRun) {
        Printer.warning(
          "DRY RUN: no build will run and nothing will be uploaded.",
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
