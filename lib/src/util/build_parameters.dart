/// Reads values out of the `flutter build` parameters a run passes.
class BuildParameters {
  const BuildParameters._();

  /// The value of [option], written as `--option=value` or `--option value`;
  /// the last one wins, as it does for `flutter build`.
  static String? valueOf(List<String> parameters, String option) {
    String? value;
    for (var i = 0; i < parameters.length; i++) {
      final parameter = parameters[i];
      if (parameter.startsWith("$option=")) {
        value = parameter.substring(option.length + 1);
      } else if (parameter == option && i + 1 < parameters.length) {
        value = parameters[++i];
      }
    }
    return value == null || value.isEmpty ? null : value;
  }

  /// The version `--build-name` gives the build in place of `pubspec.yaml`'s.
  static String? buildName(List<String> parameters) =>
      valueOf(parameters, "--build-name");

  /// The build number `--build-number` gives the build in place of
  /// `pubspec.yaml`'s.
  static String? buildNumber(List<String> parameters) =>
      valueOf(parameters, "--build-number");

  /// The folder `--split-debug-info` writes Dart symbols to, if any.
  static String? splitDebugInfoPath(List<String> parameters) =>
      valueOf(parameters, "--split-debug-info");

  /// The Gradle variant a release build with these parameters produces:
  /// `release`, or `prodRelease` for `--flavor prod`.
  static String androidReleaseVariant(List<String> parameters) {
    final flavor = valueOf(parameters, "--flavor");
    return flavor == null ? "release" : "${flavor}Release";
  }
}

extension CapitalizedString on String {
  /// `prodRelease` → `ProdRelease`, as Gradle names a variant's tasks.
  String get capitalized =>
      isEmpty ? this : "${this[0].toUpperCase()}${substring(1)}";
}
