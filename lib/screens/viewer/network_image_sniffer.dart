import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:fwfh_svg/fwfh_svg.dart';
import 'package:http/http.dart' as http;

/// Many badge/status-image services (shields.io and friends) serve SVG
/// without a `.svg` extension in the URL, so [SvgFactory]'s suffix check
/// misses them. This sniffs the actual response bytes for network images
/// and routes to [SvgPicture] or a raster [Image] accordingly.
class SvgAwareWidgetFactory extends WidgetFactory with SvgFactory {
  final ValueChanged<String>? onImageTap;

  SvgAwareWidgetFactory({this.onImageTap});

  @override
  Widget? buildImageWidget(BuildTree meta, ImageSource src) {
    final url = src.url;
    Widget? base;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      base = SniffedNetworkImage(url: url, width: src.width, height: src.height);
    } else {
      base = super.buildImageWidget(meta, src);
    }
    if (base == null || onImageTap == null) return base;
    return GestureDetector(onTap: () => onImageTap!(url), child: base);
  }

  /// `[TOC]`-generated links point at `#slug` anchors; the `markdown`
  /// package percent-encodes non-ASCII link destinations (so CJK slugs come
  /// through as `#%E7%AC%AC...`), but the `<a id>` anchors injected by
  /// [injectHackmdToc] keep the raw text. Decode before handing off to the
  /// anchor registry so the two actually match up.
  @override
  Future<bool> onTapUrl(String url) async {
    if (url.startsWith('#')) {
      final id = Uri.decodeComponent(url.substring(1));
      return onTapAnchorWrapper(id);
    }
    return super.onTapUrl(url);
  }
}

class SniffedNetworkImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;

  const SniffedNetworkImage({super.key, required this.url, this.width, this.height});

  @override
  State<SniffedNetworkImage> createState() => _SniffedNetworkImageState();
}

class _SniffedNetworkImageState extends State<SniffedNetworkImage> {
  static final _cache = <String, Uint8List>{};

  late final Future<Uint8List> _future = _load();

  Future<Uint8List> _load() async {
    final cached = _cache[widget.url];
    if (cached != null) return cached;
    final res = await http.get(Uri.parse(widget.url));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    _cache[widget.url] = res.bodyBytes;
    return res.bodyBytes;
  }

  bool _looksLikeSvg(Uint8List bytes) {
    final sample = bytes.length > 300 ? bytes.sublist(0, 300) : bytes;
    final head = utf8
        .decode(sample, allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    return head.startsWith('<svg') || head.startsWith('<?xml');
  }

  /// flutter_svg cannot reliably render `<text>` elements combined with
  /// nested `transform="scale()"` + `textLength` — the exact technique
  /// shields.io-style badges use — and produces garbled glyphs. Plain
  /// vector icons/logos/shapes have no `<text>` and are unaffected, so
  /// skip only the SVGs that would come out looking broken.
  bool _containsSvgText(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return RegExp(r'<text\b', caseSensitive: false).hasMatch(text);
  }

  /// Reads the width/height (or viewBox) declared on the root `<svg>` tag,
  /// since badge services rarely set `width`/`height` on the `<img>` itself
  /// and SvgPicture needs an aspect ratio to avoid being squashed/cropped
  /// inside the surrounding text flow.
  Size? _svgIntrinsicSize(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final tagMatch = RegExp(r'<svg\b[^>]*>').firstMatch(text);
    if (tagMatch == null) return null;
    final tag = tagMatch.group(0)!;

    final w = RegExp(r'''width\s*=\s*["']([\d.]+)''').firstMatch(tag);
    final h = RegExp(r'''height\s*=\s*["']([\d.]+)''').firstMatch(tag);
    final width = w != null ? double.tryParse(w.group(1)!) : null;
    final height = h != null ? double.tryParse(h.group(1)!) : null;
    if (width != null && height != null && width > 0 && height > 0) {
      return Size(width, height);
    }

    final vb = RegExp(
      r'''viewBox\s*=\s*["']\s*[\-\d.]+\s+[\-\d.]+\s+([\d.]+)\s+([\d.]+)''',
    ).firstMatch(tag);
    if (vb != null) {
      final vbWidth = double.tryParse(vb.group(1)!);
      final vbHeight = double.tryParse(vb.group(2)!);
      if (vbWidth != null && vbHeight != null && vbWidth > 0 && vbHeight > 0) {
        return Size(vbWidth, vbHeight);
      }
    }
    return null;
  }

  /// flutter_svg mis-renders (crops/misscales) SVGs that omit `viewBox` and
  /// only declare `width`/`height` — a pattern shields.io and friends use
  /// constantly. Per spec a missing viewBox should default to
  /// `0 0 width height`, so patch that in explicitly before handing the
  /// bytes to the renderer.
  Uint8List _ensureViewBox(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final tagMatch = RegExp(r'<svg\b[^>]*>').firstMatch(text);
    if (tagMatch == null) return bytes;
    final tag = tagMatch.group(0)!;
    if (tag.contains('viewBox')) return bytes;

    final w = RegExp(r'''width\s*=\s*["']([\d.]+)''').firstMatch(tag);
    final h = RegExp(r'''height\s*=\s*["']([\d.]+)''').firstMatch(tag);
    if (w == null || h == null) return bytes;

    final patchedTag = tag.replaceFirst(
      '<svg',
      '<svg viewBox="0 0 ${w.group(1)} ${h.group(1)}"',
    );
    final patchedText = text.replaceRange(
      tagMatch.start,
      tagMatch.end,
      patchedTag,
    );
    return Uint8List.fromList(utf8.encode(patchedText));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(width: widget.width, height: widget.height ?? 20);
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return Icon(
            Icons.broken_image_outlined,
            size: widget.height ?? 24,
            color: Colors.grey,
          );
        }
        if (_looksLikeSvg(bytes)) {
          if (_containsSvgText(bytes)) {
            return const SizedBox.shrink();
          }
          var w = widget.width;
          var h = widget.height;
          final intrinsic = _svgIntrinsicSize(bytes);
          if (intrinsic != null) {
            final ratio = intrinsic.width / intrinsic.height;
            if (w == null && h == null) {
              h = 20;
              w = h * ratio;
            } else if (w == null) {
              w = h! * ratio;
            } else {
              h ??= w / ratio;
            }
          }
          return SvgPicture(
            SvgBytesLoader(_ensureViewBox(bytes)),
            width: w,
            height: h,
            fit: BoxFit.contain,
          );
        }
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          errorBuilder: (context, error, stack) => Icon(
            Icons.broken_image_outlined,
            size: widget.height ?? 24,
            color: Colors.grey,
          ),
        );
      },
    );
  }
}
