import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/archived_build.dart';

class UploadOutcome {
  final UploadStatus status;
  final String? message;

  const UploadOutcome._(this.status, this.message);

  const UploadOutcome.done([String? message])
    : this._(UploadStatus.done, message);

  /// Failed, or could not run yet; `--upload-symbols` tries it again.
  const UploadOutcome.pending(String message)
    : this._(UploadStatus.pending, message);

  /// Nothing for this destination to send for this build, and a retry would
  /// not change that.
  const UploadOutcome.skipped(String message)
    : this._(UploadStatus.skipped, message);
}

/// A crash reporter an archived build's symbols are sent to. Each upload
/// reads from the archive, never from `build/`, so it can be repeated for an
/// earlier build at any time.
abstract class SymbolDestination {
  /// The key the outcome is recorded under in the manifest.
  String get name;

  bool supports(AppPlatform platform);

  /// The archived kinds [upload] reads through [ArchivedBuild.pathOf]; only
  /// these are extracted for it.
  Set<SymbolKind> kindsNeeded(ArchivedBuild build);

  Future<UploadOutcome> upload(ArchivedBuild build);
}
