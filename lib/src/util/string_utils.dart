class StringUtils {
  static String truncate(String text, {int maxLength = 80}) {
    if (text.length > maxLength) {
      return "${text.substring(0, maxLength - 3)}...";
    }
    return text;
  }
}
