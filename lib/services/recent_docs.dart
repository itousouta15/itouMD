import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum RecentDocSource { paste, file, url }

class RecentDoc {
  final String title;
  final String content;
  final RecentDocSource source;
  final String? sourceRef;
  final DateTime openedAt;

  const RecentDoc({
    required this.title,
    required this.content,
    required this.source,
    required this.openedAt,
    this.sourceRef,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'source': source.name,
    'sourceRef': sourceRef,
    'openedAt': openedAt.toIso8601String(),
  };

  factory RecentDoc.fromJson(Map<String, dynamic> json) => RecentDoc(
    title: json['title'] as String,
    content: json['content'] as String,
    source: RecentDocSource.values.firstWhere(
      (s) => s.name == json['source'],
      orElse: () => RecentDocSource.paste,
    ),
    sourceRef: json['sourceRef'] as String?,
    openedAt: DateTime.parse(json['openedAt'] as String),
  );
}

class RecentDocs {
  static const _key = 'recent_docs';
  static const maxEntries = 15;

  static Future<List<RecentDoc>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => RecentDoc.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<RecentDoc> docs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(docs.map((d) => d.toJson()).toList()),
    );
  }

  static Future<List<RecentDoc>> add(RecentDoc doc) async {
    final docs = await load();
    docs.removeWhere(
      (d) => d.title == doc.title && d.source == doc.source,
    );
    docs.insert(0, doc);
    if (docs.length > maxEntries) {
      docs.removeRange(maxEntries, docs.length);
    }
    await _save(docs);
    return docs;
  }

  static Future<List<RecentDoc>> remove(RecentDoc doc) async {
    final docs = await load();
    docs.removeWhere(
      (d) => d.title == doc.title && d.source == doc.source,
    );
    await _save(docs);
    return docs;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
