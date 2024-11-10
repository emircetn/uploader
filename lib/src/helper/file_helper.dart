import 'dart:convert';
import 'dart:io';

class FileHelper {
  Future<List<String>?> readFileLines(String path) async {
    try {
      return await File(path)
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
    } catch (e) {
      return null;
    }
  }

  Future<String?> readFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (e) {
      return null;
    }
  }
}
