library uploader;

import 'package:uploader/src/helper/pubspec_helper.dart';
import 'package:uploader/src/helper/upload_helper.dart';
import 'package:uploader/src/manager/uploader_manager.dart';
import 'package:uploader/src/util/printer.dart';

void main() async {
  final pubspecHelper = PubspecHelper();
  final uploadHelper = UploadHelper();

  final pubspecParameters = pubspecHelper.getPubspecParameters();

  if (pubspecParameters == null) {
    Printer.error("pubspec parameters could not be parsed");
    return;
  }

  final isSuccess = uploadHelper.checkPubspecParameters(pubspecParameters);
  if (!isSuccess) return;

  final uploaderConfig = await uploadHelper.createUploaderConfig(
    pubspecParameters,
  );
  if (uploaderConfig == null) {
    Printer.error("uploader config could not be created");
    return;
  }

  final uploaderManager = UploaderManager(config: uploaderConfig);
  await uploaderManager.startUpload();
}
