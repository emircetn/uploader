import 'package:uploader/src/util/printer.dart';

class RetryUtils {
  const RetryUtils._();

  static Future<bool> run(
    Future<bool> Function() action, {
    required int retryCount,
    required String label,
  }) async {
    for (var attempt = 0; ; attempt++) {
      if (await action()) return true;

      if (attempt >= retryCount) return false;

      final delay = _delayFor(attempt);
      Printer.warning(
        "$label failed, retrying (${attempt + 1}/$retryCount) "
        "in ${delay.inSeconds}s...",
      );
      await Future.delayed(delay);
    }
  }

  static Duration _delayFor(int attempt) =>
      Duration(seconds: 5 * (attempt + 1));
}
