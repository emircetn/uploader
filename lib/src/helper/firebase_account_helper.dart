import 'dart:convert';
import 'dart:io';

/// Says which credentials the Firebase CLI will upload with, so the
/// confirmation screen can name them before anything is built.
class FirebaseAccountHelper {
  /// In the order the Firebase CLI picks them: a `FIREBASE_TOKEN`, the
  /// account `firebase login` signed in, then Application Default
  /// Credentials. Null when it has none of them.
  Future<String?> describe(Map<String, String> environment) async {
    if (_isSet(environment["FIREBASE_TOKEN"])) {
      return "FIREBASE_TOKEN environment variable";
    }

    final emails = await _loggedInEmails();
    if (emails.isNotEmpty) return "${emails.join(", ")} (firebase login)";

    final credentials = environment["GOOGLE_APPLICATION_CREDENTIALS"];
    if (_isSet(credentials)) return "service account in $credentials";

    return null;
  }

  Future<List<String>> _loggedInEmails() async {
    try {
      final result = await Process.run("firebase", [
        "login:list",
        "--json",
      ], runInShell: true);
      if (result.exitCode != 0) return const [];
      return parseLoginList("${result.stdout}");
    } catch (_) {
      return const [];
    }
  }

  /// The accounts in `firebase login:list --json` output.
  static List<String> parseLoginList(String output) {
    try {
      final json = jsonDecode(output);
      final accounts = json is Map ? json["result"] : null;
      if (accounts is! List) return const [];
      return [
        for (final account in accounts)
          if (account is Map &&
              account["user"] is Map &&
              account["user"]["email"] is String)
            account["user"]["email"] as String,
      ];
    } on FormatException {
      return const [];
    }
  }

  static bool _isSet(String? value) => value != null && value.trim().isNotEmpty;
}
