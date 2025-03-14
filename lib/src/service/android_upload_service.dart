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
    Printer.infoAndroid(
      "[android] UPLOAD PROCESS STARTED FOR ANDROID",
      bold: true,
    );
    final androidAccountConfig = config.playStoreConfig!.accountConfig;
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
      isSuccess = await uploadToPlayConsole(
        accountConfig: androidAccountConfig!,
      );
    }
    if (isSuccess) {
      Printer.success(
        "[android] UPLOAD PROCESS COMPLETED FOR ANDROID",
        bold: true,
      );
      return true;
    }
    return false;
  }

  Future<bool> buildAbb() async {
    Printer.infoAndroid("[android] abb building...");

    bool isSuccess = await processService.buildAbb(
      skslPath: config.playStoreConfig!.skslPath,
      extraBuildParameters: config.extraBuildParameters,
    );

    if (!isSuccess) {
      return Printer.error(
        "[android] process cannot continue because "
        "ABB file could not be created",
      );
    }

    return Printer.success(
      "[android] ABB file created: "
      "${PathConstants.abbPath}",
    );
  }

  Future<bool> uploadToAppDistribution({required String firebaseAppId}) async {
    final appDistributionConfig = config.appDistributionConfig!;

    if (appDistributionConfig.androidBuildType.isApk) {
      Printer.infoAndroid("[android] apk building...");

      bool isSuccess = await processService.buildApk(
        extraBuildParameters: config.extraBuildParameters,
      );
      if (!isSuccess) {
        return Printer.error(
          "[android] process cannot continue because APK file could not be created",
        );
      }

      Printer.success(
        "[android] APK file created: "
        "${PathConstants.apkPath}",
      );

      Printer.infoAndroid("[android] apk uploading to app distribution...");

      isSuccess = await processService.uploadApkToAppDistribution(
        firebaseAppId: firebaseAppId,
        testers: appDistributionConfig.androidTesters,
        releaseNotes: appDistributionConfig.formattedReleaseNotes,
      );
      if (!isSuccess) {
        return Printer.error(
          "[android] process cannot continue because "
          "APK file could not be uploaded to distribution",
        );
      }

      return Printer.success("[android] APK file uploaded to app distribution");
    } else {
      Printer.infoAndroid("[android] abb uploading to app distribution...");

      bool isSuccess = await processService.uploadAbbToAppDistribution(
        firebaseAppId: firebaseAppId,
        testers: appDistributionConfig.androidTesters,
        releaseNotes: appDistributionConfig.formattedReleaseNotes,
      );
      if (!isSuccess) {
        return Printer.error(
          "[android] process cannot continue because "
          "ABB file could not be uploaded to app distribution",
        );
      }
      return Printer.success("[android] ABB file uploaded to app distribution");
    }
  }

  Future<bool> uploadToPlayConsole({
    required AndroidAccountConfig accountConfig,
  }) async {
    Printer.infoAndroid("[android] abb uploading to play console...");

    final playStoreConfig = config.playStoreConfig!;

    try {
      final credential = await _createCredentials(accountConfig);
      final androidPublisher = AndroidPublisherApi(credential);

      final edits = await androidPublisher.edits.insert(
        AppEdit(),
        playStoreConfig.packageName,
      );

      final editId = edits.id;
      if (editId == null) return false;

      final abbFile = File(PathConstants.abbPath);
      final Stream<List<int>> stream = abbFile.openRead();

      final bundle = await androidPublisher.edits.bundles.upload(
        playStoreConfig.packageName,
        editId,
        uploadMedia: Media(
          stream,
          await abbFile.length(),
        ),
      );

      final versionCode = bundle.versionCode;

      await androidPublisher.edits.tracks.update(
        Track(
          track: playStoreConfig.track.value,
          releases: [
            TrackRelease(
              versionCodes: ["$versionCode"],
              status: "completed",
            )
          ],
        ),
        playStoreConfig.packageName,
        editId,
        playStoreConfig.track.value,
      );

      await androidPublisher.edits.commit(
        playStoreConfig.packageName,
        editId,
      );
    } catch (e) {
      Printer.error("$e");
      return Printer.error(
        "[android] process cannot continue because "
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
