// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:uploader/src/config/ios/ios_account_config.dart';
import 'package:uploader/src/config/ios/ios_config.dart';
import 'package:uploader/src/constants/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/util/printer.dart';

class ProcessService {
  final bool dryRun;

  ProcessService({this.dryRun = false});

  Future<bool> buildIpa({
    required IPAType type,
    List<String>? extraBuildParameters,
  }) async {
    return await _runProcess(
      platform: AppPlatform.ios,
      executable: 'flutter',
      arguments: [
        'build',
        'ipa',
        (type == IPAType.adHoc
            ? '--export-method=ad-hoc'
            : '--export-method=app-store'),
        ...?extraBuildParameters,
      ],
    );
  }

  Future<bool> buildAbb({
    String? skslPath,
    List<String>? extraBuildParameters,
  }) async {
    return await _runProcess(
      platform: AppPlatform.android,
      executable: 'flutter',
      arguments: [
        'build',
        'appbundle',
        '--release',
        if (skslPath != null && skslPath.isNotEmpty) ...[
          '--bundle-sksl-path',
          skslPath,
        ],
        ...?extraBuildParameters,
      ],
    );
  }

  Future<bool> buildApk({List<String>? extraBuildParameters}) async {
    return await _runProcess(
      platform: AppPlatform.android,
      executable: 'flutter',
      arguments: ['build', 'apk', '--release', ...?extraBuildParameters],
    );
  }

  Future<bool> uploadIpaToAppDistribution({
    required String firebaseAppId,
    required String ipaName,
    required String? releaseNotes,
    required List<String>? testers,
    required List<String>? groups,
  }) async {
    return await _runProcess(
      platform: AppPlatform.ios,
      executable: 'firebase',
      arguments: [
        'appdistribution:distribute',
        PathConstants.ipaRelativePath(ipaName),
        '--app',
        firebaseAppId,
        if (releaseNotes != null) ...['--release-notes', ".$releaseNotes"],
        ..._recipientArguments(testers: testers, groups: groups),
      ],
    );
  }

  Future<bool> uploadAbbToAppDistribution({
    required String firebaseAppId,
    required String? releaseNotes,
    required List<String>? testers,
    required List<String>? groups,
  }) async {
    return await _runProcess(
      platform: AppPlatform.android,
      executable: 'firebase',
      arguments: [
        'appdistribution:distribute',
        PathConstants.abbRelativePath,
        '--app',
        firebaseAppId,
        if (releaseNotes != null) ...['--release-notes', ".$releaseNotes"],
        ..._recipientArguments(testers: testers, groups: groups),
      ],
    );
  }

  Future<bool> uploadApkToAppDistribution({
    required String firebaseAppId,
    required String? releaseNotes,
    required List<String>? testers,
    required List<String>? groups,
  }) async {
    return await _runProcess(
      platform: AppPlatform.android,
      executable: 'firebase',
      arguments: [
        'appdistribution:distribute',
        PathConstants.apkRelativePath,
        '--app',
        firebaseAppId,
        if (releaseNotes != null) ...['--release-notes', ".$releaseNotes"],
        ..._recipientArguments(testers: testers, groups: groups),
      ],
    );
  }

  Future<bool> uploadToTestFlight({
    required IosConfig testFlightConfig,
    required IosAccountConfig accountConfig,
    required String ipaName,
  }) async {
    return await _runProcess(
      platform: AppPlatform.ios,
      executable: 'xcrun',
      arguments: [
        'altool',
        '--upload-app',
        '--type',
        'ios',
        "-f",
        PathConstants.ipaRelativePath(ipaName),
        '--apiKey',
        accountConfig.authKey,
        '--apiIssuer',
        accountConfig.issuerId,
      ],
    );
  }

  List<String> _recipientArguments({
    required List<String>? testers,
    required List<String>? groups,
  }) {
    return [
      if (testers != null && testers.isNotEmpty) ...[
        '--testers',
        testers.join(', '),
      ],
      if (groups != null && groups.isNotEmpty) ...[
        '--groups',
        groups.join(','),
      ],
    ];
  }

  Future<bool> _runProcess({
    required AppPlatform platform,
    required String executable,
    required List<String> arguments,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    if (dryRun) {
      Printer.info(
        "[${platform.value}] would run: $executable ${arguments.join(' ')}",
      );
      return true;
    }

    try {
      final process = await Process.start(
        executable,
        arguments,
        runInShell: true,
        mode: mode,
      );

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            print("[${platform.value}] $line");
          });
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            print("[${platform.value}] $line");
          });

      final exitCode = await process.exitCode;

      return exitCode == 0;
    } catch (e) {
      Printer.error("$e");
      return false;
    }
  }
}
