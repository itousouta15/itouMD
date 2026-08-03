import 'dart:convert';

import 'package:http/http.dart' as http;

class LlmException implements Exception {
  final String message;

  LlmException(this.message);

  @override
  String toString() => message;
}

/// Minimal OpenAI-compatible chat client for the editor's AI assistant.
/// Without a user API key it talks to the app's own proxy (the built-in
/// free quota), which forwards to DeepSeek's cheapest model server-side.
class LlmClient {
  static const systemPrompt = '你是一個繁體中文的 Markdown 寫作助手。直接輸出結果，不要任何額外說明或前綴。';

  static Future<String> complete({
    required String baseUrl,
    required String model,
    String? apiKey,
    required String userPrompt,
    double temperature = 0.7,
  }) async {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              if (apiKey != null && apiKey.isNotEmpty)
                'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
              'temperature': temperature,
            }),
          )
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw LlmException('連不到 AI 服務，檢查網路或設定 (´;ω;`)');
    }
    if (res.statusCode != 200) {
      throw LlmException(_errorMessage(res));
    }
    try {
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final choices = json['choices'] as List? ?? const [];
      if (choices.isEmpty) throw LlmException('AI 沒有回應 (´;ω;`)');
      final content =
          (choices.first as Map<String, dynamic>)['message']?['content']
              as String?;
      if (content == null || content.trim().isEmpty) {
        throw LlmException('AI 沒有回應 (´;ω;`)');
      }
      return content.trim();
    } on LlmException {
      rethrow;
    } catch (_) {
      throw LlmException('AI 回應格式無法解析 (´;ω;`)');
    }
  }

  static String _errorMessage(http.Response res) {
    String? detail;
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is Map) {
        final error = json['error'];
        if (error is Map && error['message'] is String) {
          detail = error['message'] as String;
        } else if (json['message'] is String) {
          detail = json['message'] as String;
        }
      }
    } catch (_) {}
    final fallback = switch (res.statusCode) {
      401 => 'API Key 無效，檢查設定 (´;ω;`)',
      402 || 429 => '免費額度已用完，請稍後再試或設定自己的 API Key (´;ω;`)',
      500 => 'AI 服務暫時出問題，稍後再試 (´;ω;`)',
      _ => 'AI 服務發生錯誤，HTTP ${res.statusCode} (´;ω;`)',
    };
    if (detail != null && detail.isNotEmpty) return '$fallback（$detail）';
    return fallback;
  }
}
