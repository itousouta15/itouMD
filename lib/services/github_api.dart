import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

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

  /// `raw.githubusercontent.com/{owner}/{repo}/{ref}/{path}` — the Contents
  /// and README APIs both include this, and it's the only place the actual
  /// resolved ref (branch name or commit SHA) shows up when the caller
  /// asked for "the default branch" rather than a specific one. Used to
  /// resolve relative links/images inside the fetched content.
  final String? downloadUrl;

  const GithubFile({
    required this.path,
    required this.content,
    required this.sha,
    this.downloadUrl,
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

/// One entry from `GET /user/repos` — just enough to show a picker list.
class GithubRepoSummary {
  final String owner;
  final String name;
  final String? description;
  final bool private;

  const GithubRepoSummary({
    required this.owner,
    required this.name,
    this.description,
    required this.private,
  });

  String get fullName => '$owner/$name';

  factory GithubRepoSummary.fromJson(Map<String, dynamic> json) {
    final ownerJson = json['owner'] as Map<String, dynamic>?;
    return GithubRepoSummary(
      owner: ownerJson?['login'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      private: json['private'] as bool? ?? false,
    );
  }
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
    final detail = apiErrorDetail(res);
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

  static Future<http.Response> _request(Future<http.Response> Function() send) {
    return runApiRequest(send, const Duration(seconds: 20), () {
      throw GithubApiException('連不到 GitHub，檢查網路連線 (´;ω;`)');
    });
  }

  /// Decodes the Contents/README API's `content` field. GitHub always
  /// chunks this base64 string with a newline every 60 characters — Dart's
  /// `base64Decode` throws on embedded whitespace instead of ignoring it
  /// like most decoders, so it has to be stripped first.
  static String _decodeFileContent(String base64Content) {
    return utf8.decode(
      base64Decode(base64Content.replaceAll(RegExp(r'\s'), '')),
      allowMalformed: true,
    );
  }

  /// Parses a `github.com` URL into repo coordinates. Supports the blob
  /// view (`/blob/{branch}/{path}`) for a specific file; any other URL
  /// under that repo — the bare root, `/tree/...`, `/issues/...`, a
  /// trailing slash, whatever page you happened to copy the link from —
  /// resolves to the repo itself (README.md on the default branch), since
  /// pasting "the repo" is almost always what's meant. Returns null only
  /// when there isn't even an owner/repo to work with.
  static GithubFileRef? parseUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'github.com') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final owner = segments[0];
    final repo = segments[1];
    if (segments.length >= 4 && segments[2] == 'blob') {
      return GithubFileRef(
        owner: owner,
        repo: repo,
        branch: segments[3],
        path: segments.sublist(4).join('/'),
      );
    }
    return GithubFileRef(owner: owner, repo: repo);
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
      content: _decodeFileContent(content),
      sha: sha,
      downloadUrl: json['download_url'] as String?,
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

  /// Lists repos the authenticated user owns, collaborates on, or belongs
  /// to via an org — most-recently-updated first, for a "pick a repo"
  /// browser instead of typing `owner/repo` by hand.
  static Future<List<GithubRepoSummary>> listRepos(
    String token, {
    int page = 1,
    int perPage = 50,
  }) async {
    final res = await _request(
      () => http.get(
        Uri.parse(
          '$_base/user/repos?sort=updated&per_page=$perPage&page=$page',
        ),
        headers: _headers(token),
      ),
    );
    if (res.statusCode != 200) {
      throw GithubApiException(_errorMessage(res), res.statusCode);
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list
        .map((e) => GithubRepoSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetches a repo's README via GitHub's dedicated readme endpoint, which
  /// resolves the actual filename itself (`README.md`, `readme.md`,
  /// `README`, ...) — unlike the Contents API used by [getFile], which
  /// needs the exact case-sensitive path and 404s on a guess that's wrong.
  /// Works unauthenticated for public repos; pass [token] when available
  /// for private repos and higher rate limits.
  static Future<GithubFile> getReadme(
    GithubFileRef ref, {
    String? token,
    String? branch,
  }) async {
    final query = (branch ?? '').isNotEmpty ? '?ref=$branch' : '';
    final headers = token != null && token.isNotEmpty
        ? _headers(token)
        : {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'itouMD',
          };
    final res = await _request(
      () => http.get(
        Uri.parse('$_base/repos/${ref.owner}/${ref.repo}/readme$query'),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) {
      throw GithubApiException(_errorMessage(res), res.statusCode);
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final content = json['content'] as String? ?? '';
    final path = json['path'] as String? ?? ref.path;
    final sha = json['sha'] as String?;
    if (sha == null) {
      throw GithubApiException('讀不到檔案的 SHA (´;ω;`)');
    }
    return GithubFile(
      path: path,
      content: _decodeFileContent(content),
      sha: sha,
      downloadUrl: json['download_url'] as String?,
    );
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
