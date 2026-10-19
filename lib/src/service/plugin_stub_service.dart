import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:uploader/src/constants/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/plugin_stub_helper.dart';
import 'package:uploader/src/helper/project_file_helper.dart';
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
  late final files = ProjectFileHelper(projectRoot);

  PluginStubService({
    required this.config,
    required this.processService,
    this.dryRun = false,
    String? projectRoot,
  }) : projectRoot = projectRoot ?? Directory.current.path;

  static const _manifestName = "manifest.json";
  static const _interruptedExitCode = 130;
  static const _heartbeatInterval = Duration(seconds: 5);

  bool _applied = false;
  Future<void>? _restoring;
  Timer? _heartbeat;

  List<PluginStubPlan> _appliedPlans = const [];

  /// The stubs the current build graph resolves to, empty until [apply]
  /// succeeded.
  List<PluginStubPlan> get appliedPlans => _appliedPlans;
  final List<StreamSubscription<ProcessSignal>> _signalSubscriptions = [];

  bool get _mayStub => !config.isEmpty || config.auto;

  /// False when the project is one stubs cannot be applied to, so the run
  /// stops before any build instead of after the analysis builds.
  bool checkProject() {
    if (!_mayStub) return true;
    if (files.readYaml("pubspec.yaml")?["resolution"] != "workspace") {
      return true;
    }
    return Printer.error(
      "[stubs] pluginStubs, prunedAssets and prunedFonts do not support pub "
      "workspace members yet: with `resolution: workspace` the lockfile, the "
      "package config and the overrides belong to the workspace root",
    );
  }

  /// Puts back what an earlier run left stubbed because it was killed before
  /// it could restore the project. Returns false when the project could not
  /// be brought back.
  Future<bool> recoverInterruptedRun() async {
    final manifest = files.file(_backupPath(_manifestName));
    final hasBackup = manifest.existsSync();
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
      final changedSinceRun = _restoreFiles(
        keepChangesAfter: manifest.lastModifiedSync().add(
          _heartbeatInterval * 2,
        ),
      );
      if (changedSinceRun.isNotEmpty) {
        Printer.warning(
          "[stubs] these files changed after that run ended, so they were "
          "left as they are: ${changedSinceRun.join(", ")}. Check that they "
          "do not describe stubbed dependencies",
        );
      }
    } else {
      files.file(PathConstants.pubspecOverridesRelativePath).deleteSync();
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
    if (dryRun || _applied || !_mayStub) return;

    _backupFiles();
    _applied = true;
    _watchSignals();
    _startHeartbeat();
  }

  /// Stubs every configured package, and each of [autoStubs] on its platform
  /// unless the config lists it or a stub already took it out of the graph.
  /// [isResolved] means the original dependencies were resolved since the
  /// last change to them. Returns false, with the project already restored,
  /// when the stubbed dependencies could not be resolved or a stubbed plugin
  /// is still registered.
  Future<bool> apply({
    Map<String, AppPlatform> autoStubs = const {},
    bool isResolved = false,
  }) async {
    if (config.isEmpty && autoStubs.isEmpty) {
      await _discardBackup();
      return true;
    }

    if (dryRun) {
      _describePlan();
      return true;
    }

    backUp();

    bool isSuccess;
    try {
      isSuccess = await _stubPackages(
        autoStubs: autoStubs,
        isResolved: isResolved,
      );
    } catch (e) {
      isSuccess = Printer.error("[stubs] the plugins could not be stubbed: $e");
    }
    if (!isSuccess) {
      await restore();
    } else if (_appliedPlans.isEmpty) {
      await _discardBackup();
    }
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

    await _stopWatching();
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

  /// With nothing stubbed the run is a plain build, so what its builds
  /// rewrite in the lockfiles stays, as it would without uploader.
  Future<void> _discardBackup() async {
    if (!_applied) return;

    await _stopWatching();
    _deleteWorkingFolders();
    _applied = false;
  }

  Future<bool> _stubPackages({
    required Map<String, AppPlatform> autoStubs,
    required bool isResolved,
  }) async {
    if (!isResolved) {
      Printer.info("[stubs] resolving the original dependencies...");
      if (!await processService.pubGet()) {
        return Printer.error(
          "[stubs] flutter pub get failed before the plugins could be stubbed",
        );
      }
    }

    final packageConfigUri = files
        .file(PathConstants.packageConfigRelativePath)
        .absolute
        .uri;
    final packageConfig = files.readJson(
      PathConstants.packageConfigRelativePath,
    );
    if (packageConfig == null) {
      return Printer.error(
        "[stubs] ${PathConstants.packageConfigRelativePath} could not be read",
      );
    }

    final stubsFolder = Directory(
      files.path(PathConstants.pluginStubsRelativePath),
    );
    if (stubsFolder.existsSync()) stubsFolder.deleteSync(recursive: true);

    final strippedPlatforms = {...autoStubs, ...config.strippedPlatforms};
    final configuredNames = config.packageNames;
    final candidates = <({PluginStubPlan plan, String root})>[];

    for (final name in {...configuredNames, ...autoStubs.keys}) {
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
      if (plan.changesPackage) candidates.add((plan: plan, root: root));
    }

    final outOfGraph = helper.leftGraph([
      for (final candidate in candidates) candidate.plan,
    ]);
    final plans = <PluginStubPlan>[];
    final stubPaths = <String, String>{};

    for (final (:plan, :root) in candidates) {
      final isConfigured = configuredNames.contains(plan.name);
      if (!isConfigured && outOfGraph.contains(plan.name)) continue;

      final stubRelativePath =
          "${PathConstants.pluginStubsRelativePath}/${plan.name}";
      _copyFolder(
        Directory(root),
        Directory(files.path(stubRelativePath)),
        skippedFolders: helper.skippedFolders(
          plan.removesNativeCode ? plan.strippedPlatform : null,
        ),
      );
      files
          .file("$stubRelativePath/pubspec.yaml")
          .writeAsStringSync(helper.encodePubspec(plan.pubspec));

      plans.add(plan);
      stubPaths[plan.name] = stubRelativePath;
    }

    if (plans.isEmpty) {
      Printer.warning("[stubs] no plugin needed a stub");
      return true;
    }

    files
        .file(PathConstants.pubspecOverridesRelativePath)
        .writeAsStringSync(
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
    final packageConfigUri = files
        .file(PathConstants.packageConfigRelativePath)
        .absolute
        .uri;
    final packageConfig = files.readJson(
      PathConstants.packageConfigRelativePath,
    );

    for (final entry in stubPaths.entries) {
      final root = packageConfig == null
          ? null
          : helper.packageRoot(
              packageConfig: packageConfig,
              packageConfigUri: packageConfigUri,
              name: entry.key,
            );
      if (root == null || !_isSameFolder(root, files.path(entry.value))) {
        return Printer.error(
          "[stubs] ${entry.key} did not resolve to its stub at ${entry.value}",
        );
      }
    }

    final strippingPlans = plans.where((plan) => plan.removesNativeCode);
    final remaining = helper.remainingRegistrations(
      pluginsDependencies: files.readJson(
        PathConstants.flutterPluginsDependenciesRelativePath,
      ),
      plans: strippingPlans.toList(),
    );
    if (remaining.isNotEmpty) {
      return Printer.error(
        "[stubs] these plugins are still registered, because another "
        "dependency or a platform that is still built pulls them in: "
        "${remaining.join(", ")}. Add them to pluginStubs too",
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
    final backedUpOverrides = files.readYaml(
      _backupPath(PathConstants.pubspecOverridesRelativePath),
    );
    if (backedUpOverrides != null &&
        backedUpOverrides.containsKey("dependency_overrides")) {
      return backedUpOverrides["dependency_overrides"];
    }
    return files.readYaml("pubspec.yaml")?["dependency_overrides"];
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
      files.path(PathConstants.pluginStubBackupRelativePath),
    );
    if (backupFolder.existsSync()) backupFolder.deleteSync(recursive: true);
    backupFolder.createSync(recursive: true);

    final existed = <String, bool>{};
    for (final relativePath in PathConstants.pluginStubRestoredFiles) {
      final file = files.file(relativePath);
      existed[relativePath] = file.existsSync();
      if (file.existsSync()) {
        final backup = files.file(_backupPath(relativePath));
        backup.parent.createSync(recursive: true);
        file.copySync(backup.path);
      }
    }

    files
        .file(_backupPath(_manifestName))
        .writeAsStringSync(jsonEncode({"existed": existed}));
  }

  /// Puts the backed up files back and returns those it left as they are
  /// because they changed after [keepChangesAfter].
  List<String> _restoreFiles({DateTime? keepChangesAfter}) {
    final manifest = files.readJson(_backupPath(_manifestName));
    final existed = manifest?["existed"];
    if (existed is! Map) return const [];

    final keptChanges = <String>[];
    for (final entry in existed.entries) {
      final relativePath = "${entry.key}";
      final file = files.file(relativePath);
      final isChangedSince =
          keepChangesAfter != null &&
          file.existsSync() &&
          file.lastModifiedSync().isAfter(keepChangesAfter);
      if (isChangedSince) {
        keptChanges.add(relativePath);
      } else if (entry.value == true) {
        final backup = files.file(_backupPath(relativePath));
        if (backup.existsSync()) {
          file.parent.createSync(recursive: true);
          backup.copySync(file.path);
        }
      } else if (file.existsSync()) {
        file.deleteSync();
      }
    }
    return keptChanges;
  }

  void _deleteWorkingFolders() {
    for (final relativePath in [
      PathConstants.pluginStubsRelativePath,
      PathConstants.pluginStubBackupRelativePath,
    ]) {
      final folder = Directory(files.path(relativePath));
      if (folder.existsSync()) folder.deleteSync(recursive: true);
    }

    final uploaderFolder = Directory(
      files.path(PathConstants.uploaderBuildRelativePath),
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

  /// A run killed without a signal leaves its backup behind. The manifest's
  /// modification time tells the next run until when this one was alive, so
  /// a lockfile changed after that is not overwritten with the backup.
  void _startHeartbeat() {
    final manifest = files.file(_backupPath(_manifestName));
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      if (manifest.existsSync()) manifest.setLastModifiedSync(DateTime.now());
    });
  }

  Future<void> _stopWatching() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    for (final subscription in _signalSubscriptions) {
      await subscription.cancel();
    }
    _signalSubscriptions.clear();
  }

  /// Copies [from] into [to], leaving out the top level folders in
  /// [skippedFolders]. Links are copied as links, such as an `ios/Classes`
  /// pointing at `../darwin/Classes`.
  void _copyFolder(
    Directory from,
    Directory to, {
    Set<String> skippedFolders = const {},
    Uri? packageRoot,
  }) {
    final root = packageRoot ?? from.absolute.uri;
    to.createSync(recursive: true);
    for (final entity in from.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      );
      final copyPath = "${to.path}/$name";
      if (entity is! File && skippedFolders.contains(name)) continue;

      if (entity is Link) {
        Link(copyPath).createSync(_copiedLinkTarget(entity, packageRoot: root));
      } else if (entity is Directory) {
        _copyFolder(entity, Directory(copyPath), packageRoot: root);
      } else if (entity is File) {
        entity.copySync(copyPath);
      }
    }
  }

  /// A relative target inside the package still holds in the copy; any other
  /// target has to name the original, since the copy lives somewhere else.
  String _copiedLinkTarget(Link link, {required Uri packageRoot}) {
    final target = link.targetSync();
    final targetUri = Uri.file(target);
    final resolved = link.absolute.parent.uri.resolveUri(targetUri);
    final staysInPackage =
        !targetUri.isAbsolute && resolved.path.startsWith(packageRoot.path);
    return staysInPackage ? target : resolved.toFilePath();
  }

  bool _hasGeneratedOverrides() {
    final overrides = files.file(PathConstants.pubspecOverridesRelativePath);
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

  String _backupPath(String relativePath) =>
      "${PathConstants.pluginStubBackupRelativePath}/$relativePath";
}
