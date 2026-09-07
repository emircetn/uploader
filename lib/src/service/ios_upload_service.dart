import 'package:uploader/src/config/ios/ios_account_config.dart';
import 'package:uploader/src/config/uploader_config.dart';
import 'package:uploader/src/constants/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/util/printer.dart';
import 'package:uploader/src/util/retry_utils.dart';

class IosUploadService {
  final UploaderConfig config;

  IosUploadService(this.config);

  late final processService = ProcessService(dryRun: config.isDryRun);

  Future<bool> upload(String? firebaseAppId) async {
    Printer.infoIOS("[ios] UPLOAD PROCESS STARTED FOR IOS", bold: true);
    final ipaName = config.iosConfig!.ipaName;
    final uploadType = config.uploadType;

    if (uploadType.availableOnAppDistribution && firebaseAppId == null) {
      return Printer.error(
        "[ios] app distribution was requested but the firebase app id "
        "could not be resolved",
      );
    }

    if (uploadType.availableOnAppDistribution) {
      final isSuccess = await uploadToAppDistribution(
        ipaName: ipaName,
        firebaseAppId: firebaseAppId!,
      );
      if (!isSuccess) return false;
    }
    if (uploadType.availableOnStore) {
      final isSuccess = await uploadToTestFlight(
        ipaName: ipaName,
        accountConfig: config.iosConfig!.accountConfig!,
      );
      if (!isSuccess) return false;
    }

    Printer.success("[ios] UPLOAD PROCESS COMPLETED FOR IOS", bold: true);
    return true;
  }

  Future<bool> uploadToAppDistribution({
    required String ipaName,
    required String firebaseAppId,
  }) async {
    final appDistributionConfig = config.appDistributionConfig!;

    Printer.infoIOS("[ios] IPA(adhoc) building...");

    bool isSuccess = await processService.buildIpa(
      type: IPAType.adHoc,
      extraBuildParameters: config.buildParametersFor(
        BuildTarget.appDistribution,
      ),
    );
    if (!isSuccess) {
      return Printer.error(
        "[ios] process cannot continue because "
        "IPA(adHoc) file could not be created",
      );
    }

    Printer.success(
      "[ios] IPA(adHoc) file created: "
      "${PathConstants.ipaPath(ipaName)}",
    );

    Printer.infoIOS("[ios] IPA(adhoc) uploading to app distribution...");

    isSuccess = await RetryUtils.run(
      () => processService.uploadIpaToAppDistribution(
        firebaseAppId: firebaseAppId,
        ipaName: ipaName,
        testers: appDistributionConfig.iosTesters,
        groups: appDistributionConfig.iosGroups,
        releaseNotes: appDistributionConfig.formattedReleaseNotes,
      ),
      retryCount: config.uploadRetryCount,
      label: "[ios] ipa upload to app distribution",
    );
    if (!isSuccess) {
      return Printer.error(
        "[ios] process cannot continue because "
        "IPA(adHoc) file could not be uploaded",
      );
    }
    return Printer.success(
      "[ios] IPA(adHoc) file uploaded to app distribution",
    );
  }

  Future<bool> uploadToTestFlight({
    required String ipaName,
    required IosAccountConfig accountConfig,
  }) async {
    Printer.infoIOS("[ios] IPA(appStore) building...");

    bool isSuccess = await processService.buildIpa(
      type: IPAType.appStore,
      extraBuildParameters: config.buildParametersFor(BuildTarget.store),
    );
    if (!isSuccess) {
      return Printer.error(
        "[ios] process cannot continue because "
        "IPA(appStore) file could not be created",
      );
    }
    Printer.success(
      "[ios] IPA(appStore) file created: "
      "${PathConstants.ipaPath(ipaName)}",
    );

    Printer.infoIOS("[ios] IPA(appStore) uploading to testflight...");

    isSuccess = await RetryUtils.run(
      () => processService.uploadToTestFlight(
        testFlightConfig: config.iosConfig!,
        accountConfig: accountConfig,
        ipaName: ipaName,
      ),
      retryCount: config.uploadRetryCount,
      label: "[ios] ipa upload to testflight",
    );
    if (!isSuccess) {
      return Printer.error(
        "[ios] process cannot continue because "
        "IPA(appStore) file could not be uploaded to testflight",
      );
    }
    return Printer.success("[ios] IPA(appStore) file uploaded to testflight");
  }
}
