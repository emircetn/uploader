import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/util/path_utils.dart';

/// Where New Relic receives mapping files and dSYMs.
enum NewRelicRegion {
  us(value: "us", host: "mobile-symbol-upload.newrelic.com"),
  eu(value: "eu", host: "mobile-symbol-upload.eu.nr-data.net"),
  jp(value: "jp", host: "mobile-symbol-upload.jp.nr-data.net");

  final String value;
  final String host;

  const NewRelicRegion({required this.value, required this.host});

  Uri get symbolUri => Uri.https(host, "/symbol");
}

/// Where a token is read from, written out in `pubspec.yaml` so a reader
/// can see which data an upload uses. Either an environment variable, or a
/// key in a file of `KEY=value` lines or a JSON object, such as `.env`, a
/// `--dart-define-from-file` JSON or `newrelic.properties`.
class TokenSource {
  final String? env;
  final String? file;
  final String? key;

  const TokenSource.env(String this.env) : file = null, key = null;

  const TokenSource.file({required String this.file, required String this.key})
    : env = null;

  String get description =>
      env != null ? "environment variable $env" : "$key in $file";
}

class NewRelicSymbolsConfig {
  final NewRelicRegion region;

  /// The application token for each platform. A platform without one is not
  /// uploaded to New Relic.
  final TokenSource? androidToken;
  final TokenSource? iosToken;

  const NewRelicSymbolsConfig({
    this.region = NewRelicRegion.us,
    this.androidToken,
    this.iosToken,
  });

  TokenSource? tokenFor(AppPlatform platform) => switch (platform) {
    AppPlatform.android => androidToken,
    AppPlatform.ios => iosToken,
    AppPlatform.all => null,
  };

  String get platforms => [
    if (androidToken != null) "android",
    if (iosToken != null) "ios",
  ].join(", ");
}

/// A shell command run for every archived build of [platform], with the
/// archived files substituted for placeholders such as `{mapping}`.
class SymbolCommand {
  final String name;
  final AppPlatform platform;
  final String run;

  const SymbolCommand({
    required this.name,
    required this.run,
    this.platform = AppPlatform.all,
  });
}

class SymbolsConfig {
  static const String defaultArchivePath = "~/.uploader/archive";
  static const int defaultKeepLast = 10;

  /// Where each build's symbols are copied. Outside the project by default,
  /// so `flutter clean` cannot take them.
  final String archivePath;

  /// How many runs are kept per app. A run with an upload still pending is
  /// never removed. Zero or less keeps every run.
  final int keepLast;

  /// Whether a symbol upload that still fails after its retries fails the
  /// run. Off by default: the build has already been archived, and the
  /// upload can be repeated with `--upload-symbols`.
  final bool failOnUploadError;

  final bool crashlytics;
  final NewRelicSymbolsConfig? newRelic;
  final List<SymbolCommand> commands;

  const SymbolsConfig({
    this.archivePath = defaultArchivePath,
    this.keepLast = defaultKeepLast,
    this.failOnUploadError = false,
    this.crashlytics = false,
    this.newRelic,
    this.commands = const [],
  });

  /// [archivePath] with a leading `~` expanded and a relative path resolved
  /// against [projectRoot].
  String resolveArchivePath({
    required String projectRoot,
    required Map<String, String> environment,
  }) {
    final path = PathUtils.resolve(
      archivePath,
      projectRoot: projectRoot,
      environment: environment,
    );
    return path.endsWith("/") ? path.substring(0, path.length - 1) : path;
  }

  List<String> get destinationNames => [
    if (crashlytics) "crashlytics",
    if (newRelic case final newRelic?)
      "newRelic (${newRelic.platforms}, ${newRelic.region.value})",
    for (final command in commands) command.name,
  ];
}
