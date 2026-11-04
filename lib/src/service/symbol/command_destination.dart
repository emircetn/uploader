import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/model/archived_build.dart';
import 'package:uploader/src/model/symbols_config.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/service/symbol/symbol_destination.dart';
import 'package:uploader/src/util/retry_utils.dart';

/// Runs a configured shell command for each archived build, for a crash
/// reporter the tool does not know, such as `sentry-cli`.
///
/// Placeholders: `{mapping}`, `{crashlyticsMappingId}`, `{nativeLibs}`,
/// `{dartSymbols}`, `{dsyms}` for the archived files, extracted for the
/// command, and `{dir}` (the build's archive folder), `{version}`,
/// `{buildNumber}`, `{platform}`, `{target}`, `{firebaseAppId}`. Values are
/// shell quoted. A command naming a file the build did not produce is
/// skipped.
class CommandDestination implements SymbolDestination {
  final SymbolCommand command;
  final ProcessService processService;
  final int retryCount;

  CommandDestination({
    required this.command,
    required this.processService,
    required this.retryCount,
  });

  static final _placeholder = RegExp(r"\{(\w+)\}");

  @override
  String get name => command.name;

  @override
  bool supports(AppPlatform platform) =>
      command.platform == AppPlatform.all || command.platform == platform;

  /// The archived kinds the command's placeholders name.
  @override
  Set<SymbolKind> kindsNeeded(ArchivedBuild build) {
    final names = {
      for (final match in _placeholder.allMatches(command.run)) match.group(1),
    };
    return {
      for (final kind in SymbolKind.values)
        if (names.contains(kind.value) && build.files.containsKey(kind)) kind,
    };
  }

  @override
  Future<UploadOutcome> upload(ArchivedBuild build) async {
    final rendered = render(command.run, build);
    if (rendered.missing.isNotEmpty) {
      return UploadOutcome.skipped(
        "this build has no ${rendered.missing.join(", ")}",
      );
    }

    final isSuccess = await RetryUtils.run(
      () => processService.run(
        platform: build.platform,
        executable: "sh",
        arguments: ["-c", rendered.command],
        workingDirectory: build.directory.path,
      ),
      retryCount: retryCount,
      label: "[${build.platform.value}] ${command.name}",
    );
    return isSuccess
        ? const UploadOutcome.done()
        : UploadOutcome.pending("`${command.name}` failed");
  }

  /// [template] with every placeholder replaced, and the placeholders the
  /// build has no value for.
  static ({String command, List<String> missing}) render(
    String template,
    ArchivedBuild build,
  ) {
    // Only placeholders the command names are read: a kind it does not
    // name was not extracted for it.
    final values = <String, String? Function()>{
      for (final kind in SymbolKind.values)
        kind.value: () => build.pathOf(kind),
      "dir": () => build.directory.path,
      "version": () => build.version,
      "buildNumber": () => build.buildNumber,
      "platform": () => build.platform.value,
      "target": () => build.target.name,
      "firebaseAppId": () => build.firebaseAppId,
    };

    final missing = <String>[];
    final command = template.replaceAllMapped(_placeholder, (match) {
      final key = match.group(1)!;
      if (!values.containsKey(key)) return match.group(0)!;
      final value = values[key]!();
      if (value == null) {
        missing.add(key);
        return "";
      }
      return shellQuote(value);
    });
    return (command: command, missing: missing);
  }

  static String shellQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";
}
