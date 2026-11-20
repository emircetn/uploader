class TodoFinding {
  /// Path relative to the project root, with `/` separators.
  final String path;

  /// 1-based line number.
  final int line;

  /// The trimmed source line.
  final String text;

  const TodoFinding({
    required this.path,
    required this.line,
    required this.text,
  });

  @override
  String toString() => "$path:$line: $text";

  @override
  bool operator ==(Object other) =>
      other is TodoFinding &&
      other.path == path &&
      other.line == line &&
      other.text == text;

  @override
  int get hashCode => Object.hash(path, line, text);
}
