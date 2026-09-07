class AppDetail {
  final String appName;
  final String buildVersion;

  final String? buildNumber;

  AppDetail({
    required this.appName,
    required this.buildVersion,
    this.buildNumber,
  });
}
