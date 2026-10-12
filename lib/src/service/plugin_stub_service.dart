import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:uploader/src/constants/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/plugin_stub_helper.dart';
import 'package:uploader/src/model/plugin_stub_config.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/util/printer.dart';
import 'package:uploader/src/util/string_utils.dart';
import 'package:yaml/yaml.dart';

/// Swaps the configured plugins for stubs before the builds and puts the
/// project back afterwards.
///
/// Nothing is committed and nothing outside the project changes: the stubs
/// live under `build/`, the swap is a generated `pubspec_overrides.yaml`, and
/// every file the stubbed resolve rewrites is backed up first.
class PluginStubService {
  final PluginStubConfig config;
  final ProcessService processService;
  final bool dryRun;

  /// The Flutter project the run builds.
  final String projectRoot;

  final helper = PluginStubHelper();

  PluginStubService({
    required this.config,
    required this.processService,
    this.dryRun = false,
    String? projectRoot,
  }) : projectRoot = projectRoot ?? Directory.current.path;

  static const _manifestName = "manifest.json";
  static const _interruptedExitCode = 130;

  bool _applied = false;
  Future<void>? _restoring;

  List<PluginStubPlan> _appliedPlans = const [];

  /// The stubs the current build graph resolves to, empty until [apply]
  /// succeeded.
  List<PluginStubPlan> get appliedPlans => _appliedPlans;
  final List<StreamSubscription<ProcessSignal>> _signalSubscriptions = [];

  /// Puts back what an earlier run left stubbed because it was killed before
  /// it could restore the project. Returns false when the project could not
  /// be brought back.
  Future<bool> recoverInterruptedRun() async {
    final hasBackup = _file(_backupPath(_manifestName)).existsSync();
    final hasMarker = _hasGeneratedOverrides();
    if (!hasBackup && !hasMarker) return true;

    if (dryRun) {
      Printer.warning(
        "[stubs] an earlier run left plugin stubs in place. A real run "
        "restores the project before it starts",
      );
      return true;
    }

    Printer.warning(
      "[stubs] an earlier run ended before it restored the project; "
      "restoring it now",
    );

    if (hasBackup) {
      _restoreFiles();
    } else {
      _file(PathConstants.pubspecOverridesRelativePath).deleteSync();
      Printer.warning(
        "[stubs] the backup of that run is gone, so only "
        "${PathConstants.pubspecOverridesRelativePath} was removed. "
        "pubspec.lock and ios/Podfile.lock may still describe the stubbed "
        "dependencies; restore them from version control",
      );
    }
    _deleteWorkingFolders();

    if (!await processService.pubGet()) {
      return Printer.error(
        "[stubs] flutter pub get failed after restoring the project",
      );
    }
    return true;
  }

  /// Backs up every file [restore] puts back, when the config may stub
  /// anything. It runs before the code size analysis builds, since their
  /// `pod install` already rewrites `ios/Podfile.lock`. [apply] calls it too.
  void backUp() {
    if (dryRun || _applied || (config.isEmpty && !config.auto)) return;

    _backupFiles();
    _applied = true;
    _watchSignals();
  }

  /// Stubs every configured package, and each of [autoStubs] on its platform
  /// unless the config lists it or a stub already took it out of the graph.
  /// Returns false, with the project already restored, when the stubbed
  /// dependencies could not be resolved or a stubbed plugin is still
  /// registered.
  Future<bool> apply({Map<String, AppPlatform> autoStubs = const {}}) async {
    if (config.isEmpty && autoStubs.isEmpty) return true;

    if (dryRun) {
      _describePlan();
      return true;
    }

    backUp();

    bool isSuccess;
    try {
      isSuccess = await _stubPackages(autoStubs: autoStubs);
    } catch (e) {
      isSuccess = Printer.error("[stubs] the plugins could not be stubbed: $e");
    }
    if (!isSuccess) await restore();
    return isSuccess;
  }

  /// Puts back every file [apply] changed and resolves the original
  /// dependencies again. Safe to call more than once and from a signal
  /// handler while a build is still unwinding.
  /// Once it finished, the service is back where it started, so a later
  /// [apply] backs the project up again.
  Future<void> restore() =>
      _restoring ??= _restore().whenComplete(() => _restoring = null);

  Future<void> _restore() async {
    if (!_applied) return;

    for (final subscription in _signalSubscriptions) {
      await subscription.cancel();
    }
    _signalSubscriptions.clear();

    _restoreFiles();
    _deleteWorkingFolders();
    _applied = false;
    _appliedPlans = const [];

    if (!await processService.pubGet()) {
      Printer.warning(
        "[stubs] the project files were restored but flutter pub get failed; "
        "run it before building locally",
      );
      return;
    }
    Printer.info("[stubs] project restored to its original dependencies");
  }

  Future<bool> _stubPackages({
    required Map<String, AppPlatform> autoStubs,
  }) async {
    Printer.info("[stubs] resolving the original dependencies...");
    if (!await processService.pubGet()) {
      return Printer.error(
        "[stubs] flutter pub get failed before the plugins could be stubbed",
      );
    }

    final packageConfigUri = _file(
      PathConstants.packageConfigRelativePath,
    ).absolute.uri;
    final packageConfig = _readJson(PathConstants.packageConfigRelativePath);
    if (packageConfig == null) {
      return Printer.error(
        "[stubs] ${PathConstants.packageConfigRelativePath} could not be read",
      );
    }

    final stubsFolder = Directory(_path(PathConstants.pluginStubsRelativePath));
    if (stubsFolder.existsSync()) stubsFolder.deleteSync(recursive: true);

    final plans = <PluginStubPlan>[];
    final stubPaths = <String, String>{};
    final strippedPlatforms = {...autoStubs, ...config.strippedPlatforms};
    final configuredNames = config.packageNames;

    for (final name in {...configuredNames, ...autoStubs.keys}) {
      final isConfigured = configuredNames.contains(name);
      final isOutOfGraph = plans.any(
        (plan) => plan.droppedImplementations.contains(name),
      );
      if (!isConfigured && isOutOfGraph) continue;

      final root = helper.packageRoot(
        packageConfig: packageConfig,
        packageConfigUri: packageConfigUri,
        name: name,
      );
      if (root == null) {
        return Printer.error(
          "[stubs] $name is listed in pluginStubs, prunedAssets or prunedFonts "
          "but is not a dependency of this app",
        );
      }

      final strippedPlatform = strippedPlatforms[name];
      final assetPatterns = config.prunedAssets[name] ?? const [];
      final fontFamilies = config.prunedFonts[name] ?? const [];
      final plan = helper.planStub(
        name: name,
        pubspec: loadYaml(File("$root/pubspec.yaml").readAsStringSync()),
        strippedPlatform: strippedPlatform,
        packageRoot: root,
        assetPatterns: assetPatterns,
        fontFamilies: fontFamilies,
      );
      if (strippedPlatform != null && !plan.removesNativeCode) {
        Printer.warning(
          "[stubs] $name has no native code on ${strippedPlatform.value}, so "
          "its native side was left as it is",
        );
      }
      if (assetPatterns.isNotEmpty && plan.prunedAssets.isEmpty) {
        Printer.warning(
          "[stubs] prunedAssets of $name matched none of the assets it "
          "declares: ${assetPatterns.join(", ")}",
        );
      }
      final undeclaredFonts = fontFamilies.whereNot(plan.prunedFonts.contains);
      if (undeclaredFonts.isNotEmpty) {
        Printer.warning(
          "[stubs] prunedFonts of $name lists families it does not declare: "
          "${undeclaredFonts.join(", ")}",
        );
      }
      if (!plan.changesPackage) continue;

      final stubRelativePath = "${PathConstants.pluginStubsRelativePath}/$name";
      _copyFolder(
        Directory(root),
        Directory(_path(stubRelativePath)),
        skippedFolders: helper.skippedFolders(
          plan.removesNativeCode ? strippedPlatform : null,
        ),
      );
      _file(
        "$stubRelativePath/pubspec.yaml",
      ).writeAsStringSync(helper.encodePubspec(plan.pubspec));

      plans.add(plan);
      stubPaths[name] = stubRelativePath;
    }

    if (plans.isEmpty) {
      Printer.warning("[stubs] no plugin needed a stub");
      return true;
    }

    _file(PathConstants.pubspecOverridesRelativePath).writeAsStringSync(
      helper.encodeOverridesFile(
        helper.mergeOverrides(
          baseOverrides: _projectOverrides(),
          stubPaths: stubPaths,
        ),
      ),
    );

    Printer.info("[stubs] resolving the stubbed dependencies...");
    if (!await processService.pubGet()) {
      return Printer.error(
        "[stubs] flutter pub get failed with the stubbed plugins",
      );
    }

    return _verify(plans: plans, stubPaths: stubPaths);
  }

  bool _verify({
    required List<PluginStubPlan> plans,
    required Map<String, String> stubPaths,
  }) {
    final packageConfigUri = _file(
      PathConstants.packageConfigRelativePath,
    ).absolute.uri;
    final packageConfig = _readJson(PathConstants.packageConfigRelativePath);

    for (final entry in stubPaths.entries) {
      final root = packageConfig == null
          ? null
          : helper.packageRoot(
              packageConfig: packageConfig,
              packageConfigUri: packageConfigUri,
              name: entry.key,
            );
      if (root == null || !_isSameFolder(root, _path(entry.value))) {
        return Printer.error(
          "[stubs] ${entry.key} did not resolve to its stub at ${entry.value}",
        );
      }
    }

    final strippingPlans = plans.where((plan) => plan.removesNativeCode);
    final remaining = helper.remainingRegistrations(
      pluginsDependencies: _readJson(
        PathConstants.flutterPluginsDependenciesRelativePath,
      ),
      plans: strippingPlans.toList(),
    );
    if (remaining.isNotEmpty) {
      return Printer.error(
        "[stubs] these plugins are still registered, because another "
        "dependency still pulls them in: ${remaining.join(", ")}. "
        "Add them to pluginStubs too",
      );
    }

    _appliedPlans = plans;

    final summary = plans.map(_describeAppliedPlan).join("\n");
    return Printer.success("[stubs] left out of the build:\n$summary");
  }

  String _describeAppliedPlan(PluginStubPlan plan) {
    final changes = [
      if (plan.removesNativeCode)
        "native code on ${plan.strippedPlatform!.value}"
            "${plan.droppedImplementations.isEmpty ? "" : " with ${plan.droppedImplementations.join(", ")}"}",
      if (plan.prunedAssets.isNotEmpty)
        "${plan.prunedAssets.length} assets "
            "(${StringUtils.formatBytes(plan.prunedAssetBytes)})",
      if (plan.prunedFonts.isNotEmpty)
        "fonts ${plan.prunedFonts.join(", ")} "
            "(${StringUtils.formatBytes(plan.prunedFontBytes)})",
    ];
    return "${plan.name}: ${changes.join(", ")}";
  }

  /// The overrides pub applies without uploader. A `pubspec_overrides.yaml`
  /// that sets them replaces the ones in `pubspec.yaml`.
  Map<dynamic, dynamic>? _projectOverrides() {
    final backedUpOverrides = _file(
      _backupPath(PathConstants.pubspecOverridesRelativePath),
    );
    if (backedUpOverrides.existsSync()) {
      final overrides = _readYaml(backedUpOverrides);
      if (overrides != null && overrides.containsKey("dependency_overrides")) {
        return overrides["dependency_overrides"];
      }
    }
    return _readYaml(_file("pubspec.yaml"))?["dependency_overrides"];
  }

  void _describePlan() {
    final lines = [
      for (final entry in config.strippedPlatforms.entries)
        "${entry.key} (${entry.value.value})",
      for (final entry in config.prunedAssets.entries)
        "${entry.key} assets: ${entry.value.join(", ")}",
      for (final entry in config.prunedFonts.entries)
        "${entry.key} fonts: ${entry.value.join(", ")}",
    ].join("\n");
    Printer.info(
      "[stubs] DRY RUN: these plugins would be stubbed through "
      "${PathConstants.pubspecOverridesRelativePath} and restored after the "
      "builds:\n$lines",
    );
  }

  void _backupFiles() {
    final backupFolder = Directory(
      _path(PathConstants.pluginStubBackupRelativePath),
    );
    if (backupFolder.existsSync()) backupFolder.deleteSync(recursive: true);
    backupFolder.createSync(recursive: true);

    final existed = <String, bool>{};
    for (final relativePath in PathConstants.pluginStubRestoredFiles) {
      final file = _file(relativePath);
      existed[relativePath] = file.existsSync();
      if (file.existsSync()) {
        final backup = _file(_backupPath(relativePath));
        backup.parent.createSync(recursive: true);
        file.copySync(backup.path);
      }
    }

    _file(
      _backupPath(_manifestName),
    ).writeAsStringSync(jsonEncode({"existed": existed}));
  }

  void _restoreFiles() {
    final manifest = _readJson(_backupPath(_manifestName));
    final existed = manifest?["existed"];
    if (existed is! Map) return;

    for (final entry in existed.entries) {
      final relativePath = "${entry.key}";
      final file = _file(relativePath);
      if (entry.value == true) {
        final backup = _file(_backupPath(relativePath));
        if (backup.existsSync()) {
          file.parent.createSync(recursive: true);
          backup.copySync(file.path);
        }
      } else if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  void _deleteWorkingFolders() {
    for (final relativePath in [
      PathConstants.pluginStubsRelativePath,
      PathConstants.pluginStubBackupRelativePath,
    ]) {
      final folder = Directory(_path(relativePath));
      if (folder.existsSync()) folder.deleteSync(recursive: true);
    }

    final uploaderFolder = Directory(
      _path(PathConstants.uploaderBuildRelativePath),
    );
    if (uploaderFolder.existsSync() && uploaderFolder.listSync().isEmpty) {
      uploaderFolder.deleteSync();
    }
  }

  /// A cancelled CI job or Ctrl+C must not leave the checkout stubbed.
  void _watchSignals() {
    final signals = [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ];
    for (final signal in signals) {
      _signalSubscriptions.add(
        signal.watch().listen((_) async {
          Printer.warning("[stubs] interrupted, restoring the project...");
          await restore();
          exit(_interruptedExitCode);
        }),
      );
    }
  }

  /// Copies [from] into [to], leaving out the top level folders in
  /// [skippedFolders].
  void _copyFolder(
    Directory from,
    Directory to, {
    Set<String> skippedFolders = const {},
  }) {
    to.createSync(recursive: true);
    for (final entity in from.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      );
      if (entity is Directory) {
        if (skippedFolders.contains(name)) continue;
        _copyFolder(entity, Directory("${to.path}/$name"));
      } else if (entity is File) {
        entity.copySync("${to.path}/$name");
      }
    }
  }

  bool _hasGeneratedOverrides() {
    final overrides = _file(PathConstants.pubspecOverridesRelativePath);
    if (!overrides.existsSync()) return false;
    final firstLine = overrides.readAsLinesSync().firstOrNull;
    return firstLine == pluginStubOverridesMarker;
  }

  bool _isSameFolder(String a, String b) {
    String canonical(String path) {
      final folder = Directory(path);
      return folder.existsSync() ? folder.resolveSymbolicLinksSync() : path;
    }

    return canonical(a) == canonical(b);
  }

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

  Map<dynamic, dynamic>? _readYaml(File file) {
    if (!file.existsSync()) return null;
    final decoded = loadYaml(file.readAsStringSync());
    return decoded is Map ? decoded : null;
  }

  String _backupPath(String relativePath) =>
      "${PathConstants.pluginStubBackupRelativePath}/$relativePath";

  String _path(String relativePath) => "$projectRoot/$relativePath";

  File _file(String relativePath) => File(_path(relativePath));
}
