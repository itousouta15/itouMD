import 'dart:convert';
import 'dart:io';

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
/// Release with a `itouMD-vX.Y.Z.apk` asset, so the public `releases/latest`
/// endpoint is the source of truth for "is there an update".
class UpdateChecker {
  static const _repo = 'itousouta15/itouMD';

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

    String? apkUrl;
    final assets = json['assets'] as List? ?? const [];
    for (final asset in assets) {
      if (asset is Map<String, dynamic> &&
          (asset['name'] as String? ?? '').endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        break;
      }
    }

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

  /// Downloads the APK into the app cache and hands it to the system
  /// installer. [onProgress] reports 0..1 as bytes arrive.
  static Future<void> downloadAndInstall(
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
      throw Exception('下載失敗，HTTP ${streamed.statusCode}');
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

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}
