import 'package:test/test.dart';
import 'package:uploader/src/helper/code_size_helper.dart';

Map<String, dynamic> leaf(String name, int value) => {
  "n": name,
  "value": value,
};

Map<String, dynamic> node(String name, List<Map<String, dynamic>> children) => {
  "n": name,
  "children": children,
};

/// A function as the snapshot profile lists it: a named node with its code.
Map<String, dynamic> function(String name, {int size = 100}) =>
    node(name, [leaf("<Code>", 16), leaf("<(RO) Instructions>", size)]);

/// Shaped like `~/.flutter-devtools/ios-code-size-analysis_01.json`.
Map<String, dynamic> summaryWith(List<Map<String, dynamic>> packages) =>
    node("Root", [
      node("Runner.app", [
        node("Frameworks", [
          node("App.framework", [node("App (Dart AOT)", packages)]),
        ]),
        leaf("Info.plist", 2000),
      ]),
    ]);

void main() {
  final helper = CodeSizeHelper();

  group('packagesIn', () {
    final summary = summaryWith([
      node(
        "package:image_picker_ios/package:image_picker_ios/image_picker_ios.dart",
        [
          node("ImagePickerIOS", [
            function("new ImagePickerIOS."),
            function("registerWith"),
            function("Allocate ImagePickerIOS"),
            leaf("<Class>", 32),
          ]),
        ],
      ),
      node("package:file_picker", [
        node("package:file_picker/src", [
          node("file_picker.dart", [
            node("FilePicker", [
              node("_token", [leaf("<Field>", 17)]),
              function("init:_token"),
              function("set:platform"),
            ]),
          ]),
        ]),
      ]),
      node("package:path_provider_foundation", [
        node("path_provider_foundation_real.dart", [
          node("PathProviderFoundation", [
            function("registerWith"),
            function("getTemporaryPath", size: 68),
          ]),
        ]),
      ]),
      node("dart:core", [function("print")]),
      leaf("@shared", 10),
    ]);

    late final packages = helper.packagesIn(summary)!;

    test('a plugin that only registered itself is not reachable', () {
      expect(packages["image_picker_ios"]!.isReachable, isFalse);
      expect(packages["file_picker"]!.isReachable, isFalse);
    });

    test('a plugin with a called function is reachable', () {
      expect(packages["path_provider_foundation"]!.functions, [
        "getTemporaryPath",
      ]);
    });

    test('collapsed package names are read by their package', () {
      expect(packages.keys, contains("image_picker_ios"));
    });

    test('a package weighs what its leaves do', () {
      expect(packages["path_provider_foundation"]!.bytes, 16 + 100 + 16 + 68);
    });

    test('dart libraries and symbol groups are not packages', () {
      expect(packages.keys, isNot(contains("core")));
      expect(packages, hasLength(3));
    });
  });

  test('a package reached by any merged snapshot is reached', () {
    final merged = helper.merge([
      {
        "ads": const PackageCode(bytes: 300, functions: []),
        "url": const PackageCode(bytes: 900, functions: ["launch"]),
      },
      {
        "ads": const PackageCode(bytes: 4000, functions: ["load"]),
        "url": const PackageCode(bytes: 900, functions: ["launch"]),
      },
    ]);

    expect(merged["ads"]!.isReachable, isTrue);
    expect(merged["ads"]!.bytes, 4000);
    expect(merged["url"]!.functions, ["launch"]);
  });

  test('a summary without a Dart AOT snapshot yields nothing', () {
    expect(helper.packagesIn(node("Root", [leaf("Runner", 10)])), isNull);
  });

  test('the summary path is read from the build output', () {
    expect(
      helper.summaryPathIn(
        "A summary of your iOS bundle analysis can be found at: "
        "/Users/me/.flutter-devtools/ios-code-size-analysis_03.json",
      ),
      "/Users/me/.flutter-devtools/ios-code-size-analysis_03.json",
    );
    expect(
      helper.summaryPathIn(
        "A summary of your APK analysis can be found at: /tmp/apk-code-size-analysis_01.json",
      ),
      "/tmp/apk-code-size-analysis_01.json",
    );
    expect(helper.summaryPathIn("Built build/ios/iphoneos/Runner.app"), isNull);
  });

  group('analysisParameters', () {
    test('flags the analysis cannot take are left out with their values', () {
      expect(
        helper.analysisParameters([
          "--no-tree-shake-icons",
          "--obfuscate",
          "--split-debug-info=build/symbols",
          "--target-platform",
          "android-arm,android-arm64",
          "--export-method=app-store",
          "--dart-define=FLAVOR=prod",
        ]),
        ["--no-tree-shake-icons", "--dart-define=FLAVOR=prod"],
      );
    });

    test('a value flag followed by another flag only drops itself', () {
      expect(
        helper.analysisParameters(["--split-debug-info", "--flavor", "prod"]),
        ["--flavor", "prod"],
      );
    });
  });
}
