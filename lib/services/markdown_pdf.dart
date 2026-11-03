import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'github_link_rewriter.dart';
import 'markdown_pdf_images.dart';
import 'markdown_renderer.dart';

String markdownPdfFileName(String title) {
  var name = title
      .replaceAll(RegExp(r'[\x00-\x1f\x7f\\/:*?"<>|]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '')
      .replaceFirst(
        RegExp(r'\.(md|markdown|mdx|txt|pdf)$', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) name = 'document';
  if (RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(name)) {
    name = '_$name';
  }
  var utf8Length = 0;
  name = String.fromCharCodes(
    name.runes.take(100).takeWhile((rune) {
      utf8Length += utf8.encode(String.fromCharCode(rune)).length;
      return utf8Length <= 180;
    }),
  );
  return '$name.pdf';
}

Future<Uint8List> generateMarkdownPdf({
  required String markdown,
  required String title,
  GithubLinkContext? githubLinkContext,
}) async {
  final fontData = await rootBundle.load('assets/fonts/NotoSansTC-Regular.ttf');
  return compute(_generatePdf, (
    markdown: markdown,
    title: title,
    githubLinkContext: githubLinkContext,
    fontData: fontData,
  ));
}

typedef _PdfInput = ({
  String markdown,
  String title,
  GithubLinkContext? githubLinkContext,
  ByteData fontData,
});

Future<Uint8List> _generatePdf(_PdfInput input) async {
  var html = convertMarkdownToHtml(input.markdown);
  if (input.githubLinkContext case final context?) {
    html = rewriteGithubRelativeLinks(html, context);
  }
  final document = pw.Document(title: input.title, creator: 'itouMD');
  final fallback = pw.Font.ttf(input.fontData);
  final fragment = html_parser.parseFragment(html);
  final images = await loadMarkdownPdfImages(
    fragment
        .querySelectorAll('img[src]')
        .map((image) => image.attributes['src']!),
  );
  final renderer = _PdfRenderer(document.document, images, {
    for (final element in fragment.querySelectorAll('[id]')) element.id,
  });
  final blocks = renderer.blocks(fragment.nodes).toList();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      maxPages: 1000,
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
        fontFallback: [fallback],
      ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
      ),
      build: (_) => blocks.isEmpty ? [pw.SizedBox(height: 1)] : blocks,
    ),
  );
  return document.save();
}

class _PdfRenderer {
  _PdfRenderer(
    PdfDocument document,
    Map<String, Uint8List> bytesBySource,
    this.anchors,
  ) {
    for (final entry in bytesBySource.entries) {
      try {
        images[entry.key] = pw.ImageProxy(
          PdfImage.file(document, bytes: entry.value),
        );
      } catch (_) {
        // A valid image header does not guarantee decodable pixel data.
      }
    }
  }

  final Map<String, pw.ImageProvider> images = {};
  final Set<String> anchors;
  static const _ignored = {
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'head',
    'form',
  };
  static const _blockTags = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'pre',
    'ul',
    'ol',
    'li',
    'blockquote',
    'div',
    'section',
    'article',
    'details',
    'summary',
    'table',
    'hr',
  };
  static const _bodyStyle = pw.TextStyle(fontSize: 11, lineSpacing: 3);
  final _codeFont = pw.Font.courier();

  Iterable<pw.Widget> blocks(
    List<dom.Node> nodes, {
    int depth = 0,
    pw.TextStyle style = _bodyStyle,
    String prefix = '',
  }) sync* {
    final inline = <dom.Node>[];
    var nextPrefix = prefix;
    for (final node in nodes) {
      if (node is! dom.Element || !_blockTags.contains(node.localName)) {
        inline.add(node);
        continue;
      }
      if (_hasContent(inline)) {
        yield _paragraph(inline, style, prefix: nextPrefix, depth: depth);
        nextPrefix = '';
      }
      inline.clear();
      final tag = node.localName!;
      if (tag == 'p' &&
          node.nodes
              .where(
                (child) => child is! dom.Text || child.text.trim().isNotEmpty,
              )
              .every(
                (child) => child is dom.Element && child.localName == 'img',
              ) &&
          node.children.isNotEmpty) {
        for (final image in node.children) {
          final source = image.attributes['src'] ?? '';
          final data = images[source];
          if (data == null) {
            yield _paragraph([image], style);
          } else {
            yield _image(data, maxWidth: 450, maxHeight: 280);
            final alt = image.attributes['alt']?.trim() ?? '';
            if (alt.isNotEmpty) {
              yield pw.Text(alt, style: style.copyWith(fontSize: 9));
            }
          }
          yield pw.SizedBox(height: 8);
        }
        nextPrefix = '';
        continue;
      }
      if (tag == 'p' || tag == 'summary' || RegExp(r'^h[1-6]$').hasMatch(tag)) {
        final heading = tag.startsWith('h') ? int.parse(tag[1]) : null;
        final emphasis =
            heading != null ||
            tag == 'summary' ||
            node.classes.contains('hackmd-callout-title');
        if (heading != null) yield pw.SizedBox(height: 10);
        yield _paragraph(
          node.nodes,
          emphasis
              ? style.copyWith(
                  fontSize: heading == null ? 11 : 24 - heading * 2.0,
                  fontWeight: pw.FontWeight.bold,
                )
              : style,
          prefix: nextPrefix,
          depth: depth,
        );
        yield pw.SizedBox(height: 7);
      } else if (tag == 'pre') {
        yield pw.Text(
          node.text.replaceAll('\t', '    ').replaceFirst(RegExp(r'\n$'), ''),
          style: style.copyWith(font: _codeFont, fontSize: 9, lineSpacing: 2),
          overflow: pw.TextOverflow.span,
        );
        yield pw.SizedBox(height: 9);
      } else if (tag == 'ul' || tag == 'ol') {
        var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        for (final item in node.children.where(
          (child) => child.localName == 'li',
        )) {
          number = int.tryParse(item.attributes['value'] ?? '') ?? number;
          final marker = tag == 'ol' ? '${number++}. ' : '- ';
          yield* blocks(
            item.nodes,
            depth: depth + 1,
            style: style,
            prefix: marker,
          );
          yield pw.SizedBox(height: 4);
        }
      } else if (tag == 'table') {
        yield* _table(node);
        yield pw.SizedBox(height: 9);
      } else if (tag == 'hr') {
        yield pw.Divider(color: PdfColors.grey400);
      } else {
        yield* blocks(
          node.nodes,
          depth: tag == 'blockquote' ? depth + 1 : depth,
          style: tag == 'blockquote'
              ? style.copyWith(color: PdfColors.grey700)
              : style,
          prefix: nextPrefix,
        );
      }
      nextPrefix = '';
    }
    if (_hasContent(inline)) {
      yield _paragraph(inline, style, prefix: nextPrefix, depth: depth);
    }
  }

  bool _hasContent(List<dom.Node> nodes) => nodes.any(
    (node) =>
        node is dom.Element && !_ignored.contains(node.localName) ||
        node is dom.Text && node.text.trim().isNotEmpty,
  );

  pw.Widget _paragraph(
    List<dom.Node> nodes,
    pw.TextStyle style, {
    String prefix = '',
    int depth = 0,
  }) => pw.RichText(
    overflow: pw.TextOverflow.span,
    text: pw.TextSpan(
      style: style,
      children: [
        if (prefix.isNotEmpty || depth > 0)
          pw.TextSpan(text: '${'  ' * depth.clamp(0, 8)}$prefix'),
        ...nodes.map(_inline),
      ],
    ),
  );

  pw.InlineSpan _inline(dom.Node node) {
    if (node is dom.Text) {
      return pw.TextSpan(text: node.text.replaceAll(RegExp(r'\s+'), ' '));
    }
    if (node is! dom.Element || _ignored.contains(node.localName)) {
      return const pw.TextSpan(text: '');
    }
    final tag = node.localName;
    if (tag == 'br') return const pw.TextSpan(text: '\n');
    if (tag == 'input') {
      return pw.TextSpan(
        text: node.attributes.containsKey('checked') ? '[x] ' : '[ ] ',
      );
    }
    if (tag == 'x-latex') {
      var tex = '';
      try {
        tex = utf8.decode(base64Decode(node.attributes['data-tex'] ?? ''));
      } on FormatException {
        tex = node.text;
      }
      final display = node.attributes['data-mode'] == 'display';
      return pw.TextSpan(
        text: display ? '\n\$\$$tex\$\$\n' : '\$$tex\$',
        style: pw.TextStyle(font: _codeFont, fontSize: 10),
      );
    }
    if (tag == 'img') {
      final source = node.attributes['src'] ?? '';
      final image = images[source];
      if (image != null) {
        return pw.WidgetSpan(
          child: _image(image, maxWidth: 120, maxHeight: 90),
        );
      }
      final alt = node.attributes['alt']?.trim();
      final label = alt?.isNotEmpty == true ? alt! : 'Image';
      final visibleSource = source.startsWith('data:')
          ? 'image unavailable'
          : source;
      return pw.TextSpan(
        text: '[$label]${visibleSource.isEmpty ? '' : ' ($visibleSource)'}',
        annotation: _urlAnnotation(source),
        style: const pw.TextStyle(color: PdfColors.blue800),
      );
    }
    final style = switch (tag) {
      'b' || 'strong' => const pw.TextStyle(fontWeight: pw.FontWeight.bold),
      'i' || 'em' => const pw.TextStyle(fontStyle: pw.FontStyle.italic),
      'del' ||
      's' => const pw.TextStyle(decoration: pw.TextDecoration.lineThrough),
      'code' => pw.TextStyle(font: _codeFont, fontSize: 10),
      'a' => const pw.TextStyle(
        color: PdfColors.blue800,
        decoration: pw.TextDecoration.underline,
      ),
      _ => null,
    };
    return pw.TextSpan(
      style: style,
      annotation: tag == 'a'
          ? _urlAnnotation(node.attributes['href'] ?? '')
          : null,
      children: [
        if (node.id.isNotEmpty && anchors.contains(node.id))
          pw.WidgetSpan(
            child: pw.Anchor(
              name: node.id,
              child: pw.SizedBox(width: 0, height: 0),
            ),
          ),
        ...node.nodes.map(_inline),
      ],
    );
  }

  pw.AnnotationBuilder? _urlAnnotation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (url.startsWith('#') && anchors.contains(uri.fragment)) {
      return pw.AnnotationLink(uri.fragment);
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty ||
        uri.scheme == 'mailto') {
      return pw.AnnotationUrl(url);
    }
    return null;
  }

  pw.Widget _image(
    pw.ImageProvider image, {
    required double maxWidth,
    required double maxHeight,
  }) {
    final width = (image.width ?? maxWidth).toDouble();
    final height = (image.height ?? maxHeight).toDouble();
    final scale = math.min(1.0, math.min(maxWidth / width, maxHeight / height));
    return pw.Image(
      image,
      width: width * scale,
      height: height * scale,
      fit: pw.BoxFit.contain,
    );
  }

  Iterable<pw.Widget> _table(dom.Element table) sync* {
    final rows = table
        .querySelectorAll('tr')
        .map(
          (row) => row.children
              .where((cell) => cell.localName == 'th' || cell.localName == 'td')
              .toList(),
        )
        .where((row) => row.isNotEmpty)
        .toList();
    if (rows.isEmpty) return;
    final columns = rows
        .map((row) => row.length)
        .reduce((a, b) => a > b ? a : b);
    if (columns > 6) {
      for (final row in rows) {
        for (var i = 0; i < row.length; i++) {
          yield _paragraph(row[i].nodes, _bodyStyle, prefix: '${i + 1}: ');
        }
        yield pw.Divider(color: PdfColors.grey400);
      }
      return;
    }
    final pdfRows = <pw.TableRow>[];
    for (final row in rows) {
      final cells = [
        for (var i = 0; i < columns; i++)
          _cellChunks(i < row.length ? _plainText(row[i]) : ''),
      ];
      final parts = cells
          .map((cell) => cell.length)
          .reduce((a, b) => a > b ? a : b);
      final heading = row.every((cell) => cell.localName == 'th');
      for (var part = 0; part < parts; part++) {
        pdfRows.add(
          pw.TableRow(
            repeat: heading && parts == 1,
            decoration: heading
                ? const pw.BoxDecoration(color: PdfColors.grey200)
                : null,
            children: [
              for (final cell in cells)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    part < cell.length ? cell[part] : '',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: heading
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
        );
      }
    }
    yield pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      defaultColumnWidth: const pw.FlexColumnWidth(),
      children: pdfRows,
    );
  }

  String _plainText(dom.Node node) {
    if (node is dom.Element && node.localName == 'img') {
      return '[${node.attributes['alt'] ?? 'Image'}]';
    }
    if (node is dom.Element && node.localName != 'x-latex') {
      if (_ignored.contains(node.localName)) return '';
      if (node.localName == 'br') return '\n';
      if (node.localName != 'input') return node.nodes.map(_plainText).join();
    }
    final span = _inline(node);
    return span.toPlainText();
  }

  // PDF table rows cannot span pages; bound each continuation row's height.
  List<String> _cellChunks(String text) {
    final chunks = <String>[];
    var runes = <int>[];
    var lines = 0;
    for (final rune in text.runes) {
      runes.add(rune);
      if (rune == 10) lines++;
      if (runes.length >= 120 || lines >= 8) {
        chunks.add(String.fromCharCodes(runes));
        runes = [];
        lines = 0;
      }
    }
    if (runes.isNotEmpty || chunks.isEmpty) {
      chunks.add(String.fromCharCodes(runes));
    }
    return chunks;
  }
}
