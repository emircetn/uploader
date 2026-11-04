class PathUtils {
  const PathUtils._();

  /// [path] with a leading `~` expanded to the home folder and a relative
  /// path resolved against [projectRoot]. Throws a [StateError] for a `~`
  /// path when [environment] names no home folder.
  static String resolve(
    String path, {
    required String projectRoot,
    required Map<String, String> environment,
  }) {
    var resolved = path;
    if (resolved == "~" || resolved.startsWith("~/")) {
      final home = environment["HOME"] ?? environment["USERPROFILE"];
      if (home == null) {
        throw StateError("$path cannot be resolved without HOME");
      }
      resolved = "$home${resolved.substring(1)}";
    }
    return resolved.startsWith("/") ? resolved : "$projectRoot/$resolved";
  }
}
