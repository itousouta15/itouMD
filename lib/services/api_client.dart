import 'dart:convert';

import 'package:http/http.dart' as http;

/// Extracts a `message` field from a JSON error body, if present — the
/// common shape GitHub-style REST error responses use.
String? apiErrorDetail(http.Response res) {
  try {
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is Map && json['message'] is String) {
      return json['message'] as String;
    }
  } catch (_) {}
  return null;
}

/// Runs [send] with [timeout], calling [onNetworkError] — which must throw
/// — when the request itself fails (DNS, timeout, no connection; never a
/// non-2xx response). Shared by [GithubApi] and [HackmdApi]'s per-call
/// request wrappers, whose only real difference is which exception type
/// they throw.
Future<http.Response> runApiRequest(
  Future<http.Response> Function() send,
  Duration timeout,
  Never Function() onNetworkError,
) async {
  try {
    return await send().timeout(timeout);
  } catch (_) {
    onNetworkError();
  }
}
