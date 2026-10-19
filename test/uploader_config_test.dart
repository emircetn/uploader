import 'package:test/test.dart';
import 'package:uploader/src/config/uploader_config.dart';
import 'package:uploader/src/enum/enums.dart';

UploaderConfig configWith({
  List<String>? common,
  List<String>? appDistribution,
  List<String>? store,
  Map<String, String>? commonEnv,
  Map<String, String>? appDistributionEnv,
  Map<String, String>? storeEnv,
}) => UploaderConfig(
  uploadType: UploadType.all,
  platform: AppPlatform.all,
  extraBuildParameters: common,
  appDistributionExtraBuildParameters: appDistribution,
  storeExtraBuildParameters: store,
  extraBuildEnvironment: commonEnv,
  appDistributionExtraBuildEnvironment: appDistributionEnv,
  storeExtraBuildEnvironment: storeEnv,
  useParallelUpload: true,
  enableLogFileCreation: false,
);

void main() {
  group('buildParametersFor', () {
    test('a target gets the common list followed by its own', () {
      final config = configWith(
        common: ["--common"],
        appDistribution: ["--appdist"],
        store: ["--store"],
      );

      expect(config.buildParametersFor(BuildTarget.appDistribution), [
        "--common",
        "--appdist",
      ]);
      expect(config.buildParametersFor(BuildTarget.store), [
        "--common",
        "--store",
      ]);
    });

    test('one target\'s list never leaks into the other', () {
      final config = configWith(appDistribution: ["--appdist"]);

      expect(config.buildParametersFor(BuildTarget.store), isEmpty);
      expect(config.buildParametersFor(BuildTarget.appDistribution), [
        "--appdist",
      ]);
    });

    test('without any list both targets get nothing', () {
      final config = configWith();

      expect(config.buildParametersFor(BuildTarget.appDistribution), isEmpty);
      expect(config.buildParametersFor(BuildTarget.store), isEmpty);
    });

    test('the common list alone still reaches both targets', () {
      final config = configWith(common: ["--common"]);

      expect(config.buildParametersFor(BuildTarget.appDistribution), [
        "--common",
      ]);
      expect(config.buildParametersFor(BuildTarget.store), ["--common"]);
    });
  });

  group('buildEnvironmentFor', () {
    test('a target gets the common map and its own on top', () {
      final config = configWith(
        commonEnv: {'A': '1', 'B': 'common'},
        appDistributionEnv: {'B': 'appdist'},
        storeEnv: {'C': 'store'},
      );

      expect(config.buildEnvironmentFor(BuildTarget.appDistribution), {
        'A': '1',
        'B': 'appdist',
      });
      expect(config.buildEnvironmentFor(BuildTarget.store), {
        'A': '1',
        'B': 'common',
        'C': 'store',
      });
    });

    test('one target\'s variable never reaches the other', () {
      final config = configWith(
        appDistributionEnv: {'FLUTTER_XCODE_STAGING': 'YES'},
      );

      expect(config.buildEnvironmentFor(BuildTarget.store), isEmpty);
      expect(config.buildEnvironmentFor(BuildTarget.appDistribution), {
        'FLUTTER_XCODE_STAGING': 'YES',
      });
    });
  });
}
