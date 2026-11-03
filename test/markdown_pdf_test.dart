import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itou_md/services/github_link_rewriter.dart';
import 'package:itou_md/services/markdown_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF file names', () {
    test('replaces supported extensions without losing Unicode', () {
      expect(markdownPdfFileName('筆記.MARKDOWN'), '筆記.pdf');
      expect(markdownPdfFileName('notes.md'), 'notes.pdf');
      expect(markdownPdfFileName('notes.mdx'), 'notes.pdf');
      expect(markdownPdfFileName('notes.txt'), 'notes.pdf');
      expect(markdownPdfFileName('notes.pdf'), 'notes.pdf');
      expect(markdownPdfFileName('release.v2'), 'release.v2.pdf');
    });

    test('handles unsafe, empty and reserved names', () {
      expect(
        markdownPdfFileName('report/2026: draft?.md'),
        'report_2026_ draft_.pdf',
      );
      expect(markdownPdfFileName(' \n '), '_.pdf');
      expect(markdownPdfFileName('  ... '), 'document.pdf');
      expect(markdownPdfFileName('.md'), 'document.pdf');
      expect(markdownPdfFileName('CON.md'), '_CON.pdf');
      expect(markdownPdfFileName('notes. '), 'notes.pdf');
      expect(markdownPdfFileName('a' * 300).length, 104);
      expect(utf8.encode(markdownPdfFileName('筆' * 100)).length, lessThan(255));
    });
  });

  test('empty Markdown produces a valid single-page PDF', () async {
    final bytes = await generateMarkdownPdf(markdown: '', title: 'Empty');
    final raw = latin1.decode(bytes);
    expect(raw, startsWith('%PDF-'));
    expect(raw.trimRight(), endsWith('%%EOF'));
    expect(_pageCount(raw), 1);
  });

  test(
    'exports formatted Markdown, expanded spoilers, math and safe links',
    () async {
      final bytes = await generateMarkdownPdf(
        title: 'Fixture',
        markdown: r'''
---
secret: FRONTMATTERHIDDEN
---
# HeadingSentinel

[TOC]

**BoldSentinel** and *ItalicSentinel* with ~~RemovedSentinel~~.

3. ThirdSentinel
4. FourthSentinel
   - NestedSentinel

- [x] DoneSentinel
- [ ] TodoSentinel

> QuoteSentinel

:::info
CalloutSentinel
:::

:::spoiler Hidden by default
SpoilerSentinel
:::

| Name | Value |
| --- | --- |
| TableSentinel | value |

```dart
CodeSentinel("quoted");
```

Formula $x_1$ and $$E=mc^2$$.

[Website](https://example.com/guide)
[BadLink](javascript:alert%281%29)
<script>EXECUTABLEHIDDEN</script>
<style>STYLEHIDDEN</style>
''',
      );
      final raw = latin1.decode(bytes);
      final content = _decodedPdf(bytes);
      for (final marker in [
        'HeadingSentinel',
        'BoldSentinel',
        'ItalicSentinel',
        'RemovedSentinel',
        'ThirdSentinel',
        'FourthSentinel',
        'NestedSentinel',
        'DoneSentinel',
        'TodoSentinel',
        'QuoteSentinel',
        'CalloutSentinel',
        'SpoilerSentinel',
        'TableSentinel',
        'CodeSentinel',
        'x_1',
        'E=mc^2',
      ]) {
        expect(content, contains(marker), reason: marker);
      }
      expect(raw, contains('https://example.com/guide'));
      expect(content, isNot(contains('FRONTMATTERHIDDEN')));
      expect(content, isNot(contains('EXECUTABLEHIDDEN')));
      expect(content, isNot(contains('STYLEHIDDEN')));
      expect(raw, isNot(contains('javascript:')));
      expect(raw, contains('/Dest'));
    },
  );

  test('embeds a Unicode font and its text mapping for Chinese', () async {
    final bytes = await generateMarkdownPdf(
      markdown: '# 中文筆記\n\n繁體中文測試。',
      title: 'Chinese',
    );
    final raw = latin1.decode(bytes);
    final content = _decodedPdf(bytes).toLowerCase();
    expect(raw, contains('/FontFile2'));
    expect(raw, contains('/ToUnicode'));
    expect(content, contains('4e2d'));
    expect(content, contains('6587'));
  });

  test(
    'long paragraphs and unbroken code lines span pages without losing the end',
    () async {
      final paragraph = List.filled(1300, 'Long paragraph text.').join(' ');
      final code = List.generate(150, (i) => 'line$i ${'x' * 180}').join('\n');
      final bytes = await generateMarkdownPdf(
        markdown:
            '$paragraph\n\n```\n$code\nCodeEndSentinel\n```\n\nFinalSentinel',
        title: 'Long document',
      );
      expect(_pageCount(latin1.decode(bytes)), greaterThan(3));
      final content = _decodedPdf(bytes);
      expect(content, contains('CodeEndSentinel'));
      expect(content, contains('FinalSentinel'));
    },
  );

  test('long table cells and many rows remain exportable', () async {
    final rows = List.generate(
      90,
      (i) => '| Row$i | ${'word ' * 45} |',
    ).join('\n');
    final bytes = await generateMarkdownPdf(
      markdown:
          '| Name | Value |\n| --- | --- |\n$rows\n| FinalTableSentinel | Done |',
      title: 'Table',
    );
    expect(_pageCount(latin1.decode(bytes)), greaterThan(2));
    expect(_decodedPdf(bytes), contains('FinalTableSentinel'));
  });

  test('GitHub relative links retain their repository context', () async {
    final bytes = await generateMarkdownPdf(
      markdown:
          '[Guide](../guide.md)\n\n![Diagram](file:///private/diagram.png)',
      title: 'Links',
      githubLinkContext: const GithubLinkContext(
        owner: 'owner',
        repo: 'repo',
        ref: 'main',
        dirPath: 'docs',
      ),
    );
    final raw = latin1.decode(bytes);
    expect(raw, contains('https://github.com/owner/repo/blob/main/guide.md'));
    expect(_decodedPdf(bytes), contains('Diagram'));
    expect(raw, isNot(contains('/URI(file:')));
  });

  test(
    'data PNGs are embedded as PDF images without a network request',
    () async {
      final png = base64Encode(
        await File('assets/logo/hackmd_logo.png').readAsBytes(),
      );
      final bytes = await generateMarkdownPdf(
        markdown: '![Pixel](data:image/png;base64,$png)',
        title: 'Image',
      );
      expect(latin1.decode(bytes), matches(RegExp(r'/Subtype\s*/Image')));
      expect(_decodedPdf(bytes), contains('Pixel'));
    },
  );

  test(
    'corrupt PNG pixel data falls back without losing the rest of the note',
    () async {
      const corruptPng =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM1sAAAAASUVORK5CYII=';
      final bytes = await generateMarkdownPdf(
        markdown:
            '![BrokenSentinel](data:image/png;base64,$corruptPng)\n\nAfterImageSentinel',
        title: 'Broken image',
      );
      final content = _decodedPdf(bytes);
      expect(content, contains('BrokenSentinel'));
      expect(content, contains('AfterImageSentinel'));
      expect(content, isNot(contains(corruptPng)));
    },
  );
}

int _pageCount(String raw) => RegExp(r'/Type\s*/Page\b').allMatches(raw).length;

String _decodedPdf(List<int> bytes) {
  final raw = latin1.decode(bytes);
  final contents = StringBuffer(raw);
  for (final match in RegExp(
    r'stream\r?\n([\s\S]*?)\r?\nendstream',
  ).allMatches(raw)) {
    try {
      contents.write(
        latin1.decode(zlib.decode(latin1.encode(match.group(1)!))),
      );
    } on FormatException {
      // JPEG data and uncompressed PDF streams are already in the raw text.
    }
  }
  return contents.toString();
}
