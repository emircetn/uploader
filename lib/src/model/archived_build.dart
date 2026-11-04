import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:uploader/src/enum/enums.dart';

/// A kind of file a build leaves behind that a crash reporter needs.
enum SymbolKind {
  /// R8/ProGuard `mapping.txt`.
  mapping(value: "mapping", archivedName: "mapping.txt"),

  /// The Android resource Crashlytics generates to name the mapping file.
  crashlyticsMappingId(
    value: "crashlyticsMappingId",
    archivedName: "crashlytics_mapping_file_id.xml",
  ),

  /// Unstripped `.so` files, one folder per ABI.
  nativeLibs(value: "nativeLibs", archivedName: "native-libs"),

  /// What `--split-debug-info` writes.
  dartSymbols(value: "dartSymbols", archivedName: "dart-symbols"),

  /// The archive's `dSYMs` folder.
  dsyms(value: "dsyms", archivedName: "dSYMs");

  final String value;
  final String archivedName;

  const SymbolKind({required this.value, required this.archivedName});

  /// Each kind is archived in a zip of its own.
  String get zipName => "$archivedName.zip";

  bool get isFolder => switch (this) {
    mapping || crashlyticsMappingId => false,
    nativeLibs || dartSymbols || dsyms => true,
  };
}

enum UploadStatus {
  done(value: "done"),
  pending(value: "pending"),
  skipped(value: "skipped");

  final String value;

  const UploadStatus({required this.value});
}

class UploadRecord {
  final UploadStatus status;
  final String? message;
  final DateTime at;

  const UploadRecord({required this.status, required this.at, this.message});

  Map<String, dynamic> toJson() => {
    "status": status.value,
    "at": at.toIso8601String(),
    if (message != null) "message": message,
  };

  static UploadRecord? fromJson(dynamic json) {
    if (json is! Map) return null;
    final status = UploadStatus.values.firstWhereOrNull(
      (status) => status.value == json["status"],
    );
    if (status == null) return null;
    return UploadRecord(
      status: status,
      at: DateTime.tryParse("${json["at"]}") ?? DateTime(0),
      message: json["message"] as String?,
    );
  }
}

/// One build's symbols as they sit in the archive, read from and written to
/// its `manifest.json`.
class ArchivedBuild {
  static const String manifestName = "manifest.json";

  final Directory directory;

  final String appName;
  final String version;
  final String? buildNumber;
  final AppPlatform platform;
  final BuildTarget target;
  final DateTime createdAt;
  final String? gitCommit;

  /// Firebase app id this build reports to, kept so a later retry does not
  /// depend on the project still being in the same state. Filled in on a
  /// retry when the build could not read it.
  String? firebaseAppId;

  /// The id the New Relic Gradle plugin compiled into the build. New Relic
  /// only matches a mapping file tagged with it.
  final String? newRelicBuildId;

  /// Archived zips by kind, relative to [directory]. Unstripped native
  /// libraries and dSYMs shrink to about a third.
  final Map<SymbolKind, String> files;

  /// Where the zips are extracted while the build is uploaded; null
  /// otherwise. [pathOf] points into it.
  Directory? contentDirectory;

  /// The kinds extracted into [contentDirectory].
  Set<SymbolKind> extractedKinds = const {};

  /// The archived zip of [kind], or null when the build did not produce it.
  String? zipOf(SymbolKind kind) {
    final zip = files[kind];
    return zip == null ? null : "${directory.path}/$zip";
  }

  /// Upload outcome by destination name.
  final Map<String, UploadRecord> uploads;

  ArchivedBuild({
    required this.directory,
    required this.appName,
    required this.version,
    required this.platform,
    required this.target,
    required this.createdAt,
    required this.files,
    this.buildNumber,
    this.gitCommit,
    this.firebaseAppId,
    this.newRelicBuildId,
    Map<String, UploadRecord>? uploads,
  }) : uploads = uploads ?? {};

  String get fullVersion => fullVersionOf(version, buildNumber);

  /// `1.4.0+87`, or `1.4.0` without a build number; also the name of the
  /// archive's version folder.
  static String fullVersionOf(String version, String? buildNumber) =>
      buildNumber == null ? version : "$version+$buildNumber";

  String get label => "${platform.value} ${target.name} $fullVersion";

  /// The path of an archived [kind] inside [contentDirectory], or null when
  /// the build did not produce it.
  String? pathOf(SymbolKind kind) {
    if (!files.containsKey(kind)) return null;
    final content = contentDirectory;
    if (content == null || !extractedKinds.contains(kind)) {
      throw StateError("${kind.value} of $label is not extracted");
    }
    return "${content.path}/${kind.archivedName}";
  }

  bool get hasPendingUploads =>
      uploads.values.any((record) => record.status == UploadStatus.pending);

  Iterable<String> get pendingDestinations => uploads.entries
      .where((entry) => entry.value.status == UploadStatus.pending)
      .map((entry) => entry.key);

  void record(String destination, UploadRecord record) {
    uploads[destination] = record;
  }

  Map<String, dynamic> toJson() => {
    "appName": appName,
    "version": version,
    if (buildNumber != null) "buildNumber": buildNumber,
    "platform": platform.value,
    "target": target.name,
    "createdAt": createdAt.toIso8601String(),
    if (gitCommit != null) "gitCommit": gitCommit,
    if (firebaseAppId != null) "firebaseAppId": firebaseAppId,
    if (newRelicBuildId != null) "newRelicBuildId": newRelicBuildId,
    "files": {
      for (final MapEntry(:key, :value) in files.entries) key.value: value,
    },
    "uploads": {
      for (final MapEntry(:key, :value) in uploads.entries) key: value.toJson(),
    },
  };

  void save() {
    File(
      "${directory.path}/$manifestName",
    ).writeAsStringSync(const JsonEncoder.withIndent("  ").convert(toJson()));
  }

  /// Reads the manifest in [directory], or null when there is none or it
  /// cannot be read.
  static ArchivedBuild? load(Directory directory) {
    final file = File("${directory.path}/$manifestName");
    if (!file.existsSync()) return null;

    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return null;

      final platform = AppPlatform.values.firstWhereOrNull(
        (platform) => platform.value == json["platform"],
      );
      final target = BuildTarget.values.firstWhereOrNull(
        (target) => target.name == json["target"],
      );
      if (platform == null || target == null) return null;

      final files = <SymbolKind, String>{};
      final filesJson = json["files"];
      if (filesJson is Map) {
        for (final MapEntry(:key, :value) in filesJson.entries) {
          final kind = SymbolKind.values.firstWhereOrNull(
            (kind) => kind.value == key,
          );
          if (kind != null && value is String) files[kind] = value;
        }
      }

      final uploads = <String, UploadRecord>{};
      final uploadsJson = json["uploads"];
      if (uploadsJson is Map) {
        for (final MapEntry(:key, :value) in uploadsJson.entries) {
          final record = UploadRecord.fromJson(value);
          if (record != null) uploads["$key"] = record;
        }
      }

      return ArchivedBuild(
        directory: directory,
        appName: "${json["appName"]}",
        version: "${json["version"]}",
        buildNumber: json["buildNumber"] as String?,
        platform: platform,
        target: target,
        createdAt: DateTime.tryParse("${json["createdAt"]}") ?? DateTime(0),
        gitCommit: json["gitCommit"] as String?,
        firebaseAppId: json["firebaseAppId"] as String?,
        newRelicBuildId: json["newRelicBuildId"] as String?,
        files: files,
        uploads: uploads,
      );
    } catch (_) {
      return null;
    }
  }
}
