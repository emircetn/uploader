import 'package:test/test.dart';
import 'package:uploader/src/helper/ipa_size_helper.dart';

void main() {
  final helper = IpaSizeHelper();

  String entryLine(int bytes, String path, {String date = "09-22-2026"}) =>
      " $bytes  $date 17:22   $path";

  /// Builds a listing whose totals row matches its entries, the way real
  /// `unzip -l` output does. Tests that need a mismatch pass [totalBytes] or
  /// [entryCount], or drop the row with [withTotals].
  String listingOf(
    Map<String, int> entries, {
    int? totalBytes,
    int? entryCount,
    bool withTotals = true,
    String date = "09-22-2026",
  }) {
    final bytes =
        totalBytes ?? entries.values.fold<int>(0, (sum, value) => sum + value);
    final count = entryCount ?? entries.length;

    return [
      "Archive:  build/ios/ipa/Example.ipa",
      "  Length      Date    Time    Name",
      "---------  ---------- -----   ----",
      ...entries.entries.map((e) => entryLine(e.value, e.key, date: date)),
      if (withTotals) ...[
        "---------                     -------",
        "$bytes                     $count files",
      ],
    ].join("\n");
  }

  IpaSizeReport reportFor(String listing) {
    final report = helper.parsePayloadListing(listing);
    expect(report, isNotNull);
    return report!;
  }

  IpaSizeReport runnerReport(int bytes, {int? totalBytes}) => reportFor(
        listingOf(
          {"Payload/Runner.app/Runner": bytes},
          totalBytes: totalBytes,
        ),
      );

  int bytesOf(IpaSizeReport report, String name) =>
      report.largestEntries.firstWhere((entry) => entry.name == name).bytes;

  group('payload total', () {
    test('counts only the entries under Payload', () {
      final report = reportFor(
        listingOf({
          "Signatures/FBSDKCoreKit.xcframework-ios.signature": 6204,
          "Symbols/F44B7C7A.symbols": 6892,
          "Payload/Runner.app/Runner": 50000000,
        }),
      );

      expect(report.payloadBytes, 50000000);
    });

    test('reads sizes as decimal MB', () {
      final report = runnerReport(177929658);

      expect(report.payloadSizeInMb, closeTo(177.9, 0.05));
    });

    test('skips directory entries', () {
      final report = reportFor(
        listingOf({
          "Payload/": 0,
          "Payload/Runner.app/": 0,
          "Payload/Runner.app/Runner": 1000000,
        }),
      );

      expect(report.payloadBytes, 1000000);
      expect(report.largestEntries, hasLength(1));
    });

    test('never counts the totals row as an entry', () {
      final report = runnerReport(100000000);

      expect(report.parsedEntryCount, 1);
      expect(report.payloadBytes, 100000000);
    });

    test('returns null when nothing is listed under Payload', () {
      final listing = listingOf({"Symbols/F44B7C7A.symbols": 6892});

      expect(helper.parsePayloadListing(listing), isNull);
    });
  });

  group('grouping', () {
    test('groups a framework by its bundle', () {
      final report = reportFor(
        listingOf({
          "Payload/Runner.app/Frameworks/media_kit_libs_ios_video.framework"
              "/Harfbuzz": 20000000,
          "Payload/Runner.app/Frameworks/media_kit_libs_ios_video.framework"
              "/Info.plist": 1000000,
        }),
      );

      expect(
        bytesOf(report, "Frameworks/media_kit_libs_ios_video.framework"),
        21000000,
      );
    });

    test('groups a resource bundle by its bundle', () {
      final report = reportFor(
        listingOf({
          "Payload/Runner.app/GoogleMVFaceDetectorResources.bundle/model":
              9000000,
        }),
      );

      expect(bytesOf(report, "GoogleMVFaceDetectorResources.bundle"), 9000000);
    });

    test('keeps flutter assets out of the App.framework total', () {
      final report = reportFor(
        listingOf({
          "Payload/Runner.app/Frameworks/App.framework/App": 16000000,
          "Payload/Runner.app/Frameworks/App.framework/flutter_assets"
              "/assets/images/hero.webp": 10000000,
          "Payload/Runner.app/Frameworks/App.framework/flutter_assets"
              "/packages/some_package/assets/clip.mp4": 8000000,
        }),
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
        listingOf({
          "Payload/Runner.app/Small.bundle/a": 1000000,
          "Payload/Runner.app/Runner": 50000000,
          "Payload/Runner.app/Medium.bundle/a": 9000000,
        }),
      );

      expect(
        report.largestEntries.map((entry) => entry.name),
        ["Runner", "Medium.bundle", "Small.bundle"],
      );
    });
  });

  group('listing completeness', () {
    test('a listing whose totals match every entry read is complete', () {
      final report = runnerReport(100000000);

      expect(report.isListingComplete, isTrue);
      expect(report.parsedBytes, report.listingBytes);
      expect(report.parsedEntryCount, report.listingEntryCount);
    });

    test('a totals row larger than what was read is incomplete', () {
      final report = runnerReport(100000000, totalBytes: 305000000);

      expect(report.isListingComplete, isFalse);
      expect(
        report.exceedsLimit,
        isFalse,
        reason: "the figure is a lower bound, so the limit is unresolved "
            "rather than breached",
      );
    });

    test('a line this parser cannot read leaves the listing incomplete', () {
      // Without the totals row a 250 MB app would be reported as 1 MB, since
      // the oversized entry uses a date format the parser does not accept.
      final listing = [
        listingOf(
          {"Payload/Runner.app/Runner": 1000000},
          withTotals: false,
        ),
        entryLine(
          249000000,
          "Payload/Runner.app/Frameworks/Huge.framework/Huge",
          date: "2026/09/22",
        ),
        "---------                     -------",
        "250000000                     2 files",
      ].join("\n");

      final report = reportFor(listing);

      expect(report.payloadBytes, 1000000);
      expect(report.isListingComplete, isFalse);
    });

    test('a listing with no totals row cannot be confirmed complete', () {
      final report = reportFor(
        listingOf(
          {"Payload/Runner.app/Runner": 100000000},
          withTotals: false,
        ),
      );

      expect(report.listingBytes, isNull);
      expect(report.isListingComplete, isFalse);
    });
  });

  group('limits', () {
    test('flags a payload over the limit', () {
      final report = runnerReport(203800000);

      expect(report.exceedsLimit, isTrue);
      expect(report.isCloseToLimit, isTrue);
      expect(report.overLimitMb, closeTo(3.8, 0.05));
    });

    test('flags a payload inside the warning margin', () {
      final report = runnerReport(190000000);

      expect(report.exceedsLimit, isFalse);
      expect(report.isCloseToLimit, isTrue);
      expect(report.remainingMb, closeTo(10, 0.05));
    });

    test('flags a payload exactly at the warning margin', () {
      final report = runnerReport(185000000);

      expect(report.payloadSizeInMb, 185.0);
      expect(report.isCloseToLimit, isTrue);
      expect(report.exceedsLimit, isFalse);
    });

    test('treats exactly the limit as not yet exceeded', () {
      final report = runnerReport(200000000);

      expect(report.payloadSizeInMb, 200.0);
      expect(report.exceedsLimit, isFalse);
      expect(report.isCloseToLimit, isTrue);
    });

    test('stays quiet for a payload below the warning margin', () {
      final report = runnerReport(100000000);

      expect(report.exceedsLimit, isFalse);
      expect(report.isCloseToLimit, isFalse);
    });
  });

  test('inspect returns null when there is no readable archive', () async {
    expect(await helper.inspect("does/not/exist.ipa"), isNull);
  });
}
