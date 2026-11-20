import "dart:io";

import "package:test/test.dart";
import "package:uploader/src/helper/todo_helper.dart";
import "package:uploader/src/model/todo_finding.dart";

void main() {
  final helper = TodoHelper();
  late Directory sandbox;

  setUp(() => sandbox = Directory.systemTemp.createTempSync("todo_helper"));
  tearDown(() => sandbox.deleteSync(recursive: true));

  void write(String relativePath, String content) =>
      File("${sandbox.path}/$relativePath")
        ..createSync(recursive: true)
        ..writeAsStringSync(content);

  List<TodoFinding> find() => helper.find(root: sandbox.path);

  TodoFinding todo(String path, int line, String text) =>
      TodoFinding(path: path, line: line, text: text);

  test("comment TODOs are reported with a relative path and line", () {
    write(
      "lib/src/app.dart",
      [
        "class App {",
        "  // TODO: fix the gate",
        '  final label = "TODO";',
        "  void run() {} // TODO: handle errors",
        "  /// TODO: document this",
        "  /* TODO: block */",
        "  /*",
        "   * TODO: continued",
        "   */",
        "  // todo: lowercase is not a marker",
        "  // TODOS are a different word",
        "}",
      ].join("\n"),
    );

    expect(find(), [
      todo("lib/src/app.dart", 2, "// TODO: fix the gate"),
      todo("lib/src/app.dart", 4, "void run() {} // TODO: handle errors"),
      todo("lib/src/app.dart", 5, "/// TODO: document this"),
      todo("lib/src/app.dart", 6, "/* TODO: block */"),
      todo("lib/src/app.dart", 8, "* TODO: continued"),
    ]);
  });

  test("generated dart files are skipped", () {
    write("lib/app.g.dart", "// TODO: generated\n");
    write("lib/app.freezed.dart", "// TODO: generated\n");
    write("lib/app.gr.dart", "// TODO: generated\n");
    write("lib/app.dart", "// TODO: keep\n");

    expect(find(), [todo("lib/app.dart", 1, "// TODO: keep")]);
  });

  test("only the requested directories are scanned", () {
    write("lib/app.dart", "// TODO: in lib\n");
    write("test/app_test.dart", "// TODO: in test\n");
    write("android/Main.dart", "// TODO: android\n");

    expect(find().map((todo) => todo.path), ["lib/app.dart"]);
  });

  test("a project without lib/ yields nothing", () {
    write("pubspec.yaml", "name: app\n");

    expect(find(), isEmpty);
  });

  test("findings are ordered by path then line", () {
    write("lib/b.dart", "// TODO: b\n");
    write("lib/a.dart", "var x = 1;\n// TODO: later\n// TODO: earlier\n");

    expect(find().map((todo) => "${todo.path}:${todo.line}"), [
      "lib/a.dart:2",
      "lib/a.dart:3",
      "lib/b.dart:1",
    ]);
  });
}
