import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI assistant settings. Defaults to the built-in free quota (the app's
/// Cloudflare Worker proxy in front of DeepSeek's cheapest model); users
/// can switch to their own OpenAI-compatible endpoint + API key.
class LlmPrefs {
  static const _useBuiltinKey = 'llm_use_builtin';
  static const _baseUrlKey = 'llm_base_url';
  static const _modelKey = 'llm_model';
  static const _apiKeyKey = 'llm_api_key';
  static const _storage = FlutterSecureStorage();

  /// The app's own proxy endpoint (Cloudflare Worker) used when the user
  /// hasn't configured their own API key. Rate-limited per IP.
  static const builtinBaseUrl = 'https://llm.itousouta.me';
  static const builtinModel = 'deepseek-v4-flash-free';
  static const defaultBaseUrl = 'https://api.openai.com/v1';
  static const defaultModel = 'gpt-4o-mini';

  static Future<bool> get useBuiltin async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useBuiltinKey) ?? true;
  }

  static Future<void> setUseBuiltin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useBuiltinKey, value);
  }

  static Future<String?> get baseUrl async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_baseUrlKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return (await useBuiltin) ? builtinBaseUrl : defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, value.trim());
  }

  static Future<String?> get model async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modelKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return (await useBuiltin) ? builtinModel : defaultModel;
  }

  static Future<void> setModel(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelKey, value.trim());
  }

  static Future<String?> get apiKey => _storage.read(key: _apiKeyKey);

  static Future<void> setApiKey(String value) =>
      _storage.write(key: _apiKeyKey, value: value.trim());

  static Future<void> clearApiKey() => _storage.delete(key: _apiKeyKey);
}
