import 'dart:convert';

class AndroidAccountConfig {
  final String clientEmail;
  final String clientId;
  final String privateKey;

  bool get checkParameters =>
      clientEmail.isNotEmpty && clientId.isNotEmpty && privateKey.isNotEmpty;

  String? get showError {
    List<String> errorList = [];

    if (clientEmail.isEmpty) {
      errorList.add("client_email not found");
    }
    if (clientId.isEmpty) {
      errorList.add("client_id not found");
    }
    if (privateKey.isEmpty) {
      errorList.add("private_key not found");
    }

    return errorList.isEmpty ? null : errorList.join(', ');
  }

  AndroidAccountConfig({
    required this.clientEmail,
    required this.clientId,
    required this.privateKey,
  });

  factory AndroidAccountConfig.fromMap(Map<String, dynamic> map) {
    return AndroidAccountConfig(
      clientEmail: map['client_email'] ?? '',
      clientId: map['client_id'] ?? '',
      privateKey: map['private_key'] ?? '',
    );
  }

  factory AndroidAccountConfig.fromJson(String source) =>
      AndroidAccountConfig.fromMap(json.decode(source));
}
