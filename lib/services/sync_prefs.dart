import 'package:shared_preferences/shared_preferences.dart';

enum ConflictResolution { ask, overwrite, cancel }

class SyncPrefs {
  static const _autoRefreshKey = 'auto_refresh_on_open';
  static const _conflictKey = 'conflict_resolution';

  static Future<bool> get autoRefreshOnOpen async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoRefreshKey) ?? true;
  }

  static Future<void> setAutoRefreshOnOpen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoRefreshKey, value);
  }

  static Future<ConflictResolution> get conflictResolution async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_conflictKey) ?? 0;
    if (index >= ConflictResolution.values.length) return ConflictResolution.ask;
    return ConflictResolution.values[index];
  }

  static Future<void> setConflictResolution(ConflictResolution value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_conflictKey, value.index);
  }
}
