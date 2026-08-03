import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's GitHub Personal Access Token in the platform
/// keystore (same pattern as [HackmdAccount]).
class GithubAccount {
  static const _tokenKey = 'github_pat';
  static const _storage = FlutterSecureStorage();

  static Future<String?> getToken() => _storage.read(key: _tokenKey);

  static Future<void> setToken(String token) =>
      _storage.write(key: _tokenKey, value: token.trim());

  static Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
