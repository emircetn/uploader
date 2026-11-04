import 'dart:io';

import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/archived_build.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/service/symbol/symbol_destination.dart';
import 'package:uploader/src/util/retry_utils.dart';

/// Sends symbols to Firebase Crashlytics: the mapping file and native and
/// Dart symbols through the Firebase CLI, which App Distribution already
/// needs, and dSYMs through the `upload-symbols` tool the Crashlytics pod
/// ships.
class CrashlyticsDestination implements SymbolDestination {
  final ProcessService processService;
  final String projectRoot;
  final int retryCount;

  CrashlyticsDestination({
    required this.processService,
    required this.projectRoot,
    required this.retryCount,
  });

  static const uploadSymbolsRelativePath =
      "ios/Pods/FirebaseCrashlytics/upload-symbols";

  @override
  String get name => "crashlytics";

  @override
  bool supports(AppPlatform platform) => true;

  /// Dart symbols go up for Android only: on iOS Crashlytics reads them
  /// from the dSYMs.
  @override
  Set<SymbolKind> kindsNeeded(ArchivedBuild build) => {
    if (build.platform == AppPlatform.ios)
      SymbolKind.dsyms
    else ...[
      SymbolKind.mapping,
      SymbolKind.crashlyticsMappingId,
      SymbolKind.nativeLibs,
      SymbolKind.dartSymbols,
    ],
  }.where(build.files.containsKey).toSet();

  @override
  Future<UploadOutcome> upload(ArchivedBuild build) async {
    final platform = build.platform;
    final steps = <String, Future<bool> Function()>{};

    // Problems a retry can fix leave the upload pending; notes are about
    // files that will never be uploadable and do not hold it back.
    final problems = <String>[];
    final notes = <String>[];

    String appId() => build.firebaseAppId!;

    if (platform == AppPlatform.ios) {
      final dsyms = build.pathOf(SymbolKind.dsyms);
      if (dsyms != null) {
        final tool = "$projectRoot/$uploadSymbolsRelativePath";
        if (File(tool).existsSync()) {
          steps["dSYMs"] = () => processService.run(
            platform: platform,
            executable: tool,
            arguments: ["-ai", appId(), "-p", "ios", dsyms],
          );
        } else if (File("$projectRoot/ios/Podfile").existsSync()) {
          problems.add(
            "$uploadSymbolsRelativePath not found; run `pod install` in ios/",
          );
        } else {
          notes.add(
            "dSYMs not uploaded: without CocoaPods the project has no "
            "$uploadSymbolsRelativePath",
          );
        }
      }
    } else {
      final mapping = build.pathOf(SymbolKind.mapping);
      final mappingId = build.pathOf(SymbolKind.crashlyticsMappingId);
      if (mapping != null && mappingId == null) {
        notes.add(
          "mapping.txt not uploaded: the build left no Crashlytics mapping "
          "file id; is the Crashlytics Gradle plugin applied?",
        );
      } else if (mapping != null) {
        steps["mapping file"] = () => processService.run(
          platform: platform,
          executable: "firebase",
          arguments: [
            "crashlytics:mappingfile:upload",
            "--app=${appId()}",
            "--resource-file=$mappingId",
            mapping,
          ],
        );
      }

      for (final (label, kind) in [
        ("native symbols", SymbolKind.nativeLibs),
        ("Dart symbols", SymbolKind.dartSymbols),
      ]) {
        final path = build.pathOf(kind);
        if (path == null) continue;
        steps[label] = () => processService.run(
          platform: platform,
          executable: "firebase",
          arguments: ["crashlytics:symbols:upload", "--app=${appId()}", path],
        );
      }
    }

    if (steps.isEmpty && problems.isEmpty) {
      return UploadOutcome.skipped(
        notes.isEmpty
            ? "no symbols for Crashlytics in this build"
            : notes.join("; "),
      );
    }

    if (build.firebaseAppId == null) {
      return UploadOutcome.pending(
        "the Firebase app id could not be read from "
        "${platform == AppPlatform.ios ? "ios/Runner/GoogleService-Info.plist" : "android/app/google-services.json"}",
      );
    }

    for (final MapEntry(key: label, value: step) in steps.entries) {
      final isSuccess = await RetryUtils.run(
        step,
        retryCount: retryCount,
        label: "[${platform.value}] crashlytics $label upload",
      );
      if (!isSuccess) problems.add("$label upload failed");
    }

    if (problems.isNotEmpty) {
      return UploadOutcome.pending([...problems, ...notes].join("; "));
    }
    return UploadOutcome.done([steps.keys.join(", "), ...notes].join("; "));
  }
}
