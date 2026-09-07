import 'package:test/test.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/pubspec_parameters.dart';
import 'package:yaml/yaml.dart';

PubspecParameters parse(String yaml) =>
    PubspecParameters.fromPubspec(loadYaml(yaml) as Map);

void main() {
  group('defaults', () {
    final params = parse('''
uploader:
  platform: all
  uploadType: all
''');

    test('platform and upload type are read', () {
      expect(params.platform, AppPlatform.all);
      expect(params.uploadType, UploadType.all);
    });

    test('play store release defaults to a completed internal release', () {
      expect(params.androidTrack, AndroidTrack.internal);
      expect(params.androidReleaseStatus, ReleaseStatus.completed);
    });

    test('uploads are retried twice unless configured otherwise', () {
      expect(params.uploadRetryCount, 2);
    });

    test('optional lists stay null rather than empty', () {
      expect(params.extraBuildParameters, isNull);
      expect(params.appDistributionAndroidGroups, isNull);
      expect(params.appDistributionIosGroups, isNull);
      expect(params.appDistributionReleaseNotesPath, isNull);
      expect(params.appDistributionExtraBuildParameters, isNull);
      expect(params.storeExtraBuildParameters, isNull);
    });
  });

  test('a pubspec without an uploader section yields empty parameters', () {
    final params = parse('name: some_app\n');

    expect(params.platform, isNull);
    expect(params.uploadType, isNull);
    expect(params.extraBuildParameters, isNull);
    expect(params.uploadRetryCount, 2);
  });

  group('play store release controls', () {
    test('a draft release is read', () {
      final params = parse('''
uploader:
  platform: android
  uploadType: store
  playStoreConfig:
    track: beta
    releaseStatus: draft
''');

      expect(params.androidTrack, AndroidTrack.beta);
      expect(params.androidReleaseStatus, ReleaseStatus.draft);
    });

    test('an unknown status falls back to completed', () {
      final params = parse('''
uploader:
  playStoreConfig:
    releaseStatus: whatever
''');

      expect(params.androidReleaseStatus, ReleaseStatus.completed);
    });

    test('production is not a supported track', () {
      final params = parse('''
uploader:
  playStoreConfig:
    track: production
''');

      expect(params.androidTrack, AndroidTrack.internal);
      expect(
        AndroidTrack.values.map((track) => track.value),
        isNot(contains("production")),
      );
    });
  });

  group('app distribution groups', () {
    test('groups are read as plain lists', () {
      final params = parse('''
uploader:
  appDistributionConfig:
    androidGroups:
      - qa
      - internal
    iosGroups:
      - qa
''');

      expect(params.appDistributionAndroidGroups, ["qa", "internal"]);
      expect(params.appDistributionIosGroups, ["qa"]);
    });
  });

  test('release notes path is read from the app distribution section', () {
    final params = parse('''
uploader:
  appDistributionConfig:
    releaseNotesPath: notes.txt
''');

    expect(params.appDistributionReleaseNotesPath, "notes.txt");
  });

  group('upload retry count', () {
    test('an explicit count is honoured, including zero', () {
      expect(parse('uploader:\n  uploadRetryCount: 0\n').uploadRetryCount, 0);
      expect(parse('uploader:\n  uploadRetryCount: 5\n').uploadRetryCount, 5);
    });

    test('a negative count falls back to the default', () {
      expect(parse('uploader:\n  uploadRetryCount: -1\n').uploadRetryCount, 2);
    });
  });

  test('per target build parameters are read', () {
    final params = parse('''
uploader:
  extraBuildParameters:
    - --common
  appDistributionExtraBuildParameters:
    - --dart-define=APP_CHANNEL=staging
  storeExtraBuildParameters:
    - --store-only
''');

    expect(params.extraBuildParameters, ["--common"]);
    expect(params.appDistributionExtraBuildParameters, [
      "--dart-define=APP_CHANNEL=staging",
    ]);
    expect(params.storeExtraBuildParameters, ["--store-only"]);
  });

  test('extra build parameters keep every element', () {
    final params = parse('''
uploader:
  extraBuildParameters:
    - --dart-define=A=1
    - --dart-define=B=2
''');

    expect(params.extraBuildParameters, [
      "--dart-define=A=1",
      "--dart-define=B=2",
    ]);
  });
}
