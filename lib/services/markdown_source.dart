import 'dart:convert';

import 'package:http/http.dart' as http;

class MarkdownFetchException implements Exception {
  final String message;
  MarkdownFetchException(this.message);
  @override
  String toString() => message;
}

/// Converts common "human" GitHub URLs (blob view, gist page) into their
/// raw-content equivalent so pasting a normal browser link just works.
String normalizeMarkdownUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || !uri.hasScheme) return input.trim();

  if (uri.host == 'github.com' && uri.pathSegments.contains('blob')) {
    final segments = List<String>.from(uri.pathSegments);
    final blobIndex = segments.indexOf('blob');
    segments.removeAt(blobIndex);
    return uri
        .replace(host: 'raw.githubusercontent.com', pathSegments: segments)
        .toString();
  }

  if (uri.host == 'gist.github.com' && !uri.path.endsWith('/raw')) {
    return '${uri.toString()}/raw';
  }

  if (uri.host == 'hackmd.io' && !uri.path.endsWith('/download')) {
    final segments = List<String>.from(uri.pathSegments)
      ..removeWhere((s) => s.isEmpty);
    if (segments.isEmpty) return input.trim();

    // The download route needs the exact path as shown (custom-aliased
    // notes 404 if the leading @username segment is stripped), so just
    // append the action rather than rewriting the path.
    return uri.replace(pathSegments: [...segments, 'download']).toString();
  }

  return input.trim();
}

final _frontMatterBlockPattern = RegExp(
  r'^---\s*\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)',
);
final _yamlTitleFieldPattern = RegExp(
  r'''^title\s*:\s*["']?(.+?)["']?\s*$''',
  multiLine: true,
  caseSensitive: false,
);
final _firstH1Pattern = RegExp(r'^#\s+(.+?)\s*#*\s*$', multiLine: true);

/// Picks a human-readable title for fetched content: the YAML front
/// matter's `title:` field if present (this is how HackMD notes carry
/// their real title — the URL itself is just an opaque id, e.g.
/// `S1mHSwOWll`), otherwise the document's first `# heading`. Returns
/// `null` (letting the caller fall back to the URL) if neither is found.
String? extractDocTitle(String content) {
  final frontMatter = _frontMatterBlockPattern.matchAsPrefix(content);
  if (frontMatter != null) {
    final titleMatch = _yamlTitleFieldPattern.firstMatch(frontMatter.group(1)!);
    final title = titleMatch?.group(1)?.trim();
    if (title != null && title.isNotEmpty) return title;
  }

  final h1 = _firstH1Pattern.firstMatch(content);
  final title = h1?.group(1)?.trim();
  if (title != null && title.isNotEmpty) return title;

  return null;
}

Future<String> fetchMarkdownFromUrl(String rawInput) async {
  final url = normalizeMarkdownUrl(rawInput);
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    throw MarkdownFetchException('這個網址怪怪的，再檢查一下 (´;ω;`)');
  }

  final http.Response response;
  try {
    response = await http.get(uri).timeout(const Duration(seconds: 15));
  } catch (_) {
    throw MarkdownFetchException('抓不到內容，檢查網路連線或網址 (´;ω;`)');
  }

  if (response.statusCode != 200) {
    throw MarkdownFetchException('伺服器回了 ${response.statusCode}，抓取失敗 (´;ω;`)');
  }

  return utf8.decode(response.bodyBytes, allowMalformed: true);
}
