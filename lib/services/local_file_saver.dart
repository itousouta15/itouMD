import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Outcome of an attempt to write an edited document back to the device file
/// it was opened from.
enum LocalSaveResult {
  /// The original file was updated in place.
  saved,

  /// The platform/file can't be written back — the caller should fall back
  /// to "另存新檔" (save-as).
  unsupported,

  /// A write was attempted but threw (e.g. permission revoked, stream
  /// unavailable).
  failed,
}

/// Writes edits back to the file a document was opened from.
///
/// `file_picker` reports the original file two ways: `identifier` (the
/// platform's original-file reference — an Android `content://` Uri or an
/// iOS NSURL) and `path` (a sandbox copy on mobile, but the *real* file on
/// desktop). So:
///
/// * **Android** — the picker uses `ACTION_OPEN_DOCUMENT`, which hands the
///   app a read/write Uri grant; [LocalFileSaver] writes back through a
///   native channel opening an output stream on that Uri.
/// * **Desktop** (Windows/macOS/Linux) — `identifier` is null and `path`
///   already points at the original, so a plain file write works.
/// * **iOS** — the picker runs in import mode and only ever gives the app a
///   sandbox copy; the provider file isn't writable from here, so save-back
///   is unsupported and the app falls back to 另存新檔.
class LocalFileSaver {
  static const _channel = MethodChannel('itou_md/local_file');

  static Future<LocalSaveResult> writeBack({
    String? path,
    String? identifier,
    required String text,
  }) async {
    if (kIsWeb) return LocalSaveResult.unsupported;
    final bytes = Uint8List.fromList(utf8.encode(text));

    if (Platform.isAndroid && identifier != null) {
      try {
        await _channel.invokeMethod<void>('writeToUri', {
          'uri': identifier,
          'bytes': bytes,
        });
        return LocalSaveResult.saved;
      } catch (_) {
        return LocalSaveResult.failed;
      }
    }

    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (isDesktop && identifier == null && path != null) {
      try {
        await File(path).writeAsBytes(bytes, flush: true);
        return LocalSaveResult.saved;
      } catch (_) {
        return LocalSaveResult.failed;
      }
    }

    return LocalSaveResult.unsupported;
  }
}
