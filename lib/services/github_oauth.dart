import 'dart:convert';

import 'package:http/http.dart' as http;

class GithubOAuthException implements Exception {
  final String message;

  GithubOAuthException(this.message);

  @override
  String toString() => message;
}

/// An active GitHub device-flow session: the user opens [verificationUri],
/// types [userCode], and the app polls [GithubOAuth.pollForToken] until the
/// authorization completes.
class GithubOAuthSession {
  final String clientId;
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int interval;

  const GithubOAuthSession({
    required this.clientId,
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
  });
}

/// GitHub OAuth Device Flow — the account-login path that replaces pasting
/// a Personal Access Token. Works for public OAuth apps without a client
/// secret; the access token it yields is used exactly like a PAT
/// (`Authorization: Bearer`).
class GithubOAuth {
  /// The app's registered GitHub OAuth App client id (public by design —
  /// device flow needs no secret). Overridable at build time with
  /// `--dart-define=GITHUB_CLIENT_ID=...`.
  static const clientId = String.fromEnvironment(
    'GITHUB_CLIENT_ID',
    defaultValue: 'Ov23liM02CBR2iKAK387',
  );

  static bool get isConfigured => clientId.isNotEmpty;

  static Future<GithubOAuthSession> startDeviceFlow() async {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('https://github.com/login/device/code'),
            headers: {'Accept': 'application/json'},
            body: {'client_id': clientId, 'scope': 'repo'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw GithubOAuthException('連不到 GitHub，檢查網路連線 (´;ω;`)');
    }
    if (res.statusCode != 200) {
      throw GithubOAuthException(_error(res));
    }
    final json = _decode(res);
    final deviceCode = json['device_code'] as String?;
    final userCode = json['user_code'] as String?;
    final verificationUri = json['verification_uri'] as String?;
    if (deviceCode == null || userCode == null || verificationUri == null) {
      throw GithubOAuthException('GitHub 回傳格式錯誤，請稍後再試 (´;ω;`)');
    }
    return GithubOAuthSession(
      clientId: clientId,
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      interval: (json['interval'] as num?)?.toInt() ?? 5,
    );
  }

  /// Polls for the access token until the user authorizes. Returns the
  /// token on success; throws on denial/timeout. [isCancelled] is checked
  /// between polls so the UI can abort without leaving a dangling loop.
  static Future<String> pollForToken(
    GithubOAuthSession session, {
    required bool Function() isCancelled,
  }) async {
    var interval = session.interval;
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled()) {
        throw GithubOAuthException('已取消登入');
      }
      await Future<void>.delayed(Duration(seconds: interval));
      if (isCancelled()) {
        throw GithubOAuthException('已取消登入');
      }

      final http.Response res;
      try {
        res = await http
            .post(
              Uri.parse('https://github.com/login/oauth/access_token'),
              headers: {'Accept': 'application/json'},
              body: {
                'client_id': session.clientId,
                'device_code': session.deviceCode,
                'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
              },
            )
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        // A single failed request (a transient blip, or the OS throttling
        // background network while the user is off in the browser
        // approving) isn't fatal — keep polling like `authorization_pending`
        // instead of aborting the whole 15-minute window. If the network is
        // genuinely down for the whole window, the deadline below still
        // surfaces as a timeout.
        continue;
      }
      if (res.statusCode != 200) {
        throw GithubOAuthException(_error(res));
      }

      final json = _decode(res);
      final token = json['access_token'] as String?;
      if (token != null && token.isNotEmpty) return token;

      final error = json['error'] as String?;
      switch (error) {
        case 'authorization_pending':
          break; // keep polling
        case 'slow_down':
          interval += 5; // GitHub asks us to slow down
        case 'expired_token':
          throw GithubOAuthException('授權碼已過期，請重新開始 (´;ω;`)');
        case 'access_denied':
          throw GithubOAuthException('你在 GitHub 上拒絕了授權 (´;ω;`)');
        default:
          throw GithubOAuthException('GitHub 回傳錯誤：${error ?? '未知'} (´;ω;`)');
      }
    }
    throw GithubOAuthException('授權逾時，請重新開始 (´;ω;`)');
  }

  static Map<String, dynamic> _decode(http.Response res) {
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw GithubOAuthException('GitHub 回傳格式錯誤 (´;ω;`)');
    }
  }

  static String _error(http.Response res) {
    String? detail;
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is Map && json['error_description'] is String) {
        detail = json['error_description'] as String;
      }
    } catch (_) {}
    final base = switch (res.statusCode) {
      401 => 'GitHub 認證失敗 (´;ω;`)',
      404 => '找不到這個 OAuth App（client_id 有誤？）(´;ω;`)',
      _ => 'GitHub 發生錯誤，HTTP ${res.statusCode} (´;ω;`)',
    };
    if (detail != null && detail.isNotEmpty) return '$base（$detail）';
    return base;
  }
}
