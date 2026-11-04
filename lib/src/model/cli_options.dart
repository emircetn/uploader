class CliOptions {
  final bool skipConfirmation;

  final bool dryRun;

  /// Report which plugins the Dart code can still reach instead of building
  /// and uploading anything.
  final bool audit;

  /// Upload the archived symbols whose upload is still pending instead of
  /// building anything.
  final bool uploadSymbols;

  const CliOptions({
    this.skipConfirmation = false,
    this.dryRun = false,
    this.audit = false,
    this.uploadSymbols = false,
  });
}
