import 'package:test/test.dart';
import 'package:uploader/src/helper/ipa_size_helper.dart';

void main() {
  final helper = IpaSizeHelper();

  IpaSizeReport reportFor(String listing) {
    final report = helper.parsePayloadListing(listing);
    expect(report, isNotNull);
    return report!;
  }

  String entryLine(int bytes, String path) =>
      " $bytes  09-22-2026 17:22   $path";

  String listingOf(List<String> entries) =>
      [
        "Archive:  build/ios/ipa/Example.ipa",
        "  Length      Date    Time    Name",
        "---------  ---------- -----   ----",
        ...entries,
        "---------                     -------",
        "123456789                     ${entries.length} files",
      ].join("\n");

  int bytesOf(IpaSizeReport report, String name) =>
      report.largestEntries.firstWhere((entry) => entry.name == name).bytes;

  test('counts only the entries under Payload', () {
    final report = reportFor(
      listingOf([
        entryLine(6204, "Signatures/FBSDKCoreKit.xcframework-ios.signature"),
        entryLine(6892, "Symbols/F44B7C7A.symbols"),
        entryLine(50000000, "Payload/Runner.app/Runner"),
      ]),
    );

    expect(report.payloadBytes, 50000000);
  });

  test('reads sizes as decimal MB', () {
    final report = reportFor(
      listingOf([entryLine(177929658, "Payload/Runner.app/Runner")]),
    );

    expect(report.payloadSizeInMb, closeTo(177.9, 0.05));
  });

  test('skips directory entries and the archive totals line', () {
    final report = reportFor(
      listingOf([
        entryLine(0, "Payload/"),
        entryLine(0, "Payload/Runner.app/"),
        entryLine(1000000, "Payload/Runner.app/Runner"),
      ]),
    );

    expect(report.payloadBytes, 1000000);
    expect(report.largestEntries, hasLength(1));
  });

  test('groups a framework by its bundle', () {
    final report = reportFor(
      listingOf([
        entryLine(
          20000000,
          "Payload/Runner.app/Frameworks/media_kit_libs_ios_video.framework"
              "/Harfbuzz",
        ),
        entryLine(
          1000000,
          "Payload/Runner.app/Frameworks/media_kit_libs_ios_video.framework"
              "/Info.plist",
        ),
      ]),
    );

    expect(
      bytesOf(report, "Frameworks/media_kit_libs_ios_video.framework"),
      21000000,
    );
  });

  test('groups a resource bundle by its bundle', () {
    final report = reportFor(
      listingOf([
        entryLine(
          9000000,
          "Payload/Runner.app/GoogleMVFaceDetectorResources.bundle/model",
        ),
      ]),
    );

    expect(bytesOf(report, "GoogleMVFaceDetectorResources.bundle"), 9000000);
  });

  test('keeps flutter assets out of the App.framework total', () {
    final report = reportFor(
      listingOf([
        entryLine(16000000, "Payload/Runner.app/Frameworks/App.framework/App"),
        entryLine(
          10000000,
          "Payload/Runner.app/Frameworks/App.framework/flutter_assets"
              "/assets/images/hero.webp",
        ),
        entryLine(
          8000000,
          "Payload/Runner.app/Frameworks/App.framework/flutter_assets"
              "/packages/some_package/assets/clip.mp4",
        ),
      ]),
    );

    expect(bytesOf(report, "Frameworks/App.framework"), 16000000);
    expect(
      bytesOf(
        report,
        "Frameworks/App.framework/flutter_assets/assets/images",
      ),
      10000000,
    );
    expect(
      bytesOf(
        report,
        "Frameworks/App.framework/flutter_assets/packages/some_package",
      ),
      8000000,
    );
  });

  test('orders the entries from largest to smallest', () {
    final report = reportFor(
      listingOf([
        entryLine(1000000, "Payload/Runner.app/Small.bundle/a"),
        entryLine(50000000, "Payload/Runner.app/Runner"),
        entryLine(9000000, "Payload/Runner.app/Medium.bundle/a"),
      ]),
    );

    expect(
      report.largestEntries.map((entry) => entry.name),
      ["Runner", "Medium.bundle", "Small.bundle"],
    );
  });

  test('returns null when nothing is listed under Payload', () {
    final listing = listingOf([entryLine(6892, "Symbols/F44B7C7A.symbols")]);

    expect(helper.parsePayloadListing(listing), isNull);
  });

  test('flags a payload over the limit', () {
    final report = reportFor(
      listingOf([entryLine(203800000, "Payload/Runner.app/Runner")]),
    );

    expect(report.exceedsLimit, isTrue);
    expect(report.isCloseToLimit, isTrue);
    expect(report.overLimitMb, closeTo(3.8, 0.05));
  });

  test('flags a payload inside the warning margin', () {
    final report = reportFor(
      listingOf([entryLine(190000000, "Payload/Runner.app/Runner")]),
    );

    expect(report.exceedsLimit, isFalse);
    expect(report.isCloseToLimit, isTrue);
    expect(report.remainingMb, closeTo(10, 0.05));
  });

  test('stays quiet for a payload below the warning margin', () {
    final report = reportFor(
      listingOf([entryLine(100000000, "Payload/Runner.app/Runner")]),
    );

    expect(report.exceedsLimit, isFalse);
    expect(report.isCloseToLimit, isFalse);
  });

  test('inspect returns null when the archive is missing', () async {
    expect(await helper.inspect("does/not/exist.ipa"), isNull);
  });
}
