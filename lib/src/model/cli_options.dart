class CliOptions {
  final bool skipConfirmation;

  final bool dryRun;

  /// Report which plugins the Dart code can still reach instead of building
  /// and uploading anything.
  final bool audit;

  const CliOptions({
    this.skipConfirmation = false,
    this.dryRun = false,
    this.audit = false,
  });
}
