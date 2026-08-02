import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's HackMD personal access token in the platform
/// keystore (Android Keystore-backed EncryptedSharedPreferences / iOS
/// Keychain) — it's a credential, not app preferences, so it doesn't belong
/// in plain SharedPreferences alongside theme/recent-docs state.
class HackmdAccount {
  static const _tokenKey = 'hackmd_api_token';
  static const _storage = FlutterSecureStorage();

  static Future<String?> getToken() => _storage.read(key: _tokenKey);

  static Future<void> setToken(String token) =>
      _storage.write(key: _tokenKey, value: token.trim());

  static Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
