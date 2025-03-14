import 'package:uploader/src/config/ios/ios_account_config.dart';
import 'package:uploader/src/config/uploader_config.dart';
import 'package:uploader/src/constant/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/util/printer.dart';

class IosUploadService {
  final UploaderConfig config;

  IosUploadService(this.config);

  final processService = ProcessService();

  Future<bool> upload(String? firebaseAppId) async {
    Printer.infoIOS("[ios] UPLOAD PROCESS STARTED FOR IOS", bold: true);
    final iosAccountConfig = config.testFlightConfig!.accountConfig;
    final ipaName = config.testFlightConfig!.ipaName;
    final uploadType = config.uploadType;

    final availableOnAppDistribution =
        firebaseAppId != null && uploadType.availableOnAppDistribution;

    bool? isSuccess;
    if (availableOnAppDistribution) {
      isSuccess = await uploadToAppDistribution(
        ipaName: ipaName,
        firebaseAppId: firebaseAppId,
      );
      if (!isSuccess) return false;
    }
    if (uploadType.availableOnStore) {
      isSuccess = await uploadToTestFlight(
        ipaName: ipaName,
        accountConfig: iosAccountConfig!,
      );
    }
    if (isSuccess == true) {
      Printer.success("[ios] UPLOAD PROCESS COMPLETED FOR IOS", bold: true);
      return true;
    } else {
      return false;
    }
  }

  Future<bool> uploadToAppDistribution({
    required String ipaName,
    required String firebaseAppId,
  }) async {
    final appDistributionConfig = config.appDistributionConfig!;

    Printer.infoIOS("[ios] IPA(adhoc) building...");

    bool isSuccess = await processService.buildIpa(
      type: IPAType.adHoc,
      extraBuildParameters: config.extraBuildParameters,
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

    isSuccess = await processService.uploadIpaToAppDistribution(
      firebaseAppId: firebaseAppId,
      ipaName: ipaName,
      testers: appDistributionConfig.iosTesters,
      releaseNotes: appDistributionConfig.formattedReleaseNotes,
    );
    if (!isSuccess) {
      return Printer.error(
        "[ios] process cannot continue because "
        "IPA(adHoc) file could not be uploaded",
      );
    }
    return Printer.success(
        "[ios] IPA(adHoc) file uploaded to app distribution");
  }

  Future<bool> uploadToTestFlight({
    required String ipaName,
    required IosAccountConfig accountConfig,
  }) async {
    Printer.infoIOS("[ios] IPA(appStore) building...");

    bool isSuccess = await processService.buildIpa(
      type: IPAType.appStore,
      extraBuildParameters: config.extraBuildParameters,
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

    isSuccess = await processService.uploadToTestFlight(
      testFlightConfig: config.testFlightConfig!,
      accountConfig: accountConfig,
      ipaName: ipaName,
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
