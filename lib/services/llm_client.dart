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
/// free quota), which forwards to OpenCode Zen's free models server-side.
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

  /// Streaming variant for the free-conversation tab: sends `stream: true`,
  /// parses the SSE reply and hands each content delta to [onDelta] as it
  /// arrives. Returns the full assembled reply. [extraSystem] is appended to
  /// the system prompt — the chat tab uses it to inject the document context
  /// so the model knows what the user is talking about.
  static Future<String> completeStream({
    required String baseUrl,
    required String model,
    String? apiKey,
    required List<({String role, String content})> messages,
    double temperature = 0.7,
    String? extraSystem,
    required void Function(String delta) onDelta,
  }) async {
    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/chat/completions'),
    );
    request.headers['Content-Type'] = 'application/json';
    if (apiKey != null && apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }
    final system = extraSystem == null || extraSystem.isEmpty
        ? systemPrompt
        : '$systemPrompt\n\n$extraSystem';
    request.body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        ...messages.map((m) => {'role': m.role, 'content': m.content}),
      ],
      'temperature': temperature,
      'stream': true,
    });

    final http.StreamedResponse streamed;
    try {
      streamed = await http.Client()
          .send(request)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw LlmException('連不到 AI 服務，檢查網路或設定 (´;ω;`)');
    }
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw LlmException(_errorMessageFromBody(streamed.statusCode, body));
    }

    final full = StringBuffer();
    var buffer = '';
    try {
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        buffer += chunk;
        var newline = buffer.indexOf('\n');
        while (newline >= 0) {
          final line = buffer.substring(0, newline).trim();
          buffer = buffer.substring(newline + 1);
          if (line.startsWith('data:')) {
            final data = line.substring(5).trim();
            if (data != '[DONE]') {
              _consumeSseData(data, full, onDelta);
            }
          }
          newline = buffer.indexOf('\n');
        }
      }
    } catch (_) {
      throw LlmException('AI 連線中斷，再試一次看看 (´;ω;`)');
    }
    final result = full.toString().trim();
    if (result.isEmpty) throw LlmException('AI 沒有回應 (´;ω;`)');
    return result;
  }

  static void _consumeSseData(
    String data,
    StringBuffer full,
    void Function(String delta) onDelta,
  ) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final choices = json['choices'] as List? ?? const [];
      if (choices.isEmpty) return;
      final delta = (choices.first as Map<String, dynamic>)['delta'];
      if (delta is Map && delta['content'] is String) {
        final piece = delta['content'] as String;
        full.write(piece);
        onDelta(piece);
      }
    } catch (_) {
      // Malformed line — skip; the stream continues.
    }
  }

  static String _errorMessage(http.Response res) => _errorMessageFromBody(
    res.statusCode,
    utf8.decode(res.bodyBytes, allowMalformed: true),
  );

  static String _errorMessageFromBody(int statusCode, String body) {
    String? detail;
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final error = json['error'];
        if (error is Map && error['message'] is String) {
          detail = error['message'] as String;
        } else if (json['message'] is String) {
          detail = json['message'] as String;
        }
      }
    } catch (_) {}
    final fallback = switch (statusCode) {
      401 => 'API Key 無效，檢查設定 (´;ω;`)',
      402 || 429 => '免費額度已用完，請稍後再試或設定自己的 API Key (´;ω;`)',
      500 => 'AI 服務暫時出問題，稍後再試 (´;ω;`)',
      _ => 'AI 服務發生錯誤，HTTP $statusCode (´;ω;`)',
    };
    if (detail != null && detail.isNotEmpty) return '$fallback（$detail）';
    return fallback;
  }
}
