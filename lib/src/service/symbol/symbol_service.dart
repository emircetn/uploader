import 'dart:io';

import 'package:collection/collection.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/helper/app_distribution_helper.dart';
import 'package:uploader/src/helper/secret_helper.dart';
import 'package:uploader/src/model/app_detail.dart';
import 'package:uploader/src/model/archived_build.dart';
import 'package:uploader/src/model/symbols_config.dart';
import 'package:uploader/src/service/process_service.dart';
import 'package:uploader/src/service/symbol/command_destination.dart';
import 'package:uploader/src/service/symbol/crashlytics_destination.dart';
import 'package:uploader/src/service/symbol/new_relic_destination.dart';
import 'package:uploader/src/service/symbol/symbol_archive_service.dart';
import 'package:uploader/src/service/symbol/symbol_destination.dart';
import 'package:uploader/src/util/build_parameters.dart';
import 'package:uploader/src/util/printer.dart';

/// Archives each build's symbols as soon as the build ends, before the next
/// build overwrites them, and sends them to every configured destination
/// once the run's distribution uploads are done, so a slow crash reporter
/// never holds back a release. An upload that fails is recorded as pending
/// in the archive and can be repeated with `--upload-symbols`.
class SymbolService {
  final SymbolsConfig config;
  final AppDetail appDetail;
  final bool dryRun;
  final int retryCount;
  final String projectRoot;
  final Map<String, String> environment;

  /// Replaces the destinations [config] describes, for tests and harnesses
  /// that must not reach the network.
  final List<SymbolDestination>? destinationsOverride;

  final String runId;
  late final String archiveRoot;
  late final SymbolArchiveService archiveService;
  late final ProcessService processService = ProcessService(dryRun: dryRun);

  SymbolService({
    required this.config,
    required this.appDetail,
    required this.retryCount,
    this.dryRun = false,
    String? projectRoot,
    Map<String, String>? environment,
    DateTime? startedAt,
    List<SymbolDestination>? destinations,
  }) : destinationsOverride = destinations,
       projectRoot = projectRoot ?? Directory.current.path,
       environment = environment ?? Platform.environment,
       runId = SymbolArchiveService.runIdFor(startedAt ?? DateTime.now()) {
    archiveRoot = config.resolveArchivePath(
      projectRoot: this.projectRoot,
      environment: this.environment,
    );
    archiveService = SymbolArchiveService(
      archiveRoot: archiveRoot,
      appName: appDetail.appName,
      projectRoot: this.projectRoot,
    );
  }

  String get archiveFolder => archiveService.appRoot;

  /// The builds this run archived, uploaded by [uploadArchived].
  final List<ArchivedBuild> _archived = [];

  /// Archives what the build of [platform] for [target] just produced. False
  /// only when the symbols could not be archived. The version and build
  /// number are the ones the build was given, `--build-name` and
  /// `--build-number` winning over `pubspec.yaml`.
  Future<bool> handleBuild({
    required AppPlatform platform,
    required BuildTarget target,
    required List<String> buildParameters,
  }) async {
    final tag = "[${platform.value}]";
    final version =
        BuildParameters.buildName(buildParameters) ?? appDetail.buildVersion;
    final buildNumber =
        BuildParameters.buildNumber(buildParameters) ?? appDetail.buildNumber;

    if (dryRun) {
      _info(
        platform,
        "$tag would archive the ${target.name} build's symbols to "
        "${archiveService.appRoot}/"
        "${ArchivedBuild.fullVersionOf(version, buildNumber)}/$runId/"
        "${platform.value}-${target.name} and, after the uploads, send them "
        "to: ${_describeDestinations(platform)}",
      );
      return true;
    }

    final files = archiveService.collect(
      platform,
      buildParameters: buildParameters,
    );
    if (files.isEmpty) {
      Printer.warning(
        "$tag the ${target.name} build left no symbols to archive "
        "(no mapping.txt, native libraries, dSYMs or Dart symbols)",
      );
      return true;
    }

    final ArchivedBuild build;
    try {
      build = await archiveService.archive(
        runId: runId,
        version: version,
        buildNumber: buildNumber,
        platform: platform,
        target: target,
        files: files,
        firebaseAppId: await _firebaseAppId(platform),
        newRelicBuildId: platform == AppPlatform.android
            ? archiveService.readNewRelicBuildId(
                buildParameters: buildParameters,
              )
            : null,
        gitCommit: _gitCommit(),
      );
    } catch (e) {
      return Printer.error(
        "$tag the ${target.name} build's symbols could not be archived, so "
        "the run stops before the next build overwrites them: $e",
      );
    }

    Printer.success(
      "$tag ${target.name} symbols archived: ${build.directory.path} "
      "(${build.files.values.join(", ")})",
    );

    // Recorded as pending until [uploadArchived] sends them, so a run that
    // stops before then leaves them to `--upload-symbols`.
    for (final destination in _destinations()) {
      if (!destination.supports(platform)) continue;
      build.record(
        destination.name,
        UploadRecord(
          status: UploadStatus.pending,
          at: DateTime.now(),
          message:
              "not uploaded yet: the run stopped before its symbol uploads",
        ),
      );
    }
    build.save();

    _archived.add(build);
    return true;
  }

  /// Sends the builds this run archived to every destination. False only
  /// when an upload is left pending and [SymbolsConfig.failOnUploadError] is
  /// set.
  Future<bool> uploadArchived() async {
    if (dryRun || _archived.isEmpty) return true;

    final destinations = _destinations();
    final pending = <ArchivedBuild>[];
    for (final build in _archived) {
      await _uploadSafely(build, destinations);
      if (build.hasPendingUploads) pending.add(build);
    }
    _archived.clear();
    if (pending.isEmpty) return true;

    final message =
        "symbol upload pending:\n${pending.map((build) => "  ${build.label}: "
            "${build.pendingDestinations.join(", ")}").join("\n")}\n"
        "The files are archived; retry with `dart run uploader --upload-symbols`";
    if (config.failOnUploadError) return Printer.error(message);
    Printer.warning(message);
    return true;
  }

  /// Retries every archived upload still pending. True when none is left.
  Future<bool> uploadPending() async {
    final pending = archiveService
        .loadAll()
        .where((build) => build.hasPendingUploads)
        .toList();

    if (pending.isEmpty) {
      return Printer.success(
        "no symbol uploads pending in ${archiveService.appRoot}",
      );
    }

    final destinations = _destinations();
    for (final build in pending) {
      Printer.info(
        "[${build.platform.value}] retrying ${build.label} "
        "(${build.directory.path})",
        bold: true,
      );
      if (dryRun) {
        Printer.info("would upload to ${build.pendingDestinations.join(", ")}");
        continue;
      }
      await _uploadSafely(
        build,
        destinations,
        only: build.pendingDestinations.toSet(),
      );
    }

    if (dryRun) return true;

    final left = pending.where((build) => build.hasPendingUploads).toList();
    if (left.isEmpty) return Printer.success("every pending upload is done");

    return Printer.error(
      "still pending:\n${left.map((build) => "  ${build.label}: "
          "${build.pendingDestinations.join(", ")}").join("\n")}",
    );
  }

  /// Removes the oldest archived runs beyond [SymbolsConfig.keepLast].
  void prune() {
    if (dryRun) return;
    try {
      final (:removed, :removedPending) = archiveService.prune(config.keepLast);
      if (removed.isNotEmpty) {
        Printer.info(
          "removed ${removed.length} archived run(s) beyond the last "
          "${config.keepLast}",
        );
      }
      if (removedPending.isNotEmpty) {
        Printer.warning(
          "these runs were removed with uploads still pending, since "
          "${config.keepLast} newer runs with pending uploads are kept: "
          "${removedPending.join(", ")}",
        );
      }
    } catch (e) {
      Printer.warning("old symbol archives could not be removed: $e");
    }
  }

  /// [_upload], with anything it throws, such as an archived zip deleted by
  /// hand, recorded against the build instead of stopping the uploads of
  /// the builds after it.
  Future<void> _uploadSafely(
    ArchivedBuild build,
    List<SymbolDestination> destinations, {
    Set<String>? only,
  }) async {
    try {
      await _upload(build, destinations, only: only);
    } catch (e) {
      Printer.warning(
        "[${build.platform.value}] ${build.label} could not be uploaded: $e",
      );
      try {
        for (final destination in destinations) {
          if (!destination.supports(build.platform)) continue;
          if (only != null && !only.contains(destination.name)) continue;
          if (build.uploads[destination.name]?.status == UploadStatus.done) {
            continue;
          }
          build.record(
            destination.name,
            UploadRecord(
              status: UploadStatus.pending,
              at: DateTime.now(),
              message: "$e",
            ),
          );
        }
        build.save();
      } catch (_) {
        // The build's folder itself is gone; nothing is left to retry.
      }
    }
  }

  Future<void> _upload(
    ArchivedBuild build,
    List<SymbolDestination> destinations, {
    Set<String>? only,
  }) async {
    final platform = build.platform;
    final tag = "[${platform.value}]";

    // A build that could not read its Firebase app id gets another chance,
    // so a retry after fixing google-services.json can go through.
    if (build.firebaseAppId == null) {
      final appId = await _firebaseAppId(platform);
      if (appId != null) {
        build.firebaseAppId = appId;
        build.save();
      }
    }

    final active = [
      for (final destination in destinations)
        if (destination.supports(platform) &&
            (only == null || only.contains(destination.name)))
          destination,
    ];

    // A pending upload whose destination is gone from the configuration can
    // never be retried; left pending, it would also keep its run forever.
    if (only != null) {
      final gone = only.where(
        (name) => active.none((destination) => destination.name == name),
      );
      for (final name in gone) {
        build.record(
          name,
          UploadRecord(
            status: UploadStatus.skipped,
            at: DateTime.now(),
            message: "no longer configured for ${platform.value}",
          ),
        );
        Printer.warning(
          "$tag $name was pending but is no longer configured for "
          "${platform.value}; marked as skipped",
        );
      }
      if (gone.isNotEmpty) build.save();
    }

    if (active.isEmpty) return;

    try {
      final kinds = {
        for (final destination in active) ...destination.kindsNeeded(build),
      };
      await archiveService.extract(build, kinds);
    } catch (e) {
      for (final destination in active) {
        build.record(
          destination.name,
          UploadRecord(
            status: UploadStatus.pending,
            at: DateTime.now(),
            message: "the archive could not be extracted: $e",
          ),
        );
      }
      build.save();
      Printer.warning(
        "$tag ${build.directory.path} could not be extracted: $e",
      );
      return;
    }

    try {
      for (final destination in active) {
        await _uploadTo(destination, build);
      }
    } finally {
      archiveService.release(build);
    }
  }

  Future<void> _uploadTo(
    SymbolDestination destination,
    ArchivedBuild build,
  ) async {
    final platform = build.platform;
    final tag = "[${platform.value}]";
    _info(platform, "$tag uploading symbols to ${destination.name}...");

    UploadOutcome outcome;
    try {
      outcome = await destination.upload(build);
    } catch (e) {
      outcome = UploadOutcome.pending("$e");
    }

    build.record(
      destination.name,
      UploadRecord(
        status: outcome.status,
        at: DateTime.now(),
        message: outcome.message,
      ),
    );
    build.save();

    final detail = outcome.message == null ? "" : ": ${outcome.message}";
    switch (outcome.status) {
      case UploadStatus.done:
        Printer.success("$tag ${destination.name} symbols uploaded$detail");
      case UploadStatus.skipped:
        _info(platform, "$tag ${destination.name} skipped$detail");
      case UploadStatus.pending:
        Printer.warning("$tag ${destination.name} upload failed$detail");
    }
  }

  List<SymbolDestination> _destinations() =>
      destinationsOverride ?? _configuredDestinations();

  List<SymbolDestination> _configuredDestinations() => [
    if (config.crashlytics)
      CrashlyticsDestination(
        processService: processService,
        projectRoot: projectRoot,
        retryCount: retryCount,
      ),
    if (config.newRelic case final newRelic?)
      NewRelicDestination(
        config: newRelic,
        secrets: SecretHelper(
          projectRoot: projectRoot,
          environment: environment,
        ),
        processService: processService,
        retryCount: retryCount,
      ),
    for (final command in config.commands)
      CommandDestination(
        command: command,
        processService: processService,
        retryCount: retryCount,
      ),
  ];

  String _describeDestinations(AppPlatform platform) {
    final names = [
      for (final destination in _destinations())
        if (destination.supports(platform)) destination.name,
    ];
    return names.isEmpty ? "(none, archive only)" : names.join(", ");
  }

  Future<String?> _firebaseAppId(AppPlatform platform) async {
    final account = await AppDistributionHelper().getAccountConfig(platform);
    return platform == AppPlatform.ios ? account?.iosId : account?.androidId;
  }

  String? _gitCommit() {
    try {
      final result = Process.runSync("git", [
        "rev-parse",
        "HEAD",
      ], workingDirectory: projectRoot);
      if (result.exitCode != 0) return null;
      final commit = "${result.stdout}".trim();
      return commit.isEmpty ? null : commit;
    } catch (_) {
      return null;
    }
  }

  void _info(AppPlatform platform, String text) => switch (platform) {
    AppPlatform.ios => Printer.infoIOS(text),
    AppPlatform.android => Printer.infoAndroid(text),
    AppPlatform.all => Printer.info(text),
  };
}
