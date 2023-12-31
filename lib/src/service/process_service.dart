import 'dart:io';

import 'package:uploader/src/config/ios/ios_account_config.dart';
import 'package:uploader/src/config/ios/ios_config.dart';
import 'package:uploader/src/constant/path_constants.dart';
import 'package:uploader/src/enum/enums.dart';
import 'package:uploader/src/util/printer.dart';

class ProcessService {
  Future<bool> buildIpa({
    required IPAType type,
    List<String>? extraBuildParameters,
  }) async {
    return await _runProcess(
      executable: 'flutter',
      arguments: [
        'build',
        'ipa',
        (type == IPAType.adHoc
            ? '--export-method=ad-hoc'
            : '--export-method=app-store'),
        if (extraBuildParameters != null && extraBuildParameters.isNotEmpty)
          extraBuildParameters.join(', ')
      ],
    );
  }

  Future<bool> buildAbb({
    String? skslPath,
    List<String>? extraBuildParameters,
  }) async {
    return await _runProcess(
      executable: 'flutter',
      arguments: [
        'build',
        'appbundle',
        '--release',
        if (skslPath != null && skslPath.isNotEmpty) ...[
          '--bundle-sksl-path',
          skslPath,
        ],
        if (extraBuildParameters != null && extraBuildParameters.isNotEmpty)
          extraBuildParameters.join(', ')
      ],
    );
  }

  Future<bool> buildApk({
    List<String>? extraBuildParameters,
  }) async {
    return await _runProcess(
      executable: 'flutter',
      arguments: [
        'build',
        'apk',
        '--release',
        if (extraBuildParameters != null && extraBuildParameters.isNotEmpty)
          extraBuildParameters.join(', ')
      ],
    );
  }

  Future<bool> uploadIpaToAppDistribution({
    required String firebaseAppId,
    required String ipaName,
    required String? releaseNotes,
    required List<String>? testers,
  }) async {
    return await _runProcess(
      executable: 'firebase',
      arguments: [
        'appdistribution:distribute',
        "build/ios/ipa/$ipaName.ipa",
        '--app',
        firebaseAppId,
        if (releaseNotes != null) ...[
          '--release-notes',
          releaseNotes,
        ],
        if (testers != null && testers.isNotEmpty) ...[
          '--testers',
          testers.join(', '),
        ]
      ],
    );
  }

  Future<bool> uploadAbbToAppDistribution({
    required String firebaseAppId,
    required String? releaseNotes,
    required List<String>? testers,
  }) async {
    return await _runProcess(
      executable: 'firebase',
      arguments: [
        'appdistribution:distribute',
        PathConstants.abbRelativePath,
        '--app',
        firebaseAppId,
        if (releaseNotes != null) ...[
          '--release-notes',
          releaseNotes,
        ],
        if (testers != null && testers.isNotEmpty) ...[
          '--testers',
          testers.join(', '),
        ]
      ],
    );
  }

  Future<bool> uploadApkToAppDistribution({
    required String firebaseAppId,
    required String? releaseNotes,
    required List<String>? testers,
  }) async {
    return await _runProcess(
      executable: 'firebase',
      arguments: [
        'appdistribution:distribute',
        PathConstants.apkRelativePath,
        '--app',
        firebaseAppId,
        if (releaseNotes != null) ...[
          '--release-notes',
          releaseNotes,
        ],
        if (testers != null && testers.isNotEmpty) ...[
          '--testers',
          testers.join(', '),
        ]
      ],
    );
  }

  Future<bool> uploadToTestFlight({
    required IosConfig iosConfig,
    required IosAccountConfig accountConfig,
    required String ipaName,
  }) async {
    return await _runProcess(
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

  Future<bool> _runProcess({
    required String executable,
    required List<String> arguments,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        runInShell: true,
        mode: mode,
      );

      await stdout.addStream(process.stdout);
      await stderr.addStream(process.stderr);

      final exitCode = await process.exitCode;

      return exitCode == 0;
    } catch (e) {
      Printer.error("$e");
      return false;
    }
  }
}
