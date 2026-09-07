import 'dart:io';

import 'package:test/test.dart';
import 'package:uploader/src/constants/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/util/string_utils.dart';

void main() {
  group('PathConstants', () {
    final basePath = Directory.current.path;

    test('abbPath resolves the bundle output', () {
      expect(
        PathConstants.abbPath,
        "$basePath/${PathConstants.abbRelativePath}",
      );
    });

    test('apkPath resolves the apk output, not the bundle one', () {
      expect(
        PathConstants.apkPath,
        "$basePath/${PathConstants.apkRelativePath}",
      );
      expect(PathConstants.apkPath, isNot(PathConstants.abbPath));
    });

    test('ipaPath is built from the app name', () {
      expect(
        PathConstants.ipaPath("MyApp"),
        "$basePath/build/ios/ipa/MyApp.ipa",
      );
    });
  });

  group('StringUtils.truncate', () {
    test('keeps text shorter than the limit untouched', () {
      expect(StringUtils.truncate("short", maxLength: 10), "short");
    });

    test('truncates longer text to the limit with an ellipsis', () {
      final result = StringUtils.truncate("abcdefghijkl", maxLength: 8);
      expect(result, "abcde...");
      expect(result.length, 8);
    });
  });

  group('enum availability flags', () {
    test('AppPlatform', () {
      expect(AppPlatform.all.availableOnAndroid, isTrue);
      expect(AppPlatform.all.availableOnIos, isTrue);
      expect(AppPlatform.ios.availableOnAndroid, isFalse);
      expect(AppPlatform.android.availableOnIos, isFalse);
    });

    test('UploadType', () {
      expect(UploadType.all.availableOnStore, isTrue);
      expect(UploadType.all.availableOnAppDistribution, isTrue);
      expect(UploadType.appDistribution.availableOnStore, isFalse);
      expect(UploadType.store.availableOnAppDistribution, isFalse);
    });

    test('AndroidBuildType', () {
      expect(AndroidBuildType.apk.isApk, isTrue);
      expect(AndroidBuildType.apk.isAbb, isFalse);
      expect(AndroidBuildType.abb.isAbb, isTrue);
    });
  });
}
