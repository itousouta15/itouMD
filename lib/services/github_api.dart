import 'dart:convert';

import 'package:http/http.dart' as http;

class GithubApiException implements Exception {
  final String message;
  final int? statusCode;

  GithubApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// A file inside a GitHub repo, as addressed by the Contents API.
class GithubFile {
  final String path;
  final String content;
  final String sha;

  const GithubFile({
    required this.path,
    required this.content,
    required this.sha,
  });
}

/// A parsed `github.com` URL: repo coordinates plus (when given) the
/// branch and file path. `branch`/`path` may need resolving — a bare
/// `github.com/{owner}/{repo}` URL means README.md on the default branch.
class GithubFileRef {
  final String owner;
  final String repo;
  final String branch;
  final String path;

  const GithubFileRef({
    required this.owner,
    required this.repo,
    this.branch = '',
    this.path = 'README.md',
  });

  String get displayName => '$owner/$repo:${path.split('/').last}';
}

/// Thin client for the GitHub REST API (Contents + repo metadata), used to
/// write local edits back to files that were opened from `github.com` URLs.
class GithubApi {
  static const _base = 'https://api.github.com';

  static Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    // GitHub rejects requests without a User-Agent header.
    'User-Agent': 'itouMD',
  };

  static String _errorMessage(http.Response res) {
    String? detail;
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is Map && json['message'] is String) {
        detail = json['message'] as String;
      }
    } catch (_) {}
    final base = switch (res.statusCode) {
      401 => 'Token 無效或已過期，請重新設定 (´;ω;`)',
      403 => '沒有這個 repo 的寫入權限（或配額限制）(´;ω;`)',
      404 => '找不到這個檔案或 repo (´;ω;`)',
      409 => '檔案在別處被改過了，需要先合併 (´;ω;`)',
      _ => 'GitHub 發生錯誤，HTTP ${res.statusCode}',
    };
    if (detail != null && detail.isNotEmpty) return '$base（$detail）';
    return base;
  }

  static Future<http.Response> _request(
    Future<http.Response> Function() send,
  ) async {
    final http.Response res;
    try {
      res = await send().timeout(const Duration(seconds: 20));
    } catch (_) {
      throw GithubApiException('連不到 GitHub，檢查網路連線 (´;ω;`)');
    }
    return res;
  }

  /// Parses a `github.com` URL into repo coordinates. Supports the blob
  /// view (`/blob/{branch}/{path}`) and a bare repo URL (README.md on the
  /// default branch). Returns null for anything else.
  static GithubFileRef? parseUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'github.com') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final owner = segments[0];
    final repo = segments[1];
    if (segments.length == 2) {
      return GithubFileRef(owner: owner, repo: repo);
    }
    if (segments.length >= 4 && segments[2] == 'blob') {
      return GithubFileRef(
        owner: owner,
        repo: repo,
        branch: segments[3],
        path: segments.sublist(4).join('/'),
      );
    }
    return null;
  }

  /// Resolves the default branch of a repo.
  static Future<String> getDefaultBranch(
    String token,
    String owner,
    String repo,
  ) async {
    final res = await _request(
      () => http.get(
        Uri.parse('$_base/repos/$owner/$repo'),
        headers: _headers(token),
      ),
    );
    if (res.statusCode != 200) {
      throw GithubApiException(_errorMessage(res), res.statusCode);
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final branch = json['default_branch'] as String?;
    if (branch == null || branch.isEmpty) {
      throw GithubApiException('讀不到 repo 的預設分支 (´;ω;`)');
    }
    return branch;
  }

  /// Fetches a file's content (base64-decoded) and its SHA for later
  /// write-back. Throws [GithubApiException] when the file doesn't exist.
  static Future<GithubFile> getFile(
    String token,
    GithubFileRef ref, {
    String? branch,
  }) async {
    final actualBranch = ref.branch.isNotEmpty
        ? ref.branch
        : branch ?? await getDefaultBranch(token, ref.owner, ref.repo);
    final res = await _request(
      () => http.get(
        Uri.parse(
          '$_base/repos/${ref.owner}/${ref.repo}/contents/${ref.path}'
          '?ref=$actualBranch',
        ),
        headers: _headers(token),
      ),
    );
    if (res.statusCode != 200) {
      throw GithubApiException(_errorMessage(res), res.statusCode);
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final content = json['content'] as String? ?? '';
    final sha = json['sha'] as String?;
    if (sha == null) {
      throw GithubApiException('讀不到檔案的 SHA (´;ω;`)');
    }
    return GithubFile(
      path: ref.path,
      content: utf8.decode(base64Decode(content), allowMalformed: true),
      sha: sha,
    );
  }

  /// Writes [content] back via the Contents API, carrying [sha] so a
  /// concurrent change fails with 409 instead of being silently overwritten.
  static Future<void> updateFile(
    String token,
    GithubFileRef ref,
    String content, {
    required String sha,
    String? branch,
    String message = '編輯自 itouMD',
  }) async {
    final actualBranch = ref.branch.isNotEmpty
        ? ref.branch
        : branch ?? await getDefaultBranch(token, ref.owner, ref.repo);
    final res = await _request(
      () => http.put(
        Uri.parse('$_base/repos/${ref.owner}/${ref.repo}/contents/${ref.path}'),
        headers: _headers(token),
        body: jsonEncode({
          'message': message,
          'content': base64Encode(utf8.encode(content)),
          'sha': sha,
          'branch': actualBranch,
        }),
      ),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw GithubApiException(_errorMessage(res), res.statusCode);
    }
  }

  /// Fetches the authenticated user's login — used to test a stored PAT.
  static Future<String> getAuthenticatedUser(String token) async {
    final res = await _request(
      () => http.get(Uri.parse('$_base/user'), headers: _headers(token)),
    );
    if (res.statusCode != 200) {
      throw GithubApiException(_errorMessage(res), res.statusCode);
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return json['login'] as String? ?? '(未知帳號)';
  }
}
