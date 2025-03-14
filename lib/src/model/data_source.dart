class DataSource {
  final String? path;
  final String? url;

  DataSource({
    this.path,
    this.url,
  });

  bool get hasPath => path != null;
  bool get hasUrl => url != null;
  bool get isEmpty => !hasPath && !hasUrl;

  @override
  String toString() {
    if (hasPath) return 'path: $path';
    if (hasUrl) return 'url: $url';
    return '';
  }
}
