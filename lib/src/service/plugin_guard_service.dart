import 'dart:convert';
import 'dart:io';

import 'package:uploader/src/config/uploader_config.dart';
import 'package:uploader/src/constants/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/code_size_helper.dart';
import 'package:uploader/src/helper/native_import_helper.dart';
import 'package:uploader/src/helper/plugin_allowlist_helper.dart';
import 'package:uploader/src/helper/plugin_audit_helper.dart';
import 'package:uploader/src/helper/plugin_stub_helper.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/util/printer.dart';

/// What the code size analysis builds found, before any stub was applied.
class PluginAnalysis {
  /// The Dart code each analysed platform kept, by package.
  final Map<String, Map<String, PackageCode>> codeByPlatform;

  /// The unused plugins `pluginStubs.auto` stubs and the platform each one is
  /// stubbed on.
  final Map<String, AppPlatform> autoStubs;

  const PluginAnalysis({
    this.codeByPlatform = const {},
    this.autoStubs = const {},
  });
}

/// Checks the plugins a run is about to build before anything is built.
///
/// [analyse] runs a code size analysis build per platform on the project as
/// it is, which finds the plugins no Dart code reaches; stubbing a plugin
/// changes none of its Dart code, so the verdict still holds once the stubs
/// are in. [check] then stops the run for a plugin registered without being
/// in `allowedPluginsPath`, or for a stubbed plugin some Dart code still
/// reaches, which would throw `MissingPluginException` for the user instead
/// of failing here.
class PluginGuardService {
  final UploaderConfig config;
  final ProcessService processService;

  /// The Flutter project the run builds.
  final String projectRoot;

  final allowlistHelper = PluginAllowlistHelper();
  final auditHelper = PluginAuditHelper();
  final codeSizeHelper = CodeSizeHelper();
  final nativeImportHelper = NativeImportHelper();
  final stubHelper = PluginStubHelper();

  bool _hasResolved = false;

  PluginGuardService({
    required this.config,
    required this.processService,
    String? projectRoot,
  }) : projectRoot = projectRoot ?? Directory.current.path;

  bool get _dryRun => config.isDryRun;

  bool get _stubsAutomatically => config.pluginStubs.auto;

  List<String> get _builtPlatformKeys => [
    if (config.platform.availableOnAndroid) AppPlatform.android.value,
    if (config.platform.availableOnIos) AppPlatform.ios.value,
  ];

  /// The platforms an analysis build runs for: every built one for an audit
  /// or automatic stubs, otherwise those a configured stub strips.
  List<String> get _analysedPlatformKeys {
    if (config.isAudit || _stubsAutomatically) return _builtPlatformKeys;
    if (!config.verifyPluginStubs) return const [];

    final stripped = config.pluginStubs.strippedPlatforms.values.expand(
      (platform) => switch (platform) {
        AppPlatform.all => builtPlatformKeys,
        _ => [platform.value],
      },
    );
    return _builtPlatformKeys.where(stripped.contains).toList();
  }

  /// Runs the analysis builds. Null when one of them failed.
  Future<PluginAnalysis?> analyse() async {
    final analysedPlatformKeys = _analysedPlatformKeys;
    if (analysedPlatformKeys.isEmpty) return const PluginAnalysis();

    if (!_dryRun) {
      Printer.info("[guard] resolving dependencies...");
      if (!await processService.pubGet()) {
        Printer.error("[guard] flutter pub get failed");
        return null;
      }
      _hasResolved = true;
      if (!_checkConfiguredPackages()) return null;
    }

    final pluginsDependencies = _readJson(
      PathConstants.flutterPluginsDependenciesRelativePath,
    );
    final codeByPlatform = <String, Map<String, PackageCode>>{};
    final unusedByPlatform = <String, List<String>>{};

    for (final platformKey in analysedPlatformKeys) {
      final code = await _analyse(platformKey);
      if (code == null) return null;
      if (_dryRun) continue;

      codeByPlatform[platformKey] = code;
      unusedByPlatform[platformKey] = _report(
        platformKey,
        pluginsDependencies: pluginsDependencies,
        code: code,
      );
    }

    if (_dryRun && _stubsAutomatically) {
      Printer.info(
        "[guard] DRY RUN: the plugins the analysis finds unused would be "
        "stubbed",
      );
    }
    return PluginAnalysis(
      codeByPlatform: codeByPlatform,
      autoStubs: _stubsAutomatically
          ? _autoStubsFrom(unusedByPlatform)
          : const {},
    );
  }

  /// A package the config names but the app does not depend on would only
  /// stop the run once the stubs are applied, after the analysis builds.
  bool _checkConfiguredPackages() {
    final packageConfig = _readJson(PathConstants.packageConfigRelativePath);
    if (packageConfig == null) return true;

    final packageConfigUri = _file(
      PathConstants.packageConfigRelativePath,
    ).absolute.uri;
    final missing = config.pluginStubs.packageNames
        .where(
          (name) =>
              stubHelper.packageRoot(
                packageConfig: packageConfig,
                packageConfigUri: packageConfigUri,
                name: name,
              ) ==
              null,
        )
        .toList();
    if (missing.isEmpty) return true;

    return Printer.error(
      "[guard] these packages are listed in pluginStubs, prunedAssets or "
      "prunedFonts but are not dependencies of this app: "
      "${missing.join(", ")}. Check their names in pubspec.lock",
    );
  }

  /// [stubs] are the stubs the project currently resolves to.
  Future<bool> check({
    required List<PluginStubPlan> stubs,
    required PluginAnalysis analysis,
  }) async {
    if (!_checkReachability(stubs: stubs, analysis: analysis)) return false;
    if (config.allowedPluginsPath == null) return true;

    if (stubs.isEmpty && !_hasResolved && !_dryRun) {
      Printer.info("[guard] resolving dependencies...");
      if (!await processService.pubGet()) {
        return Printer.error("[guard] flutter pub get failed");
      }
    }

    return _checkAllowlist(
      _readJson(PathConstants.flutterPluginsDependenciesRelativePath),
    );
  }

  bool _checkReachability({
    required List<PluginStubPlan> stubs,
    required PluginAnalysis analysis,
  }) {
    for (final MapEntry(key: platformKey, value: code)
        in analysis.codeByPlatform.entries) {
      final reachedStubs = stubs
          .where(
            (stub) =>
                stub.removesNativeCode &&
                stub.strippedPlatformKeys.contains(platformKey) &&
                (code[stub.name]?.isReachable ?? false),
          )
          .map(
            (stub) =>
                "${stub.name} "
                "(${code[stub.name]!.functions.take(5).join(", ")})",
          )
          .toList();
      if (reachedStubs.isNotEmpty) {
        return Printer.error(
          "[guard] Dart code on $platformKey still reaches these stubbed "
          "plugins, so calling them would throw MissingPluginException:\n"
          "${reachedStubs.join("\n")}\n"
          "Remove them from pluginStubs",
        );
      }

      final hasStubs = stubs.any(
        (stub) =>
            stub.removesNativeCode &&
            stub.strippedPlatformKeys.contains(platformKey),
      );
      if (hasStubs) {
        Printer.success(
          "[guard] no Dart code on $platformKey reaches a stubbed plugin",
        );
      }
    }
    return true;
  }

  bool _checkAllowlist(Map<dynamic, dynamic>? pluginsDependencies) {
    final allowedPluginsPath = config.allowedPluginsPath;
    if (allowedPluginsPath == null) return true;

    final registered = allowlistHelper.registeredPlugins(
      pluginsDependencies: pluginsDependencies,
      platformKeys: _builtPlatformKeys,
    );
    final file = _file(allowedPluginsPath);
    final allowed = file.existsSync()
        ? allowlistHelper.decode(file.readAsStringSync())
        : <String, List<String>>{};

    final unexpected = allowlistHelper.unexpected(
      allowed: allowed,
      registered: registered,
    );
    if (unexpected.isNotEmpty) {
      return Printer.error(
        "[guard] plugins registered without being in $allowedPluginsPath:\n"
        "${_formatByPlatform(unexpected)}\n"
        "A dependency brought in new native code. Stub it with pluginStubs, "
        "or add it to $allowedPluginsPath if it is wanted",
      );
    }

    final unregistered = allowlistHelper.unregistered(
      allowed: allowed,
      registered: registered,
    );
    if (unregistered.isNotEmpty) {
      Printer.info(
        "[guard] allowed plugins no longer registered, which "
        "$allowedPluginsPath can drop:\n${_formatByPlatform(unregistered)}",
      );
    }

    final unrecorded = allowlistHelper.unrecordedPlatforms(
      allowed: allowed,
      registered: registered,
    );
    if (unrecorded.isEmpty) {
      return Printer.success(
        "[guard] every registered plugin is in $allowedPluginsPath",
      );
    }

    if (_dryRun) {
      Printer.info(
        "[guard] DRY RUN: $allowedPluginsPath would record the plugins of "
        "${unrecorded.join(", ")}",
      );
      return true;
    }
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(
        allowlistHelper.encode({
          ...allowed,
          for (final key in unrecorded) key: registered[key]!,
        }),
      );
    Printer.warning(
      "[guard] $allowedPluginsPath had no list for ${unrecorded.join(", ")}, "
      "so the plugins registered now were recorded. Commit the file so the "
      "next run is checked against it",
    );
    return true;
  }

  /// The analysis parameters of every built target, once per distinct list.
  /// A `--dart-define` only one target sets can make that target's binary
  /// call a plugin the other one never does.
  List<List<String>> get _analysisParameterSets {
    final sets = <String, List<String>>{};
    for (final target in config.builtTargets) {
      final parameters = codeSizeHelper.analysisParameters(
        config.buildParametersFor(target),
      );
      sets.putIfAbsent(parameters.join("\u0000"), () => parameters);
    }
    return sets.values.toList();
  }

  /// The Dart code the analysis builds of [platformKey] kept together, empty
  /// in a dry run and null when a build failed.
  Future<Map<String, PackageCode>?> _analyse(String platformKey) async {
    final snapshots = <Map<String, PackageCode>>[];
    for (final parameters in _analysisParameterSets) {
      final code = await _analyseWith(platformKey, parameters: parameters);
      if (code == null) return null;
      snapshots.add(code);
    }
    return codeSizeHelper.merge(snapshots);
  }

  Future<Map<String, PackageCode>?> _analyseWith(
    String platformKey, {
    required List<String> parameters,
  }) async {
    final platform = AppPlatform.values.byName(platformKey);
    Printer.info(
      "[guard] building $platformKey for code size analysis"
      "${parameters.isEmpty ? "" : " with ${parameters.join(" ")}"}...",
    );

    final summaryPath = await processService.buildForCodeSize(
      platform: platform,
      codeSizeDirectory: PathConstants.codeSizeRelativePath(platformKey),
      extraBuildParameters: parameters,
    );
    if (_dryRun) return const {};
    if (summaryPath == null) {
      Printer.error(
        "[guard] the code size analysis build for $platformKey failed",
      );
      return null;
    }

    final summary = jsonDecode(File(summaryPath).readAsStringSync());
    final code = summary is Map ? codeSizeHelper.packagesIn(summary) : null;
    if (code == null) {
      Printer.error("[guard] $summaryPath has no Dart AOT snapshot to analyse");
    }
    return code;
  }

  /// Prints the audit of [platformKey] and returns the plugins that can be
  /// stubbed there. Plugins the config already stubs are left out.
  List<String> _report(
    String platformKey, {
    required Map<dynamic, dynamic>? pluginsDependencies,
    required Map<String, PackageCode> code,
  }) {
    final plugins = _maps(pluginsDependencies?["plugins"]?[platformKey]);
    final dependencyGraph = _maps(pluginsDependencies?["dependencyGraph"]);
    final entries = auditHelper.audit(
      plugins: plugins,
      dependencyGraph: dependencyGraph,
      code: code,
      usedByApp: nativeImportHelper.importedPlugins(
        platformKey: platformKey,
        plugins: plugins,
        sources: nativeImportHelper.appSources(
          projectRoot: projectRoot,
          platformKey: platformKey,
        ),
      ),
      kept: config.pluginStubs.keep.toSet(),
    );

    final configured = config.pluginStubs.strippedPlatforms.keys.toSet();
    final unused = auditHelper
        .suggestedStubs(
          platformKey: platformKey,
          entries: entries,
          plugins: plugins,
          dependencyGraph: dependencyGraph,
        )
        .where((name) => !configured.contains(name))
        .toList();
    Printer.info(
      auditHelper.formatReport(
        platformKey: platformKey,
        entries: entries,
        suggestedStubs: unused,
        stubsAutomatically: _stubsAutomatically,
      ),
    );
    return unused;
  }

  /// A plugin unused on every built platform is stubbed on all of them.
  Map<String, AppPlatform> _autoStubsFrom(
    Map<String, List<String>> unusedByPlatform,
  ) {
    final autoStubs = <String, AppPlatform>{};
    for (final MapEntry(key: platformKey, value: names)
        in unusedByPlatform.entries) {
      final platform = AppPlatform.values.byName(platformKey);
      for (final name in names) {
        autoStubs[name] = autoStubs.containsKey(name)
            ? AppPlatform.all
            : platform;
      }
    }
    return autoStubs;
  }

  List<Map<dynamic, dynamic>> _maps(dynamic list) =>
      list is List ? list.whereType<Map>().toList() : const [];

  String _formatByPlatform(Map<String, List<String>> names) => names.entries
      .map((entry) => "${entry.key}: ${entry.value.join(", ")}")
      .join("\n");

  Map<dynamic, dynamic>? _readJson(String relativePath) {
    final file = _file(relativePath);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  File _file(String relativePath) => File("$projectRoot/$relativePath");
}
