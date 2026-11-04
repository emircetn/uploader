import 'dart:io';

import 'package:args/args.dart';
import 'package:uploader/src/helper/parse_helper.dart';
import 'package:uploader/src/helper/pubspec_helper.dart';
import 'package:uploader/src/helper/upload_helper.dart';
import 'package:uploader/src/manager/uploader_manager.dart';
import 'package:uploader/src/model/cli_options.dart';
import 'package:uploader/src/model/pubspec_parameters.dart';
import 'package:uploader/src/service/symbol/symbol_service.dart';
import 'package:uploader/src/util/logger.dart';
import 'package:uploader/src/util/printer.dart';

const _usageHeader = "Usage: dart run uploader [options]";

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Skip the confirmation prompt. Required for non-interactive runs.',
    )
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'Print the commands that would run without running any of them.',
    )
    ..addFlag(
      'audit',
      negatable: false,
      help:
          'Build once per platform for code size analysis and report which '
          'plugins the Dart code can still reach. Nothing is stubbed or '
          'uploaded.',
    )
    ..addFlag(
      'upload-symbols',
      negatable: false,
      help:
          'Retry every archived symbol upload that is still pending. Nothing '
          'is built.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help text.')
    ..addFlag('version', negatable: false, help: 'Print the uploader version.');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    Printer.error("${e.message}\n\n$_usageHeader\n${parser.usage}");
    exitCode = 64;
    return;
  }

  if (args.flag('help')) {
    Printer.info("$_usageHeader\n${parser.usage}");
    return;
  }

  final cliOptions = CliOptions(
    skipConfirmation: args.flag('yes'),
    dryRun: args.flag('dry-run'),
    audit: args.flag('audit'),
    uploadSymbols: args.flag('upload-symbols'),
  );

  final pubspecHelper = PubspecHelper();
  final uploadHelper = UploadHelper();

  final pubspecParameters = pubspecHelper.getPubspecParameters();

  if (pubspecParameters == null) {
    Printer.error("pubspec parameters could not be parsed");
    exitCode = 1;
    return;
  }

  if (cliOptions.uploadSymbols) {
    if (!await _uploadPendingSymbols(pubspecParameters, cliOptions)) {
      exitCode = 1;
    }
    return;
  }

  if (!uploadHelper.checkPubspecParameters(pubspecParameters)) {
    exitCode = 1;
    return;
  }

  final uploaderConfig = await uploadHelper.createUploaderConfig(
    pubspecParameters,
    cliOptions: cliOptions,
  );

  if (uploaderConfig == null) {
    Printer.error("uploader config could not be created");
    exitCode = 1;
    return;
  }

  if (uploaderConfig.enableLogFileCreation) Logger.instance.init();

  final uploaderManager = UploaderManager(config: uploaderConfig);
  final isSuccess = await uploaderManager.startUpload();

  if (uploaderConfig.enableLogFileCreation) await Logger.instance.close();

  if (!isSuccess) exitCode = 1;
}

/// Retries archived uploads without building, so it needs neither store
/// credentials nor testers, only the `symbols` section and the app's name.
Future<bool> _uploadPendingSymbols(
  PubspecParameters pubspecParameters,
  CliOptions cliOptions,
) async {
  final symbols = pubspecParameters.symbols;
  if (symbols == null) {
    return Printer.error(
      "--upload-symbols needs an uploader.symbols section in pubspec.yaml",
    );
  }

  final appDetail = await ParseHelper().getAppDetails();
  if (appDetail == null) return Printer.error("app detail not found");

  final SymbolService symbolService;
  try {
    symbolService = SymbolService(
      config: symbols,
      appDetail: appDetail,
      retryCount: pubspecParameters.uploadRetryCount,
      dryRun: cliOptions.dryRun,
    );
  } on StateError catch (e) {
    return Printer.error("[symbols] ${e.message}");
  }
  return await symbolService.uploadPending();
}
