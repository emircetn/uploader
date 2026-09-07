import 'dart:io';

import 'package:test/test.dart';
import 'package:uploader/src/helper/parse_helper.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('uploader_parse_helper');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  ParseHelper helperFor(String content) {
    final path = '${tempDir.path}/pubspec.yaml';
    File(path).writeAsStringSync(content);
    return ParseHelper(pubspecPath: path);
  }

  test('reads the name and splits the version from the build number', () async {
    final detail = await helperFor(
      'name: my_app\nversion: 1.2.3+45\n',
    ).getAppDetails();

    expect(detail, isNotNull);
    expect(detail!.appName, "my_app");
    expect(detail.buildVersion, "1.2.3");
    expect(detail.buildNumber, "45");
  });

  test('a version without a build number is not an error', () async {
    final detail = await helperFor(
      'name: my_app\nversion: 1.2.3\n',
    ).getAppDetails();

    expect(detail, isNotNull);
    expect(detail!.buildVersion, "1.2.3");
    expect(detail.buildNumber, isNull);
  });

  test('a key that merely contains "name:" is not mistaken for the '
      'project name', () async {
    final detail = await helperFor('''
name: my_app
version: 1.0.0+1
uploader:
  playStoreConfig:
    packageName: com.example.other
''').getAppDetails();

    expect(detail!.appName, "my_app");
  });

  test('a quoted numeric version is still split correctly', () async {
    final detail = await helperFor(
      'name: my_app\nversion: "2.0+7"\n',
    ).getAppDetails();

    expect(detail!.buildVersion, "2.0");
    expect(detail.buildNumber, "7");
  });

  test('a pubspec without a version yields no detail', () async {
    expect(await helperFor('name: my_app\n').getAppDetails(), isNull);
  });

  test('a missing pubspec yields no detail', () async {
    final helper = ParseHelper(pubspecPath: '${tempDir.path}/nope.yaml');
    expect(await helper.getAppDetails(), isNull);
  });
}
