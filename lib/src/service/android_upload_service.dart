import 'dart:io';

import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:uploader/src/config/android/android_account_config.dart';
import 'package:uploader/src/config/uploader_config.dart';
import 'package:uploader/src/constants/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/util/printer.dart';
import 'package:uploader/src/util/retry_utils.dart';

class AndroidUploadService {
  final UploaderConfig config;

  AndroidUploadService(this.config);

  late final processService = ProcessService(dryRun: config.isDryRun);

  Future<bool> upload(String? firebaseAppId) async {
    Printer.infoAndroid(
      "[android] UPLOAD PROCESS STARTED FOR ANDROID",
      bold: true,
    );
    final uploadType = config.uploadType;

    if (uploadType.availableOnAppDistribution && firebaseAppId == null) {
      return Printer.error(
        "[android] app distribution was requested but the firebase app id "
        "could not be resolved",
      );
    }

    if (uploadType.availableOnAppDistribution) {
      final isSuccess = await uploadToAppDistribution(
        firebaseAppId: firebaseAppId!,
      );
      if (!isSuccess) return false;
    }

    if (uploadType.availableOnStore) {
      // Built separately from the App Distribution artifact so the two can
      // carry different parameters. In abb mode that means two bundles when
      // both targets are requested.
      if (!await buildAbb(BuildTarget.store)) return false;

      final isSuccess = await uploadToPlayConsole(
        accountConfig: config.playStoreConfig!.accountConfig!,
      );
      if (!isSuccess) return false;
    }

    Printer.success(
      "[android] UPLOAD PROCESS COMPLETED FOR ANDROID",
      bold: true,
    );
    return true;
  }

  Future<bool> buildAbb(BuildTarget target) async {
    Printer.infoAndroid("[android] abb building...");

    final isSuccess = await processService.buildAbb(
      skslPath: config.playStoreConfig!.skslPath,
      extraBuildParameters: config.buildParametersFor(target),
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

  Future<bool> buildApk() async {
    Printer.infoAndroid("[android] apk building...");

    final isSuccess = await processService.buildApk(
      extraBuildParameters: config.buildParametersFor(
        BuildTarget.appDistribution,
      ),
    );

    if (!isSuccess) {
      return Printer.error(
        "[android] process cannot continue because "
        "APK file could not be created",
      );
    }

    return Printer.success(
      "[android] APK file created: "
      "${PathConstants.apkPath}",
    );
  }

  Future<bool> uploadToAppDistribution({required String firebaseAppId}) async {
    final appDistributionConfig = config.appDistributionConfig!;

    if (appDistributionConfig.androidBuildType.isApk) {
      if (!await buildApk()) return false;

      Printer.infoAndroid("[android] apk uploading to app distribution...");

      final isSuccess = await RetryUtils.run(
        () => processService.uploadApkToAppDistribution(
          firebaseAppId: firebaseAppId,
          testers: appDistributionConfig.androidTesters,
          groups: appDistributionConfig.androidGroups,
          releaseNotes: appDistributionConfig.formattedReleaseNotes,
        ),
        retryCount: config.uploadRetryCount,
        label: "[android] apk upload to app distribution",
      );
      if (!isSuccess) {
        return Printer.error(
          "[android] process cannot continue because "
          "APK file could not be uploaded to distribution",
        );
      }

      return Printer.success("[android] APK file uploaded to app distribution");
    } else {
      if (!await buildAbb(BuildTarget.appDistribution)) return false;

      Printer.infoAndroid("[android] abb uploading to app distribution...");

      final isSuccess = await RetryUtils.run(
        () => processService.uploadAbbToAppDistribution(
          firebaseAppId: firebaseAppId,
          testers: appDistributionConfig.androidTesters,
          groups: appDistributionConfig.androidGroups,
          releaseNotes: appDistributionConfig.formattedReleaseNotes,
        ),
        retryCount: config.uploadRetryCount,
        label: "[android] abb upload to app distribution",
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

    if (config.isDryRun) {
      Printer.info(
        "[android] would upload ${PathConstants.abbRelativePath} to "
        "${playStoreConfig.packageName} on track "
        "'${playStoreConfig.track.value}' with status "
        "'${playStoreConfig.releaseStatus.value}'",
      );
      return true;
    }

    return await RetryUtils.run(
      () => _uploadToPlayConsole(accountConfig),
      retryCount: config.uploadRetryCount,
      label: "[android] abb upload to play console",
    );
  }

  Future<bool> _uploadToPlayConsole(AndroidAccountConfig accountConfig) async {
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
        uploadMedia: Media(stream, await abbFile.length()),
      );

      final versionCode = bundle.versionCode;

      await androidPublisher.edits.tracks.update(
        Track(
          track: playStoreConfig.track.value,
          releases: [
            TrackRelease(
              versionCodes: ["$versionCode"],
              status: playStoreConfig.releaseStatus.value,
            ),
          ],
        ),
        playStoreConfig.packageName,
        editId,
        playStoreConfig.track.value,
      );

      await androidPublisher.edits.commit(playStoreConfig.packageName, editId);
    } catch (e) {
      Printer.error("$e");
      return Printer.error(
        "[android] process cannot continue because "
        "ABB file could not be uploaded to play console",
      );
    }

    return Printer.success(
      "ABB file uploaded to Play Console "
      "(track: ${playStoreConfig.track.value}, "
      "status: ${playStoreConfig.releaseStatus.value})",
    );
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
