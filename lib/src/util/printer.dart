import 'dart:io';

import 'package:ansicolor/ansicolor.dart';

class Printer {
  static final _pen = AnsiPen();

  static void info(String text, {bool bold = false}) {
    _pen
      ..reset()
      ..blue(bold: bold);

    stdout.write(_pen("\n---- [INFO] ----\n$text\n"));
  }

  static bool error(String text) {
    _pen
      ..reset()
      ..red();

    stdout.write(_pen("\n---- [ERROR] ----\n$text\n"));
    return false;
  }

  static void warning(String text) {
    _pen
      ..reset()
      ..yellow();

    stdout.write(_pen("\n---- [WARNING] ----\n$text\n"));
  }

  static bool success(String text, {bool bold = false}) {
    _pen
      ..reset()
      ..green(bold: bold);

    stdout.write(_pen("\n---- [SUCCESS] ----\n$text\n"));
    return true;
  }

  static void log(String text) {
    _pen
      ..reset()
      ..yellow();

    stdout.write(_pen(text));
  }
}
