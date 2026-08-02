import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'hackmd_api.dart';

/// A cached HackMD note's full content, keyed by the source URL it was
/// opened from (`hackmd.io/...`), so offline fallback works even when the
/// note id can't be resolved without the network.
class CachedNote {
  final String ref;
  final String title;
  final String content;
  final DateTime savedAt;

  const CachedNote({
    required this.ref,
    required this.title,
    required this.content,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'title': title,
    'content': content,
    'savedAt': savedAt.toIso8601String(),
  };

  factory CachedNote.fromJson(Map<String, dynamic> json) => CachedNote(
    ref: json['ref'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    savedAt: DateTime.parse(json['savedAt'] as String),
  );
}

/// Snapshot of the "browse my notes" list so the list stays usable offline.
class NoteListSnapshot {
  final List<HackmdNote> personal;
  final List<HackmdTeam> teams;
  final Map<String, List<HackmdNote>> teamNotes;
  final DateTime savedAt;

  const NoteListSnapshot({
    required this.personal,
    required this.teams,
    required this.teamNotes,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'personal': personal.map((n) => n.toJson()).toList(),
    'teams': teams.map((t) => t.toJson()).toList(),
    'teamNotes': teamNotes.map(
      (key, value) => MapEntry(key, value.map((n) => n.toJson()).toList()),
    ),
    'savedAt': savedAt.toIso8601String(),
  };

  factory NoteListSnapshot.fromJson(Map<String, dynamic> json) =>
      NoteListSnapshot(
        personal: (json['personal'] as List)
            .map((e) => HackmdNote.fromJson(e as Map<String, dynamic>))
            .toList(),
        teams: (json['teams'] as List)
            .map((e) => HackmdTeam.fromJson(e as Map<String, dynamic>))
            .toList(),
        teamNotes: (json['teamNotes'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            key,
            (value as List)
                .map((e) => HackmdNote.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
        ),
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}

/// Offline cache for HackMD data: note contents (keyed by source URL) and
/// the browse-list snapshot. Bounded — the newest [maxNotes] notes are kept
/// and the total payload is capped so SharedPreferences stays lean.
class NoteCache {
  static const _notesKey = 'note_cache_notes';
  static const _listKey = 'note_cache_list';
  static const maxNotes = 20;
  static const maxTotalBytes = 400 * 1024;

  static Future<List<CachedNote>> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => CachedNote.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveNotes(List<CachedNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notesKey,
      jsonEncode(notes.map((n) => n.toJson()).toList()),
    );
  }

  static Future<CachedNote?> loadNote(String ref) async {
    final notes = await _loadNotes();
    for (final note in notes) {
      if (note.ref == ref) return note;
    }
    return null;
  }

  /// Upserts the note content for [ref]; evicts the oldest entries when the
  /// cache grows past [maxNotes] or [maxTotalBytes].
  static Future<void> saveNote(String ref, String title, String content) async {
    final notes = await _loadNotes();
    notes.removeWhere((n) => n.ref == ref);
    notes.insert(
      0,
      CachedNote(
        ref: ref,
        title: title,
        content: content,
        savedAt: DateTime.now(),
      ),
    );
    while (notes.length > maxNotes) {
      notes.removeLast();
    }
    var bytes = jsonEncode(notes.map((n) => n.toJson()).toList()).length;
    while (bytes > maxTotalBytes && notes.length > 1) {
      notes.removeLast();
      bytes = jsonEncode(notes.map((n) => n.toJson()).toList()).length;
    }
    await _saveNotes(notes);
  }

  static Future<NoteListSnapshot?> loadList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return NoteListSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveList(NoteListSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_listKey, jsonEncode(snapshot.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_notesKey);
    await prefs.remove(_listKey);
  }
}
