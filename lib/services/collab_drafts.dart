import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'collab_api.dart';

class CollabDraft {
  final CollabEndpoint endpoint;
  final String text;
  final CollabSnapshot? base;
  final DateTime updatedAt;

  const CollabDraft({
    required this.endpoint,
    required this.text,
    required this.base,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'server': endpoint.server.toString(),
    'room': endpoint.room,
    'text': text,
    'base': base?.toJson(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CollabDraft.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('Unknown draft format');
    }
    final endpoint = CollabEndpoint.parse(
      json['server'] as String,
      json['room'] as String,
    );
    return CollabDraft(
      endpoint: endpoint,
      text: json['text'] as String,
      base: json['base'] == null
          ? null
          : CollabSnapshot.fromJson(json['base'], endpoint.room),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// One checked preference write holds draft AND base revision/content together.
/// No eviction via RecentDocs; endpoint + exact room identify each independent draft.
class CollabDraftStore {
  static const prefix = 'collab_draft_v1_';

  Future<CollabDraft?> load(CollabEndpoint endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$prefix${endpoint.key}');
    if (raw == null) return null;
    try {
      final draft = CollabDraft.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (draft.endpoint.key != endpoint.key) throw const FormatException();
      return draft;
    } catch (_) {
      throw const CollabException('本機協作草稿無法讀取。原始資料已保留，請勿清除應用程式資料。');
    }
  }

  Future<({List<CollabDraft> drafts, int unreadable})> list() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = <CollabDraft>[];
    var unreadable = 0;
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      try {
        final draft = CollabDraft.fromJson(
          jsonDecode(prefs.getString(key)!) as Map<String, dynamic>,
        );
        if ('$prefix${draft.endpoint.key}' != key) {
          throw const FormatException();
        }
        drafts.add(draft);
      } catch (_) {
        unreadable++;
      }
    }
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return (drafts: drafts, unreadable: unreadable);
  }

  Future<void> save(CollabDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      '$prefix${draft.endpoint.key}',
      jsonEncode(draft.toJson()),
    )) {
      throw const CollabException('本機草稿儲存失敗。請重試或先另存新檔。');
    }
  }
}
