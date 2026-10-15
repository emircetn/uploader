class StringUtils {
  static String truncate(String text, {int maxLength = 80}) {
    if (text.length > maxLength) {
      return "${text.substring(0, maxLength - 3)}...";
    }
    return text;
  }

  static const int bytesPerMegabyte = 1000000;

  /// Decimal units, matching the IPA size report and App Store Connect.
  static String formatBytes(int bytes) {
    if (bytes >= bytesPerMegabyte) {
      return "${(bytes / bytesPerMegabyte).toStringAsFixed(1)} MB";
    }
    if (bytes >= 1000) return "${(bytes / 1000).toStringAsFixed(1)} KB";
    return "$bytes B";
  }
}
