import 'package:uploader/src/config/app_distribution/app_distribution_account_config.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/download_helper.dart';
import 'package:uploader/src/helper/file_helper.dart';
import 'package:uploader/src/model/data_source.dart';

class AppDistributionHelper {
  final _fileHelper = FileHelper();
  final _downloadHelper = DownloadHelper();

  Future<AppDistributionAccountConfig?> getAccountConfig(
    AppPlatform platform,
  ) async {
    try {
      String? androidAppId;
      String? iosAppId;

      if (platform.availableOnIos) {
        const iosGoogleServicePath = "ios/Runner/GoogleService-Info.plist";
        const iosAppIdKey = 'GOOGLE_APP_ID';
        const initTag = "<string>";
        const lastTag = "</string>";

        final lineList = await _fileHelper.readFileLines(iosGoogleServicePath);

        if (lineList != null) {
          final index =
              lineList.indexWhere((element) => element.contains(iosAppIdKey));
          final line = lineList[index + 1].trim();

          iosAppId = line.substring(
            initTag.length,
            line.length - lastTag.length,
          );
        }
      }

      if (platform.availableOnAndroid) {
        const androidGoogleServicePath = "android/app/google-services.json";
        const androidAppIdKey = 'mobilesdk_app_id';

        final lineList =
            await _fileHelper.readFileLines(androidGoogleServicePath);

        if (lineList != null) {
          final index = lineList.indexWhere(
            (element) => element.contains(
              androidAppIdKey,
            ),
          );

          final line = lineList[index].split('":').last;

          androidAppId = line.substring(2, line.length - 2).trim();
        }
      }
      return AppDistributionAccountConfig(
        iosId: iosAppId,
        androidId: androidAppId,
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<String>?> getTesters(DataSource source) async {
    if (source.hasPath) {
      return await _fileHelper.readFileLines(source.path!);
    } else if (source.hasUrl) {
      final file = await _downloadHelper.downloadFile(source.url!);
      return file.split('\n');
    }
    return null;
  }
}
