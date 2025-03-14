import 'package:dio/dio.dart';

class DownloadHelper {
  Future<String> downloadFile(String url) async {
    final response = await Dio().get(url);
    return response.data;
  }
}
