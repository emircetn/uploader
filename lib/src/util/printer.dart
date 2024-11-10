import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:uploader/src/util/logger.dart';

enum LogType {
  info(text: "INFO"),
  error(text: "ERROR"),
  warning(text: "WARNING"),
  success(text: "SUCCESS");

  final String text;

  const LogType({required this.text});
}

class Printer {
  static final _pen = AnsiPen();

  static void info(String text, {bool bold = false}) {
    header(LogType.info);

    _pen
      ..reset()
      ..blue(bold: bold);

    _write(text);
    _write("\n");
  }

  static void infoIOS(String text, {bool bold = false}) {
    header(LogType.info);

    _pen
      ..reset()
      ..cyan(bold: bold);

    _write(text);
    _write("\n");
  }

  static void infoAndroid(String text, {bool bold = false}) {
    header(LogType.info);

    _pen
      ..reset()
      ..magenta(bold: bold);

    _write(text);
    _write("\n");
  }

  static bool error(String text) {
    header(LogType.error);
    _pen
      ..reset()
      ..red();

    _write(text);
    _write("\n");
    return false;
  }

  static void warning(String text) {
    header(LogType.warning);

    _pen
      ..reset()
      ..yellow();

    _write(text);
    _write("\n");
  }

  static bool success(String text, {bool bold = false}) {
    header(LogType.success);
    _pen
      ..reset()
      ..green(bold: bold);

    _write(text);
    _write("\n");

    return true;
  }

  static void log(String text) {
    _pen
      ..reset()
      ..yellow();

    _write(text);
    _write("\n");
  }

  static void header(LogType logType) {
    _pen
      ..reset()
      ..black(bold: true);

    _write("\n");
    _write("[${logType.text}]");
    _write("\n");
  }

  static void _write(String text) {
    stdout.write(_pen(text));
    Logger.instance.log(text);
  }
}
