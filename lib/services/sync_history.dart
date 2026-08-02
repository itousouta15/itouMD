import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SyncAction { merged, overwrite }

/// One recorded sync push, kept for the history list.
class SyncEntry {
  final String noteId;
  final String? teamPath;
  final String title;
  final SyncAction action;
  final DateTime pushedAt;

  const SyncEntry({
    required this.noteId,
    this.teamPath,
    required this.title,
    required this.action,
    required this.pushedAt,
  });

  Map<String, dynamic> toJson() => {
    'noteId': noteId,
    'teamPath': teamPath,
    'title': title,
    'action': action.name,
    'pushedAt': pushedAt.toIso8601String(),
  };

  factory SyncEntry.fromJson(Map<String, dynamic> json) => SyncEntry(
    noteId: json['noteId'] as String,
    teamPath: json['teamPath'] as String?,
    title: json['title'] as String,
    action: SyncAction.values.firstWhere(
      (a) => a.name == json['action'],
      orElse: () => SyncAction.overwrite,
    ),
    pushedAt: DateTime.parse(json['pushedAt'] as String),
  );
}

/// The cloud content *before* the most recent push, kept so the sync can be
/// undone even across app restarts.
class UndoSlot {
  final String noteId;
  final String? teamPath;
  final String title;
  final String priorContent;
  final DateTime pushedAt;

  const UndoSlot({
    required this.noteId,
    this.teamPath,
    required this.title,
    required this.priorContent,
    required this.pushedAt,
  });

  Map<String, dynamic> toJson() => {
    'noteId': noteId,
    'teamPath': teamPath,
    'title': title,
    'priorContent': priorContent,
    'pushedAt': pushedAt.toIso8601String(),
  };

  factory UndoSlot.fromJson(Map<String, dynamic> json) => UndoSlot(
    noteId: json['noteId'] as String,
    teamPath: json['teamPath'] as String?,
    title: json['title'] as String,
    priorContent: json['priorContent'] as String,
    pushedAt: DateTime.parse(json['pushedAt'] as String),
  );
}

class SyncHistory {
  static const _historyKey = 'sync_history';
  static const _undoKey = 'sync_undo_slot';
  static const maxEntries = 50;

  static Future<List<SyncEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SyncEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(SyncEntry entry) async {
    final entries = await load();
    entries.insert(0, entry);
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  static Future<UndoSlot?> loadUndo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_undoKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UndoSlot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveUndo(UndoSlot slot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_undoKey, jsonEncode(slot.toJson()));
  }

  static Future<void> clearUndo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_undoKey);
  }
}
