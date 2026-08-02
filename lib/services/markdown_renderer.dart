import 'package:markdown/markdown.dart' as md;

import 'hackmd_syntax.dart';
import 'latex_preprocessor.dart';

/// Converts raw Markdown to HTML, applying the front-matter-stripping,
/// LaTeX-protection, and HackMD-compatibility preprocessing passes.
///
/// Kept as a standalone top-level function (no captured state) so it can be
/// torn off and run on a background isolate via `compute()` — parsing a
/// large document is real CPU work, and doing it on the UI isolate is what
/// causes the stutter when opening a document.
String convertMarkdownToHtml(String rawMarkdown) {
  return md.markdownToHtml(
    protectMathAsHtml(
      injectHackmdToc(_expandHackmdImageSizes(_stripFrontMatter(rawMarkdown))),
    ),
    extensionSet: md.ExtensionSet.gitHubFlavored,
    blockSyntaxes: hackmdBlockSyntaxes,
  );
}

/// HackMD (and Jekyll/Hugo-style static site generators) prefix notes with
/// a YAML front-matter block — `---\ntitle: ...\ntags: ...\n---` — for
/// metadata that isn't meant to be displayed as document content. Strip it
/// if present at the very start of the document; anywhere else `---` is
/// just a horizontal rule, so this only matches when anchored to position 0.
final _frontMatterPattern = RegExp(r'^---\s*\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)[ \t]*\r?\n?');

String _stripFrontMatter(String source) {
  final match = _frontMatterPattern.matchAsPrefix(source);
  if (match == null) return source;
  return source.substring(match.end);
}

/// HackMD/CodiMD's image-resize shorthand — `![alt](url =WIDTHxHEIGHT)`,
/// e.g. `=250x`, `=x250`, `=250x250`, or `=50%x` — isn't valid CommonMark
/// (a link/image destination can't be followed by a bare size token, only a
/// quoted "title"), so the standard parser fails to recognize the whole
/// image and prints it back as literal text. Rewrite it to a plain `<img>`
/// tag with an equivalent inline style before parsing, since raw inline
/// HTML passes through GFM untouched.
final _hackmdImageSizePattern = RegExp(
  r'!\[([^\]]*)\]\(([^\s()]+)\s+=(\d*%?)x(\d*%?)\)',
);
final _fenceLinePatternForImages = RegExp(r'^\s*(`{3,}|~{3,})');

String _expandHackmdImageSizes(String source) {
  if (!source.contains('=') || !_hackmdImageSizePattern.hasMatch(source)) {
    return source;
  }

  final lines = source.split('\n');
  var inFence = false;
  String? fenceChar;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fenceMatch = _fenceLinePatternForImages.firstMatch(line);
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

    lines[i] = line.replaceAllMapped(_hackmdImageSizePattern, (m) {
      final alt = m.group(1)!.replaceAll('"', '&quot;');
      final url = m.group(2)!.replaceAll('"', '&quot;');
      final width = m.group(3) ?? '';
      final height = m.group(4) ?? '';
      final style = [
        'width:${width.isEmpty ? 'auto' : width.endsWith('%') ? width : '${width}px'}',
        'height:${height.isEmpty ? 'auto' : height.endsWith('%') ? height : '${height}px'}',
      ].join(';');
      return '<img src="$url" alt="$alt" style="$style" />';
    });
  }

  return lines.join('\n');
}
