import 'package:markdown/markdown.dart' as md;

/// HackMD/Docsify-style `:::type ... :::` container blocks. Converted to
/// `<div class="hackmd-callout hackmd-callout-TYPE">` (with a title
/// paragraph) for info/warning/success/danger, or to a native `<details>`
/// for `:::spoiler` since that already renders as a real collapsible.
class HackmdContainerSyntax extends md.BlockSyntax {
  const HackmdContainerSyntax();

  static final _openPattern = RegExp(
    r'^:::+\s*(info|warning|success|danger|spoiler)\s*$',
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
    final type = _openPattern
        .firstMatch(parser.current.content)!
        .group(1)!
        .toLowerCase();
    parser.advance();

    final childLines = <md.Line>[];
    while (!parser.isDone && !_closePattern.hasMatch(parser.current.content)) {
      childLines.add(parser.current);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();

    final children = md.BlockParser(childLines, parser.document).parseLines();

    if (type == 'spoiler') {
      final summary = md.Element('summary', [md.Text('Spoiler')]);
      return md.Element('details', [summary, ...children]);
    }

    final title = md.Element('p', [md.Text(_titleTextMap[type]!)])
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
