import 'dart:convert';

final class IosAccountConfig {
  final String authKey;
  final String issuerId;

  bool get checkParameters => authKey.isNotEmpty && issuerId.isNotEmpty;

  String? get showError {
    List<String> errorList = [];

    if (authKey.isEmpty) {
      errorList.add("auth_key not found");
    }
    if (issuerId.isEmpty) {
      errorList.add("issuer_id not found");
    }

    return errorList.isEmpty ? null : errorList.join(',');
  }

  IosAccountConfig({required this.authKey, required this.issuerId});

  factory IosAccountConfig.fromMap(Map<String, dynamic> map) {
    return IosAccountConfig(
      authKey: map['auth_key'] ?? '',
      issuerId: map['issuer_id'] ?? '',
    );
  }

  factory IosAccountConfig.fromJson(String source) =>
      IosAccountConfig.fromMap(json.decode(source));
}
