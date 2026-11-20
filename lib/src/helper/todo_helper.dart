import "dart:io";

import "package:uploader/src/model/todo_finding.dart";

/// Finds `TODO` comments in the project's own Dart code. It prints nothing
/// and decides nothing: the caller lists the findings and chooses whether
/// they stop the run.
class TodoHelper {
  /// A `TODO` marker inside a `//` or `/*` comment, including a `*`
  /// continuation line of a block comment. A `TODO` in a string or an
  /// identifier does not match.
  static final _commentTodo = RegExp(
    r"(?://|/\*).*?\bTODO\b|^\s*\*.*?\bTODO\b",
  );

  static const _generatedSuffixes = [".g.dart", ".freezed.dart", ".gr.dart"];

  /// Comment TODOs under [directories] of [root], ordered by path then line.
  /// A directory that does not exist is skipped, so a project without `lib/`
  /// still runs.
  List<TodoFinding> find({
    String root = ".",
    List<String> directories = const ["lib"],
  }) {
    final findings = <TodoFinding>[];
    for (final directory in directories) {
      final folder = Directory("$root/$directory");
      if (!folder.existsSync()) continue;

      for (final entity in folder.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !_isHandWrittenDart(entity.path)) continue;

        final List<String> lines;
        try {
          lines = entity.readAsLinesSync();
        } on FileSystemException {
          continue;
        }

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!_commentTodo.hasMatch(line)) continue;
          findings.add(
            TodoFinding(
              path: _relative(root, entity.path),
              line: i + 1,
              text: line.trim(),
            ),
          );
        }
      }
    }

    findings.sort((a, b) {
      final byPath = a.path.compareTo(b.path);
      return byPath != 0 ? byPath : a.line.compareTo(b.line);
    });
    return findings;
  }

  bool _isHandWrittenDart(String path) =>
      path.endsWith(".dart") && !_generatedSuffixes.any(path.endsWith);

  String _relative(String root, String path) {
    final rootPath = Directory(root).absolute.path;
    final filePath = File(path).absolute.path;
    final separator = Platform.pathSeparator;
    final prefix = rootPath.endsWith(separator)
        ? rootPath
        : "$rootPath$separator";
    final relative = filePath.startsWith(prefix)
        ? filePath.substring(prefix.length)
        : filePath;
    return relative.split(separator).join("/");
  }
}
