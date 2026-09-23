import 'dart:io';

/// The App Store's over-the-air download limit.
///
/// Sizes in this file are decimal MB (bytes / 1e6). Reading them as MiB moves
/// the threshold by roughly 5%, which is enough to report a build that is over
/// the limit as if it were under it.
const int appStoreSizeLimitMb = 200;

/// How close to the limit a build may get before the run points it out, so a
/// warning still arrives while there is room to drop something.
const int appStoreSizeWarningMarginMb = 15;

const int _bytesPerMb = 1000000;
const int _largestEntryCount = 15;
const int _flutterAssetsDepth = 3;
const String _payloadPrefix = "Payload/";
const String _appMarker = ".app/";
const String _flutterAssets = "flutter_assets";

/// Paths are grouped at these components, because a framework or a resource
/// bundle is what gets added or removed as a unit.
const List<String> _bundleSuffixes = [
  ".framework",
  ".xcframework",
  ".bundle",
  ".appex",
  ".app",
];

final RegExp _listingEntry = RegExp(
  r"^\s*(\d+)\s+(\d+-\d+-\d+)\s+(\d+:\d+)\s+(.+)$",
);
final RegExp _listingTotals = RegExp(r"^\s*(\d+)\s+(\d+)\s+files?\s*$");

class IpaSizeEntry {
  final String name;
  final int bytes;

  const IpaSizeEntry({required this.name, required this.bytes});

  double get sizeInMb => bytes / _bytesPerMb;
}

class IpaSizeReport {
  final int payloadBytes;
  final int parsedBytes;
  final int parsedEntryCount;
  final int? listingBytes;
  final int? listingEntryCount;
  final List<IpaSizeEntry> largestEntries;

  const IpaSizeReport({
    required this.payloadBytes,
    required this.parsedBytes,
    required this.parsedEntryCount,
    required this.listingBytes,
    required this.listingEntryCount,
    required this.largestEntries,
  });

  double get payloadSizeInMb => payloadBytes / _bytesPerMb;

  double get overLimitMb => payloadSizeInMb - appStoreSizeLimitMb;

  double get remainingMb => appStoreSizeLimitMb - payloadSizeInMb;

  bool get exceedsLimit => payloadSizeInMb > appStoreSizeLimitMb;

  bool get isCloseToLimit =>
      payloadSizeInMb >= appStoreSizeLimitMb - appStoreSizeWarningMarginMb;

  /// `unzip -l` closes with a totals row. When the entries that could be read
  /// do not add up to it, the payload figure can only be too low, so being
  /// under the limit stops being a safe conclusion. An oversized build still
  /// reads as oversized, since the figure is a lower bound either way.
  bool get isListingComplete =>
      listingBytes == parsedBytes && listingEntryCount == parsedEntryCount;
}

class IpaSizeHelper {
  /// Returns null when the size cannot be established: no `unzip` on the
  /// `PATH`, a listing this parser does not recognise at all, or nothing under
  /// `Payload/`. Callers are expected to have checked that the archive exists,
  /// so that a dry run is not confused with a failed measurement.
  Future<IpaSizeReport?> inspect(String ipaPath) async {
    final ProcessResult listing;
    try {
      listing = await Process.run("unzip", ["-l", ipaPath]);
    } on ProcessException {
      return null;
    }

    if (listing.exitCode != 0) return null;

    return parsePayloadListing("${listing.stdout}");
  }

  /// Sums the uncompressed entries under `Payload/`, which is the installed
  /// app. `Signatures/` and `Symbols/` are listed in an IPA as well and are not
  /// shipped, so the whole archive reads much larger than the app.
  IpaSizeReport? parsePayloadListing(String listing) {
    final groups = <String, int>{};
    var payloadBytes = 0;
    var parsedBytes = 0;
    var parsedEntryCount = 0;
    int? listingBytes;
    int? listingEntryCount;

    for (final line in listing.split("\n")) {
      final totals = _listingTotals.firstMatch(line);
      if (totals != null) {
        listingBytes = int.tryParse(totals.group(1)!);
        listingEntryCount = int.tryParse(totals.group(2)!);
        continue;
      }

      final match = _listingEntry.firstMatch(line);
      if (match == null) continue;

      final bytes = int.tryParse(match.group(1)!);
      if (bytes == null) continue;

      parsedEntryCount++;
      parsedBytes += bytes;

      final path = match.group(4)!;
      if (bytes == 0 || !path.startsWith(_payloadPrefix)) continue;

      payloadBytes += bytes;
      final group = _groupFor(path);
      groups[group] = (groups[group] ?? 0) + bytes;
    }

    if (payloadBytes == 0) return null;

    final entries = groups.entries.map(_toEntry).toList()..sort(_byBytesDesc);

    return IpaSizeReport(
      payloadBytes: payloadBytes,
      parsedBytes: parsedBytes,
      parsedEntryCount: parsedEntryCount,
      listingBytes: listingBytes,
      listingEntryCount: listingEntryCount,
      largestEntries: entries.take(_largestEntryCount).toList(),
    );
  }

  String describeLargestEntries(IpaSizeReport report) =>
      report.largestEntries.map(_describeEntry).join("\n");

  String _describeEntry(IpaSizeEntry entry) =>
      "  ${entry.sizeInMb.toStringAsFixed(1).padLeft(7)} MB  ${entry.name}";

  IpaSizeEntry _toEntry(MapEntry<String, int> group) =>
      IpaSizeEntry(name: group.key, bytes: group.value);

  int _byBytesDesc(IpaSizeEntry a, IpaSizeEntry b) =>
      b.bytes.compareTo(a.bytes);

  String _groupFor(String payloadPath) {
    final appIndex = payloadPath.indexOf(_appMarker);
    final relative = appIndex == -1
        ? payloadPath.substring(_payloadPrefix.length)
        : payloadPath.substring(appIndex + _appMarker.length);

    final parts = relative.split("/");

    for (var i = 0; i < parts.length; i++) {
      if (!_isBundleComponent(parts[i])) continue;

      final bundle = parts.sublist(0, i + 1).join("/");
      final rest = parts.sublist(i + 1);

      // Flutter puts the assets inside App.framework, so stopping at the
      // bundle would report asset growth as the Dart snapshot growing.
      if (rest.isNotEmpty && rest.first == _flutterAssets) {
        return "$bundle/${_flutterAssetsGroup(rest)}";
      }
      return bundle;
    }

    if (parts.first == _flutterAssets) return _flutterAssetsGroup(parts);

    return relative;
  }

  String _flutterAssetsGroup(List<String> parts) {
    final depth = parts.length < _flutterAssetsDepth
        ? parts.length
        : _flutterAssetsDepth;
    return parts.sublist(0, depth).join("/");
  }

  bool _isBundleComponent(String component) =>
      _bundleSuffixes.any(component.endsWith);
}
