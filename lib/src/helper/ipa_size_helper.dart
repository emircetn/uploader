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

class IpaSizeEntry {
  final String name;
  final int bytes;

  const IpaSizeEntry({required this.name, required this.bytes});

  double get sizeInMb => bytes / _bytesPerMb;
}

class IpaSizeReport {
  final int payloadBytes;
  final List<IpaSizeEntry> largestEntries;

  const IpaSizeReport({
    required this.payloadBytes,
    required this.largestEntries,
  });

  double get payloadSizeInMb => payloadBytes / _bytesPerMb;

  double get overLimitMb => payloadSizeInMb - appStoreSizeLimitMb;

  double get remainingMb => appStoreSizeLimitMb - payloadSizeInMb;

  bool get exceedsLimit => payloadSizeInMb > appStoreSizeLimitMb;

  bool get isCloseToLimit =>
      payloadSizeInMb > appStoreSizeLimitMb - appStoreSizeWarningMarginMb;
}

class IpaSizeHelper {
  /// Returns null when the size cannot be established: no archive on disk
  /// (a dry run never produces one), no `unzip`, or nothing under `Payload/`.
  Future<IpaSizeReport?> inspect(String ipaPath) async {
    if (!File(ipaPath).existsSync()) return null;

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

    for (final line in listing.split("\n")) {
      final match = _listingEntry.firstMatch(line);
      if (match == null) continue;

      final bytes = int.tryParse(match.group(1)!);
      final path = match.group(4)!;
      if (bytes == null || bytes == 0) continue;
      if (!path.startsWith(_payloadPrefix)) continue;

      payloadBytes += bytes;
      final group = _groupFor(path);
      groups[group] = (groups[group] ?? 0) + bytes;
    }

    if (payloadBytes == 0) return null;

    final entries = groups.entries.map(_toEntry).toList()..sort(_byBytesDesc);

    return IpaSizeReport(
      payloadBytes: payloadBytes,
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
