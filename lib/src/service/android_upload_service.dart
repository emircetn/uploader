import 'dart:io';

import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:uploader/src/config/android/android_account_config.dart';
import 'package:uploader/src/config/uploader_config.dart';
import 'package:uploader/src/constant/path_constants.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/util/printer.dart';

class AndroidUploadService {
  final UploaderConfig config;

  AndroidUploadService(this.config);

  final processService = ProcessService();

  Future<bool> upload(String? firebaseAppId) async {
    Printer.info("UPLOAD PROCESS STARTED FOR ANDROID", bold: true);
    final androidAccountConfig = config.androidConfig!.accountConfig;
    final uploadType = config.uploadType;

    bool isSuccess = await buildAbb();
    if (!isSuccess) return false;

    final availableOnAppDistribution =
        uploadType.availableOnAppDistribution && firebaseAppId != null;

    if (availableOnAppDistribution) {
      bool isSuccess = await uploadToAppDistribution(
        firebaseAppId: firebaseAppId,
      );
      if (!isSuccess) return false;
    }
    if (uploadType.availableOnStore) {
      return await uploadToPlayConsole(accountConfig: androidAccountConfig!);
    }
    return false;
  }

  Future<bool> buildAbb() async {
    Printer.info("abb building...");

    bool isSuccess = await processService.buildAbb(
      skslPath: config.androidConfig!.skslPath,
      extraBuildParameters: config.extraBuildParameters,
    );

    if (!isSuccess) {
      return Printer.error(
        "process cannot continue because "
        "ABB file could not be created",
      );
    }

    return Printer.success(
      "ABB file created: "
      "${PathConstants.abbPath}",
    );
  }

  Future<bool> uploadToAppDistribution({required String firebaseAppId}) async {
    final appDistributionConfig = config.appDistributionConfig!;

    if (appDistributionConfig.androidBuildType.isApk) {
      Printer.info("apk building...");

      bool isSuccess = await processService.buildApk(
        extraBuildParameters: config.extraBuildParameters,
      );
      if (!isSuccess) {
        return Printer.error(
          "process cannot continue because APK file could not be created",
        );
      }

      Printer.success(
        "APK file created: "
        "${PathConstants.apkPath}",
      );

      Printer.info("apk uploading to app distribution...");

      isSuccess = await processService.uploadApkToAppDistribution(
        firebaseAppId: firebaseAppId,
        testers: appDistributionConfig.androidTesters,
        releaseNotes: appDistributionConfig.showReleaseNotes,
      );
      if (!isSuccess) {
        return Printer.error(
          "process cannot continue because "
          "APK file could not be uploaded to distribution",
        );
      }

      return Printer.success("APK file uploaded to app distribution");
    } else {
      Printer.info("abb uploading to app distribution...");

      bool isSuccess = await processService.uploadAbbToAppDistribution(
        firebaseAppId: firebaseAppId,
        testers: appDistributionConfig.androidTesters,
        releaseNotes: appDistributionConfig.showReleaseNotes,
      );
      if (!isSuccess) {
        return Printer.error(
          "process cannot continue because "
          "ABB file could not be uploaded to app distribution",
        );
      }
      return Printer.success("ABB file uploaded to app distribution");
    }
  }

  Future<bool> uploadToPlayConsole({
    required AndroidAccountConfig accountConfig,
  }) async {
    Printer.info("abb uploading to play console...");

    final androidConfig = config.androidConfig!;

    try {
      final credential = await _createCredentials(accountConfig);
      final androidPublisher = AndroidPublisherApi(credential);

      final edits = await androidPublisher.edits.insert(
        AppEdit(),
        androidConfig.packageName,
      );

      final editId = edits.id;
      if (editId == null) return false;

      final abbFile = File(PathConstants.abbPath);
      final Stream<List<int>> stream = abbFile.openRead();

      final bundle = await androidPublisher.edits.bundles.upload(
        androidConfig.packageName,
        editId,
        uploadMedia: Media(
          stream,
          await abbFile.length(),
        ),
      );

      final versionCode = bundle.versionCode;

      await androidPublisher.edits.tracks.update(
        Track(
          track: androidConfig.track.value,
          releases: [
            TrackRelease(
              versionCodes: ["$versionCode"],
              status: "completed",
            )
          ],
        ),
        androidConfig.packageName,
        editId,
        androidConfig.track.value,
      );

      await androidPublisher.edits.commit(androidConfig.packageName, editId);
    } catch (e) {
      Printer.error("$e");
      return Printer.error(
        "process cannot continue because "
        "ABB file could not be uploaded to play console",
      );
    }

    return Printer.success("ABB file uploaded to Play Console");
  }

  Future<AutoRefreshingAuthClient> _createCredentials(
    AndroidAccountConfig accountConfig,
  ) async {
    return await clientViaServiceAccount(
      ServiceAccountCredentials(
        accountConfig.clientEmail,
        ClientId(accountConfig.clientId),
        accountConfig.privateKey,
      ),
      ['https://www.googleapis.com/auth/androidpublisher'],
    );
  }
}
