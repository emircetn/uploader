import 'dart:io';

class Logger {
  static Logger? _instance;

  Logger._internal();

  static Logger get instance {
    _instance ??= Logger._internal();
    return _instance!;
  }

  IOSink? logSink;
  bool isInitialized = false;

  void init() {
    if (isInitialized) return;

    final date = DateTime.now().toString();

    final logFilePath = '${Directory.current.path}/uploader_log_$date.txt';
    logSink = File(logFilePath).openWrite(mode: FileMode.append);
    ProcessSignal.sigint.watch().listen((_) async {
      await close();
      exit(0);
    });
    isInitialized = true;
  }

  void log(String message) {
    if (!isInitialized) return;
    logSink!.writeln(message);
  }

  Future<void> close() async {
    if (!isInitialized) return;

    await logSink!.flush();
    await logSink!.close();
    isInitialized = false;
  }
}
