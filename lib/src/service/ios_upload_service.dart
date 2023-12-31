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
    Printer.info("UPLOAD PROCESS STARTED FOR IOS", bold: true);
    final iosAccountConfig = config.iosConfig!.accountConfig;
    final ipaName = config.iosConfig!.ipaName;

    final availableOnAppDistribution =
        firebaseAppId != null && config.uploadType.availableOnAppDistribution;

    if (availableOnAppDistribution) {
      bool isSuccess = await uploadToAppDistribution(
        ipaName: ipaName,
        firebaseAppId: firebaseAppId,
      );
      if (!isSuccess) return false;
    }

    return await uploadToTestFlight(
      ipaName: ipaName,
      accountConfig: iosAccountConfig,
    );
  }

  Future<bool> uploadToAppDistribution({
    required String ipaName,
    required String firebaseAppId,
  }) async {
    final appDistributionConfig = config.appDistributionConfig!;

    Printer.info("IPA(adhoc) building...");

    bool isSuccess = await processService.buildIpa(
      type: IPAType.adHoc,
      extraBuildParameters: config.extraBuildParameters,
    );
    if (!isSuccess) {
      return Printer.error(
        "process cannot continue because "
        "IPA(adHoc) file could not be created",
      );
    }

    Printer.success(
      "IPA(adHoc) file created: "
      "${PathConstants.ipaPath(ipaName)}",
    );

    Printer.info("IPA(adhoc) uploading to app distribution...");

    isSuccess = await processService.uploadIpaToAppDistribution(
      firebaseAppId: firebaseAppId,
      ipaName: ipaName,
      testers: appDistributionConfig.iosTesters,
      releaseNotes: appDistributionConfig.showReleaseNotes,
    );
    if (!isSuccess) {
      return Printer.error(
        "process cannot continue because "
        "IPA(adHoc) file could not be uploaded",
      );
    }
    return Printer.success("IPA(adHoc) file uploaded to app distribution");
  }

  Future<bool> uploadToTestFlight({
    required String ipaName,
    required IosAccountConfig accountConfig,
  }) async {
    Printer.info("IPA(appStore) building...");

    bool isSuccess = await processService.buildIpa(
      type: IPAType.appStore,
      extraBuildParameters: config.extraBuildParameters,
    );
    if (!isSuccess) {
      return Printer.error(
        "process cannot continue because "
        "IPA(appStore) file could not be created",
      );
    }
    Printer.success(
      "IPA(appStore) file created: "
      "${PathConstants.ipaPath(ipaName)}",
    );

    Printer.info("IPA(appStore) uploading to testflight...");

    isSuccess = await processService.uploadToTestFlight(
      iosConfig: config.iosConfig!,
      accountConfig: accountConfig,
      ipaName: ipaName,
    );
    if (!isSuccess) {
      return Printer.error(
        "process cannot continue because "
        "IPA(appStore) file could not be uploaded to testflight",
      );
    }
    return Printer.success("IPA(appStore) file uploaded to testflight");
  }
}
