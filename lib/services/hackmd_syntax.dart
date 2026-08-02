import 'package:markdown/markdown.dart' as md;

/// HackMD/Docsify-style `:::type ... :::` container blocks. Converted to
/// `<div class="hackmd-callout hackmd-callout-TYPE">` (with a title
/// paragraph) for info/warning/success/danger, or to a native `<details>`
/// for `:::spoiler` since that already renders as a real collapsible.
class HackmdContainerSyntax extends md.BlockSyntax {
  const HackmdContainerSyntax();

  // The type keyword may be followed by a title, e.g. `:::spoiler 目錄`
  // (HackMD uses this as the collapsed summary text for spoilers).
  static final _openPattern = RegExp(
    r'^:::+\s*(info|warning|success|danger|spoiler)(?:\s+(.*\S))?\s*$',
    caseSensitive: false,
  );
  static final _closePattern = RegExp(r'^:::+\s*$');

  static const _titleTextMap = {
    'info': 'Info',
    'warning': 'Warning',
    'success': 'Success',
    'danger': 'Danger',
  };

  @override
  RegExp get pattern => _openPattern;

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _openPattern.firstMatch(parser.current.content)!;
    final type = match.group(1)!.toLowerCase();
    final customTitle = match.group(2)?.trim();
    parser.advance();

    final childLines = <md.Line>[];
    while (!parser.isDone && !_closePattern.hasMatch(parser.current.content)) {
      childLines.add(parser.current);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();

    final children = md.BlockParser(childLines, parser.document).parseLines();

    if (type == 'spoiler') {
      final summary = md.Element('summary', [
        md.Text(customTitle?.isNotEmpty == true ? customTitle! : 'Spoiler'),
      ]);
      return md.Element('details', [summary, ...children]);
    }

    final titleText = customTitle?.isNotEmpty == true
        ? customTitle!
        : _titleTextMap[type]!;
    final title = md.Element('p', [md.Text(titleText)])
      ..attributes['class'] = 'hackmd-callout-title';
    return md.Element('div', [title, ...children])
      ..attributes['class'] = 'hackmd-callout hackmd-callout-$type';
  }
}

/// Extra block syntaxes layered on top of GFM to widen note-taking-app
/// compatibility: GitHub-style `> [!NOTE]` alerts (already implemented by
/// the `markdown` package, just not bundled into `gitHubFlavored`) and
/// HackMD-style `:::info ... :::` containers.
final hackmdBlockSyntaxes = <md.BlockSyntax>[
  const md.AlertBlockSyntax(),
  const HackmdContainerSyntax(),
];

class _TocHeading {
  final int level;
  final String text;
  final String slug;
  const _TocHeading(this.level, this.text, this.slug);
}

final _fenceLinePattern = RegExp(r'^\s*(`{3,}|~{3,})');
final _atxHeadingPattern = RegExp(r'^(#{1,6})\s+(.+?)\s*#*\s*$');
final _tocLinePattern = RegExp(r'^\[toc\]\s*$', caseSensitive: false);
final _slugWordChar = RegExp(r'[\p{L}\p{N}_-]', unicode: true);
final _slugSpace = RegExp(r'\s', unicode: true);

/// Slugifies heading text into a URL-safe anchor id, keeping CJK and other
/// non-Latin letters instead of the upstream `markdown` package's own
/// heading-id generator, which strips them and can produce an empty id.
String _slugify(String text) {
  final buffer = StringBuffer();
  for (final rune in text.trim().toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    if (_slugWordChar.hasMatch(ch)) {
      buffer.write(ch);
    } else if (_slugSpace.hasMatch(ch)) {
      buffer.write('-');
    }
  }
  return buffer.toString();
}

/// Expands HackMD's `[TOC]` shortcode into a nested list of links to the
/// document's headings, and gives each heading a matching `#slug` anchor
/// (an invisible `<a id>` prefix, since GFM inline HTML passes through
/// untouched) for those links to jump to. A no-op when the document has no
/// `[TOC]` marker, so ordinary documents are left byte-for-byte untouched.
String injectHackmdToc(String source) {
  final lines = source.split('\n');
  final headings = <_TocHeading>[];
  final headingLineIndex = <int>[];
  final tocLineIndex = <int>[];
  final usedSlugs = <String, int>{};
  var inFence = false;
  String? fenceChar;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fenceMatch = _fenceLinePattern.firstMatch(line);
    if (fenceMatch != null) {
      final char = fenceMatch.group(1)![0];
      if (!inFence) {
        inFence = true;
        fenceChar = char;
      } else if (char == fenceChar) {
        inFence = false;
        fenceChar = null;
      }
      continue;
    }
    if (inFence) continue;

    if (_tocLinePattern.hasMatch(line)) {
      tocLineIndex.add(i);
      continue;
    }

    final headingMatch = _atxHeadingPattern.firstMatch(line);
    if (headingMatch == null) continue;
    final text = headingMatch.group(2)!.trim();
    if (text.isEmpty) continue;

    var slug = _slugify(text);
    if (slug.isEmpty) slug = 'heading';
    final priorCount = usedSlugs.update(slug, (v) => v + 1, ifAbsent: () => 0);
    if (priorCount > 0) slug = '$slug-$priorCount';

    headings.add(_TocHeading(headingMatch.group(1)!.length, text, slug));
    headingLineIndex.add(i);
  }

  if (tocLineIndex.isEmpty) return source;

  for (var h = 0; h < headings.length; h++) {
    final i = headingLineIndex[h];
    final marker = _atxHeadingPattern.firstMatch(lines[i])!.group(1)!;
    lines[i] = '$marker <a id="${headings[h].slug}"></a>${headings[h].text}';
  }

  var toc = '';
  if (headings.isNotEmpty) {
    final minLevel = headings.map((h) => h.level).reduce((a, b) => a < b ? a : b);
    toc = [
      for (final h in headings)
        '${'  ' * (h.level - minLevel)}- [${h.text}](#${h.slug})',
    ].join('\n');
  }
  for (final i in tocLineIndex) {
    lines[i] = toc;
  }

  return lines.join('\n');
}
