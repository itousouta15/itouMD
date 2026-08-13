import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

class HackmdApiException implements Exception {
  final String message;
  final int? statusCode;

  HackmdApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class HackmdUser {
  final String? name;
  final String? email;

  const HackmdUser({this.name, this.email});

  factory HackmdUser.fromJson(Map<String, dynamic> json) => HackmdUser(
    name: json['name'] as String?,
    email: json['email'] as String?,
  );
}

class HackmdNote {
  final String id;
  final String content;
  final String? title;
  final String? permalink;
  final String? userPath;
  final String? teamPath;

  const HackmdNote({
    required this.id,
    required this.content,
    this.title,
    this.permalink,
    this.userPath,
    this.teamPath,
  });

  factory HackmdNote.fromJson(Map<String, dynamic> json) => HackmdNote(
    id: json['id'] as String,
    content: json['content'] as String? ?? '',
    title: json['title'] as String?,
    permalink: json['permalink'] as String?,
    userPath: json['userPath'] as String?,
    teamPath: json['teamPath'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'title': title,
    'permalink': permalink,
    'userPath': userPath,
    'teamPath': teamPath,
  };
}

class HackmdTeam {
  final String id;
  final String path;
  final String? name;

  const HackmdTeam({required this.id, required this.path, this.name});

  factory HackmdTeam.fromJson(Map<String, dynamic> json) => HackmdTeam(
    id: json['id'] as String? ?? '',
    // `path` is the identifier the team endpoints actually accept
    // (`/v1/teams/{teamPath}/notes`); `id` is a UUID that 404s there.
    path: (json['path'] as String?) ?? (json['name'] as String?) ?? '',
    name: json['name'] as String?,
  );

  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'name': name};

  /// The `@slug` used in `hackmd.io/@slug/...` note URLs — the same value
  /// the API wants in `/v1/teams/{teamPath}/...`.
  String get urlSlug {
    final slug = path.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    return slug.startsWith('@') ? slug.substring(1) : slug;
  }
}

/// The outcome of [HackmdApi.resolveNoteId]: the note's id plus, when the
/// note lives in a team workspace, that team's `path` — the two together
/// pick the right read/update endpoint.
class ResolvedNote {
  final String noteId;
  final String? teamPath;

  const ResolvedNote({required this.noteId, this.teamPath});
}

/// Thin client for HackMD's official REST API (`api.hackmd.io/v1`), used to
/// push local edits back to the note they came from.
///
/// The field names here follow HackMD's documented API shape
/// (https://hackmd.io/@docs/Getting-Started-with-the-HackMD-API — the full
/// Swagger reference is JS-rendered and couldn't be scraped for exact
/// schemas), but haven't been exercised against a live token during
/// development. If a real response doesn't parse as expected, the error
/// surfaced to the UI includes the raw HTTP status so it's diagnosable from
/// the device without needing to hand a token to anyone else.
class HackmdApi {
  static const _base = 'https://api.hackmd.io/v1';

  static Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  static String _errorMessage(http.Response res) {
    switch (res.statusCode) {
      case 401:
        return 'Token 無效或已過期，請重新設定 (´;ω;`)';
      case 403:
        return '沒有這篇筆記的編輯權限 (´;ω;`)';
      case 404:
        return '在你的 HackMD 帳號裡找不到這篇筆記 (´;ω;`)';
      case 429:
        return 'HackMD 請求太頻繁了，稍後再試 (´;ω;`)';
      default:
        return 'HackMD 發生錯誤，HTTP ${res.statusCode} (´;ω;`)';
    }
  }

  static Never _networkError() =>
      throw HackmdApiException('連不到 HackMD，檢查網路連線 (´;ω;`)');

  static Future<HackmdUser> getMe(String token) async {
    final res = await runApiRequest(
      () => http.get(Uri.parse('$_base/me'), headers: _headers(token)),
      const Duration(seconds: 15),
      _networkError,
    );
    if (res.statusCode != 200) {
      throw HackmdApiException(_errorMessage(res), res.statusCode);
    }
    return HackmdUser.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  static Future<List<HackmdNote>> listNotes(String token) async {
    final res = await runApiRequest(
      () => http.get(Uri.parse('$_base/notes'), headers: _headers(token)),
      const Duration(seconds: 20),
      _networkError,
    );
    if (res.statusCode != 200) {
      throw HackmdApiException(_errorMessage(res), res.statusCode);
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list
        .map((e) => HackmdNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<HackmdNote> getNote(String token, String noteId) async {
    final res = await _get('$_base/notes/$noteId', token);
    return HackmdNote.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  static Future<List<HackmdTeam>> listTeams(String token) async {
    final res = await _get('$_base/teams', token);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list
        .map((e) => HackmdTeam.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<HackmdNote>> listTeamNotes(
    String token,
    String teamPath,
  ) async {
    final res = await _get('$_base/teams/$teamPath/notes', token);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list
        .map((e) => HackmdNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<HackmdNote> getTeamNote(
    String token,
    String teamPath,
    String noteId,
  ) async {
    final res = await _get('$_base/teams/$teamPath/notes/$noteId', token);
    return HackmdNote.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  static Future<http.Response> _get(String path, String token) async {
    final res = await runApiRequest(
      () => http.get(Uri.parse(path), headers: _headers(token)),
      const Duration(seconds: 20),
      _networkError,
    );
    if (res.statusCode != 200) {
      throw HackmdApiException(_errorMessage(res), res.statusCode);
    }
    return res;
  }

  static Future<void> _patchNote(
    String path,
    String token,
    String content,
  ) async {
    final res = await runApiRequest(
      () => http.patch(
        Uri.parse(path),
        headers: _headers(token),
        body: jsonEncode({'content': content}),
      ),
      const Duration(seconds: 20),
      _networkError,
    );
    if (res.statusCode != 200 && res.statusCode != 202) {
      throw HackmdApiException(_errorMessage(res), res.statusCode);
    }
  }

  static Future<void> updateNoteContent(
    String token,
    String noteId,
    String content,
  ) {
    return _patchNote('$_base/notes/$noteId', token, content);
  }

  static Future<void> updateTeamNoteContent(
    String token,
    String teamPath,
    String noteId,
    String content,
  ) {
    return _patchNote('$_base/teams/$teamPath/notes/$noteId', token, content);
  }

  /// Creates a personal note on the official HackMD API (`POST /notes`).
  /// Returns the created note; the UI falls back to a local draft on any
  /// failure, since this endpoint may reject some tokens/plans.
  static Future<HackmdNote> createNote(
    String token,
    String content, {
    String readPermission = 'owner',
    String writePermission = 'owner',
  }) async {
    final res = await runApiRequest(
      () => http.post(
        Uri.parse('$_base/notes'),
        headers: _headers(token),
        body: jsonEncode({
          'content': content,
          'readPermission': readPermission,
          'writePermission': writePermission,
        }),
      ),
      const Duration(seconds: 20),
      _networkError,
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw HackmdApiException(_errorMessage(res), res.statusCode);
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return HackmdNote.fromJson(json);
  }

  /// Creates a note inside a team workspace (`POST /teams/{teamPath}/notes`).
  static Future<HackmdNote> createTeamNote(
    String token,
    String teamPath,
    String content, {
    String readPermission = 'owner',
    String writePermission = 'owner',
  }) async {
    final res = await runApiRequest(
      () => http.post(
        Uri.parse('$_base/teams/$teamPath/notes'),
        headers: _headers(token),
        body: jsonEncode({
          'content': content,
          'readPermission': readPermission,
          'writePermission': writePermission,
        }),
      ),
      const Duration(seconds: 20),
      _networkError,
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw HackmdApiException(_errorMessage(res), res.statusCode);
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return HackmdNote.fromJson(json);
  }

  /// Resolves the API `noteId` (and team path, when relevant) for a
  /// `hackmd.io` note URL. A canonical URL (`hackmd.io/<id>`) already has
  /// the id as its only path segment; a custom-aliased one
  /// (`hackmd.io/@user/alias`, or a team note `hackmd.io/@team/alias`)
  /// doesn't — the alias isn't the real id, so it has to be found by listing
  /// the account's notes and matching on `permalink`. The personal notes
  /// list only covers the personal workspace, so a URL whose first segment
  /// is a team path resolves against that team's note list only. Returns
  /// `null` if no match is found (e.g. the note belongs to someone else's
  /// account), and never throws for a non-matching URL — a failed team
  /// lookup counts as "no match".
  static Future<ResolvedNote?> resolveNoteId(
    String token,
    Uri hackmdUrl,
  ) async {
    final segments = hackmdUrl.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    if (segments.length == 1 && !segments[0].startsWith('@')) {
      return ResolvedNote(noteId: segments[0]);
    }

    final alias = segments.last;
    final notes = await listNotes(token);
    for (final note in notes) {
      if (note.permalink == alias || note.id == alias) {
        return ResolvedNote(noteId: note.id);
      }
    }

    if (segments.length >= 2 && segments[0].startsWith('@')) {
      final wantedPath = segments[0].substring(1);
      final teams = await listTeams(token);
      for (final team in teams) {
        if (team.path != wantedPath) continue;
        try {
          final teamNotes = await listTeamNotes(token, team.path);
          for (final note in teamNotes) {
            if (note.permalink == alias || note.id == alias) {
              return ResolvedNote(noteId: note.id, teamPath: team.path);
            }
          }
        } on HackmdApiException {
          // Team lookup failed — the note isn't resolvable, not an error
          // worth aborting the whole sync for.
        }
        return null;
      }
    }
    return null;
  }
}
