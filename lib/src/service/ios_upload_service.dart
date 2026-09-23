import 'dart:io';

import 'package:uploader/src/config/ios/ios_account_config.dart';
import 'package:uploader/src/config/uploader_config.dart';
import 'package:uploader/src/constants/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/ipa_size_helper.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/util/printer.dart';
import 'package:uploader/src/util/retry_utils.dart';

class IosUploadService {
  final UploaderConfig config;

  IosUploadService(this.config);

  late final processService = ProcessService(dryRun: config.isDryRun);

  final ipaSizeHelper = IpaSizeHelper();

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

    await _reportIpaSize(ipaName);

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

    await _reportIpaSize(ipaName);

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

  /// Reports how large the archive that was just built is. The run is never
  /// stopped: whether an oversized build is still worth delivering is a call
  /// for whoever reads the warning, and stopping here would also strand the
  /// artifact after a successful build.
  Future<void> _reportIpaSize(String ipaName) async {
    final ipaPath = PathConstants.ipaPath(ipaName);

    // A dry run never produces an archive, and that is not worth a warning.
    if (!File(ipaPath).existsSync()) return;

    final report = await ipaSizeHelper.inspect(ipaPath);
    if (report == null) {
      Printer.warning(
        "[ios] the IPA size could not be read, so it was not checked against "
        "the $appStoreSizeLimitMb MB App Store limit. `unzip` has to be on the "
        "PATH for this check to run",
      );
      return;
    }

    final size = report.payloadSizeInMb.toStringAsFixed(1);
    final remaining = report.remainingMb.toStringAsFixed(1);

    if (report.exceedsLimit) {
      Printer.error(
        "[ios] IPA payload is $size MB, "
        "${report.overLimitMb.toStringAsFixed(1)} MB over the "
        "$appStoreSizeLimitMb MB App Store limit. The upload was not stopped\n"
        "${ipaSizeHelper.describeLargestEntries(report)}",
      );
      return;
    }

    if (!report.isListingComplete) {
      Printer.warning(
        "[ios] only ${report.parsedBytes} of the ${report.listingBytes} bytes "
        "unzip listed could be read, so $size MB is a lower bound and the "
        "$appStoreSizeLimitMb MB App Store limit could not be ruled out\n"
        "${ipaSizeHelper.describeLargestEntries(report)}",
      );
      return;
    }

    if (report.isCloseToLimit) {
      Printer.warning(
        "[ios] IPA payload is $size MB, only $remaining MB under the "
        "$appStoreSizeLimitMb MB App Store limit\n"
        "${ipaSizeHelper.describeLargestEntries(report)}",
      );
      return;
    }

    Printer.infoIOS(
      "[ios] IPA payload is $size MB, $remaining MB under the "
      "$appStoreSizeLimitMb MB App Store limit",
    );
  }
}
