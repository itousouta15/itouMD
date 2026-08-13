import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Info about a newer release, as resolved from GitHub's `releases/latest`.
class UpdateInfo {
  final String latestVersion;
  final String releaseUrl;
  final String? apkUrl;
  final String? notes;

  const UpdateInfo({
    required this.latestVersion,
    required this.releaseUrl,
    this.apkUrl,
    this.notes,
  });
}

/// Checks the GitHub release feed for a newer APK and drives the in-app
/// download + install flow. The repo ships every version as a GitHub
/// Release with one APK asset per ABI (`itouMD-vX.Y.Z-{abi}.apk`) rather
/// than a single universal APK carrying every architecture's native code,
/// so the public `releases/latest` endpoint is the source of truth for
/// "is there an update" and [InstallHelper.supportedAbis] picks which
/// asset actually matches this device.
class UpdateChecker {
  static const _repo = 'itousouta15/itouMD';
  static const _knownAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

  /// Fetches the latest release and returns [UpdateInfo] only when its
  /// version is strictly newer than the installed one; `null` when the app
  /// is current, the network failed, or the API refused to answer.
  static Future<UpdateInfo?> checkForUpdate() async {
    final PackageInfo info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }

    final http.Response res;
    try {
      res = await http
          .get(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (res.statusCode != 200) return null;

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final tag = json['tag_name'] as String? ?? '';
    final latest = tag.replaceFirst(RegExp(r'^v'), '');
    if (!_isNewer(latest, info.version)) return null;

    // Index every APK asset by whichever known ABI its filename mentions,
    // and separately remember the first APK seen regardless — the
    // fallback for an older release that only ever shipped one universal
    // APK with no ABI in its name.
    final assets = json['assets'] as List? ?? const [];
    final apkByAbi = <String, String>{};
    String? firstApkUrl;
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String?;
      if (!name.endsWith('.apk') || url == null) continue;
      firstApkUrl ??= url;
      for (final abi in _knownAbis) {
        if (name.contains(abi)) apkByAbi[abi] = url;
      }
    }

    String? apkUrl;
    for (final abi in await InstallHelper.supportedAbis()) {
      final match = apkByAbi[abi];
      if (match != null) {
        apkUrl = match;
        break;
      }
    }
    apkUrl ??= firstApkUrl;

    return UpdateInfo(
      latestVersion: latest,
      releaseUrl:
          json['html_url'] as String? ??
          'https://github.com/$_repo/releases/latest',
      apkUrl: apkUrl,
      notes: json['body'] as String?,
    );
  }

  static bool _isNewer(String latest, String current) {
    final a = _parts(latest);
    final b = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static List<int> _parts(String version) {
    final cleaned = version.split('+').first;
    final parts = cleaned
        .split('.')
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.take(3).toList();
  }

  /// Downloads the APK into the app cache. [onProgress] reports 0..1 as
  /// bytes arrive.
  static Future<File> downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/itouMD-update.apk');
    if (file.existsSync()) {
      await file.delete();
    }

    final request = http.Request('GET', Uri.parse(url));
    final streamed = await http.Client().send(request);
    if (streamed.statusCode != 200) {
      throw Exception('HTTP ${streamed.statusCode}');
    }

    final total = streamed.contentLength;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          onProgress?.call(received / total);
        }
      }
    } finally {
      await sink.close();
    }

    // A dropped connection can end the stream "cleanly" (no thrown error)
    // while still leaving a truncated file — Android's installer then
    // rejects it with an opaque "problem parsing the package" instead of
    // this surfacing as a download failure. Catch both a short read and a
    // response that isn't actually a ZIP (an HTML error/interstitial page
    // slipping through with an HTTP 200) before handing the file off.
    if (total != null && total > 0 && received != total) {
      await file.delete();
      throw Exception('下載不完整（$received/$total bytes）');
    }
    if (!await _looksLikeApk(file)) {
      await file.delete();
      throw Exception('下載到的檔案格式不正確');
    }
    return file;
  }

  /// APKs are ZIP files, which always start with the local-file-header
  /// signature `PK\x03\x04` — a cheap sanity check.
  static Future<bool> _looksLikeApk(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(4);
      return head.length == 4 &&
          head[0] == 0x50 &&
          head[1] == 0x4B &&
          head[2] == 0x03 &&
          head[3] == 0x04;
    } finally {
      await raf.close();
    }
  }

  /// Hands the downloaded APK to the system installer. Throws when the
  /// installer can't be launched (permission, no handler, ...).
  ///
  /// Does *not* delete the file afterwards: `OpenFilex.open` only confirms
  /// the install Activity was launched, not that it has finished reading
  /// the file — the system installer reads it asynchronously, in its own
  /// process, via our FileProvider content:// URI. Deleting immediately
  /// after used to race that read and could hand the installer a
  /// disappearing/truncated file (surfacing as Android's opaque "problem
  /// parsing the package"). [downloadApk] already clears any leftover file
  /// before starting the next download, so nothing accumulates.
  static Future<void> installApk(File file) async {
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}

/// Thin wrapper over the Android platform channel that checks/opens the
/// "install unknown apps" permission, which Android 8+ requires before the
/// system installer will open an APK.
class InstallHelper {
  static const _channel = MethodChannel('itou_md/install');

  static Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ??
          true;
    } catch (_) {
      // Channel unavailable (non-Android/old build) — attempt anyway.
      return true;
    }
  }

  static Future<void> openUnknownAppSourcesSettings() async {
    try {
      await _channel.invokeMethod<void>('openUnknownAppSourcesSettings');
    } catch (_) {
      // Best effort; the generic app-settings fallback lives in Kotlin.
    }
  }

  /// This device's supported ABIs, most-preferred first (e.g.
  /// `["arm64-v8a", "armeabi-v7a"]`) — used to pick the matching
  /// per-architecture release asset. Empty on non-Android or if the
  /// channel call fails, which callers treat as "no preference".
  static Future<List<String>> supportedAbis() async {
    if (!Platform.isAndroid) return const [];
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        'supportedAbis',
      );
      return result?.whereType<String>().toList() ?? const [];
    } catch (_) {
      return const [];
    }
  }
}
