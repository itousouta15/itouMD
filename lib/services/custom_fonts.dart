import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontImportException implements Exception {
  final String message;

  FontImportException(this.message);

  @override
  String toString() => message;
}

/// Imports a user-picked TTF/OTF file into the app's documents directory and
/// registers it with Flutter's [FontLoader] so it can be used as a reader
/// font family. `FontLoader` is process-global, so the font is registered
/// once per launch — [init] replays the persisted font at startup, and
/// [import] registers the picked file immediately (no restart needed).
class CustomFonts {
  static const _pathKey = 'custom_font_path';
  static const _familyKey = 'custom_font_family';

  static String? _currentFamily;

  /// The registered family name, or null when no font is imported.
  static String? get currentFamily => _currentFamily;

  static bool get isLoaded => _currentFamily != null;

  /// Re-registers the persisted font at startup so the family is available
  /// before the first frame that might use it. A missing/corrupt file clears
  /// the persisted settings (the fallback font then applies).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_pathKey);
    final family = prefs.getString(_familyKey);
    if (path == null || family == null) return;
    try {
      final file = File(path);
      if (!await file.exists()) throw const FileSystemException('not found');
      await _register(family, await file.readAsBytes());
      _currentFamily = family;
    } catch (_) {
      await prefs.remove(_pathKey);
      await prefs.remove(_familyKey);
      _currentFamily = null;
    }
  }

  /// Lets the user pick a `.ttf`/`.otf` file, copies it into the app's
  /// documents directory, registers it, and persists it. Returns the family
  /// name on success (also available via [currentFamily]) or null when the
  /// picker was cancelled. Throws [FontImportException] on failure.
  static Future<String?> import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      throw FontImportException('讀不到這個字體檔案 (´;ω;`)');
    }

    final name = picked.name;
    final dot = name.lastIndexOf('.');
    final family = dot > 0 ? name.substring(0, dot) : name;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/fonts');
    await dir.create(recursive: true);
    final dest = File('${dir.path}/$name');
    await dest.writeAsBytes(bytes, flush: true);

    await _register(family, bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathKey, dest.path);
    await prefs.setString(_familyKey, family);
    _currentFamily = family;
    return family;
  }

  /// Removes the imported font (files + settings + registration).
  static Future<void> remove() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_pathKey);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup; the settings below are the source of truth.
      }
    }
    await prefs.remove(_pathKey);
    await prefs.remove(_familyKey);
    _currentFamily = null;
  }

  static Future<void> _register(String family, Uint8List bytes) async {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}
