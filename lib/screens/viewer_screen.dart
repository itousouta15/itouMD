import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:fwfh_svg/fwfh_svg.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/all.dart' show allLanguages;
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/markdown_editor_actions.dart';
import '../services/markdown_renderer.dart';
import '../services/reader_prefs.dart';
import '../services/recent_docs.dart';
import '../theme.dart';
import '../widgets/loader_ring.dart';

/// Turns "press Enter on a list item" into "continue the list" instead of a
/// bare newline — the single biggest bit of editor friction on mobile,
/// where retyping `- ` for every line is tedious with no physical keyboard.
class _MarkdownListContinuationFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Don't interfere mid-IME-composition (CJK input etc.).
    if (newValue.composing != TextRange.empty) return newValue;
    if (newValue.text.length != oldValue.text.length + 1) return newValue;
    if (!newValue.selection.isCollapsed) return newValue;

    final insertionIndex = newValue.selection.baseOffset - 1;
    if (insertionIndex < 0 || insertionIndex >= newValue.text.length) {
      return newValue;
    }
    if (newValue.text[insertionIndex] != '\n') return newValue;

    final result = computeEnterListContinuation(newValue.text, insertionIndex);
    if (result == null) return newValue;

    return TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }
}

var _highlightLanguagesRegistered = false;

/// `highlight.parse` falls back to plain text for an unregistered language
/// rather than throwing, but it only knows about languages we've registered
/// — do it once, lazily, instead of at every `pre` block render.
void _ensureHighlightLanguagesRegistered() {
  if (_highlightLanguagesRegistered) return;
  highlight.registerLanguages(allLanguages);
  _highlightLanguagesRegistered = true;
}

/// Many badge/status-image services (shields.io and friends) serve SVG
/// without a `.svg` extension in the URL, so [SvgFactory]'s suffix check
/// misses them. This sniffs the actual response bytes for network images
/// and routes to [SvgPicture] or a raster [Image] accordingly.
class _SvgAwareWidgetFactory extends WidgetFactory with SvgFactory {
  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final url = src.url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return _SniffedNetworkImage(
        url: url,
        width: src.width,
        height: src.height,
      );
    }
    return super.buildImageWidget(tree, src);
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

class _SniffedNetworkImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;

  const _SniffedNetworkImage({required this.url, this.width, this.height});

  @override
  State<_SniffedNetworkImage> createState() => _SniffedNetworkImageState();
}

class _SniffedNetworkImageState extends State<_SniffedNetworkImage> {
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

class ViewerScreen extends StatefulWidget {
  final String title;
  final String content;
  final RecentDocSource source;
  final String? sourceRef;

  const ViewerScreen({
    super.key,
    required this.title,
    required this.content,
    this.source = RecentDocSource.paste,
    this.sourceRef,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  ReaderPrefs _prefs = const ReaderPrefs();
  // Parsing runs on a background isolate (see [convertMarkdownToHtml]) so
  // opening a large document doesn't freeze the navigation transition; null
  // just means "still converting", shown as a loading state below.
  String? _html;
  late String _content = widget.content;
  late final _editController = TextEditingController(text: widget.content);
  final _editFocusNode = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    ReaderPrefs.load().then((loaded) {
      if (mounted) setState(() => _prefs = loaded);
    });
    _render(_content);
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  /// Applies a pure [EditResult] to the controller and hands focus straight
  /// back to the field, since tapping a toolbar button would otherwise steal
  /// focus from the [TextField] and dismiss the keyboard.
  void _applyEditResult(EditResult result) {
    _editController.value = TextEditingValue(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selectionStart,
        extentOffset: result.selectionEnd,
      ),
    );
    _editFocusNode.requestFocus();
  }

  int get _safeCursor {
    final offset = _editController.selection.baseOffset;
    return offset < 0 ? _editController.text.length : offset;
  }

  (int, int) get _safeSelection {
    final sel = _editController.selection;
    if (!sel.isValid) {
      final end = _editController.text.length;
      return (end, end);
    }
    return (sel.start, sel.end);
  }

  void _toolbarWrap(String prefix, [String? suffix]) {
    final (start, end) = _safeSelection;
    _applyEditResult(
      wrapSelection(_editController.text, start, end, prefix, suffix),
    );
  }

  void _toolbarLinePrefix(String prefix) {
    _applyEditResult(
      toggleLinePrefix(_editController.text, _safeCursor, prefix),
    );
  }

  void _toolbarHeading() {
    _applyEditResult(cycleHeading(_editController.text, _safeCursor));
  }

  void _toolbarLink() {
    final (start, end) = _safeSelection;
    _applyEditResult(insertLink(_editController.text, start, end));
  }

  void _toolbarCodeBlock() {
    final (start, end) = _safeSelection;
    _applyEditResult(insertCodeBlock(_editController.text, start, end));
  }

  void _render(String markdown) {
    _html = null;
    compute(convertMarkdownToHtml, markdown).then((html) {
      if (mounted) setState(() => _html = html);
    });
  }

  /// Leaves edit mode, re-renders the preview from the edited text, and
  /// persists the change to the recent-docs entry (matched by title+source)
  /// so reopening the doc later — from "最近開啟" — shows the edit. Writing
  /// the edit back to an actual file on disk is a separate, explicit
  /// "另存新檔" action, since silently overwriting the original is riskier
  /// and Android's scoped storage often can't do it reliably anyway.
  Future<void> _applyEdit() async {
    final edited = _editController.text;
    setState(() {
      _editing = false;
      _content = edited;
    });
    _render(edited);
    await RecentDocs.add(
      RecentDoc(
        title: widget.title,
        content: edited,
        source: widget.source,
        sourceRef: widget.sourceRef,
        openedAt: DateTime.now(),
      ),
    );
  }

  void _enterEdit() {
    _editController.text = _content;
    setState(() => _editing = true);
  }

  Future<void> _saveAs(BuildContext context) async {
    final text = _editing ? _editController.text : _content;
    final safeTitle = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: '另存新檔',
        fileName: safeTitle.toLowerCase().endsWith('.md')
            ? safeTitle
            : '$safeTitle.md',
        type: FileType.custom,
        allowedExtensions: ['md'],
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
      if (!context.mounted) return;
      if (path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已另存新檔 (｡•ᴗ•｡)')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('儲存失敗，再試一次看看 (´;ω;`)')));
    }
  }

  void _updatePrefs(ReaderPrefs next) {
    setState(() => _prefs = next);
    next.save();
  }

  /// Renders as `rgba(...)` rather than hex — several of our theme tokens
  /// (border, border2, ...) are intentionally translucent, and a plain hex
  /// string silently drops the alpha channel, turning them fully opaque.
  static String _hex(Color c) {
    int ch(double v) => (v * 255.0).round().clamp(0, 255);
    final a = (c.a).clamp(0.0, 1.0);
    return 'rgba(${ch(c.r)}, ${ch(c.g)}, ${ch(c.b)}, ${a.toStringAsFixed(3)})';
  }

  /// Maps a GitHub-alert (`markdown-alert-note`) or HackMD-container
  /// (`hackmd-callout-info`) class string to a themed accent colour.
  static String? _calloutColor(
    String cls, {
    required String blueHex,
    required String purpleHex,
    required String successHex,
    required String warningHex,
    required String dangerHex,
  }) {
    if (cls.contains('-note') || cls.contains('-info')) return blueHex;
    if (cls.contains('-tip') || cls.contains('-success')) return successHex;
    if (cls.contains('-important')) return purpleHex;
    if (cls.contains('-warning')) return warningHex;
    if (cls.contains('-caution') || cls.contains('-danger')) return dangerHex;
    return null;
  }

  /// Renders a fenced code block (`<pre><code class="language-xxx">`) with
  /// syntax highlighting when a language was declared on the fence. Falls
  /// back to `null` (plain `customStylesBuilder`-styled text) for
  /// language-less blocks — `highlight`'s auto-detect scans every
  /// registered language synchronously on the UI thread, which is both
  /// slow for no real benefit and prone to mis-guessing plain output/trees
  /// as some obscure language.
  static Widget? _buildHighlightedCode({
    required dom.Element element,
    required bool isDark,
    required TextStyle mono,
    required double base,
    required ItouColors c,
  }) {
    final codeEl = element.children
        .where((e) => e.localName == 'code')
        .firstOrNull;
    if (codeEl == null) return null;

    final cls = codeEl.attributes['class'] ?? '';
    final langMatch = RegExp(r'language-(\S+)').firstMatch(cls);
    final lang = langMatch?.group(1);
    if (lang == null) return null;

    _ensureHighlightLanguagesRegistered();

    final baseTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final theme = Map<String, TextStyle>.from(baseTheme)
      ..['root'] = baseTheme['root']!.copyWith(
        backgroundColor: Colors.transparent,
      );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: c.inset,
        border: Border.all(color: c.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: HighlightView(
          codeEl.text,
          language: lang,
          theme: theme,
          textStyle: mono.copyWith(fontSize: base - 2, height: 1.5),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final html = _html;
    if (html == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title, overflow: TextOverflow.ellipsis),
        ),
        body: const Center(child: LoaderRing()),
      );
    }

    final c = ItouColorsExt.of(context);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final family = _prefs.fontFamily.textStyle();
    final mono = ReaderFontFamily.mono.textStyle();
    final textColor = _prefs.textColor.resolve(c, brightness);
    final base = _prefs.fontSize;

    final textHex = _hex(textColor);
    final dimHex = _hex(c.dim);
    final muteHex = _hex(c.mute);
    final blueHex = _hex(c.blue);
    final purpleHex = _hex(c.purple);
    final panelHex = _hex(c.panel);
    final insetHex = _hex(c.inset);
    final borderHex = _hex(c.border);
    final border2Hex = _hex(c.border2);
    const successHex = '#7fae83';
    const warningHex = '#ad8b5c';
    const dangerHex = '#e0777a';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _editing ? '完成編輯' : '編輯',
            icon: Icon(_editing ? Icons.done_outlined : Icons.edit_outlined),
            onPressed: _editing ? _applyEdit : _enterEdit,
          ),
          IconButton(
            tooltip: '另存新檔',
            icon: const Icon(Icons.save_alt_outlined),
            onPressed: () => _saveAs(context),
          ),
          if (!_editing) ...[
            IconButton(
              tooltip: '顯示設定',
              icon: const Icon(Icons.text_fields_outlined),
              onPressed: () => _openReaderSettings(context),
            ),
            IconButton(
              tooltip: '複製原始碼',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => _copyRaw(context),
            ),
          ],
        ],
      ),
      body: _editing
          ? Column(
              children: [
                Expanded(
                  child: Container(
                    color: c.bg,
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _editController,
                      focusNode: _editFocusNode,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      inputFormatters: [_MarkdownListContinuationFormatter()],
                      style: mono.copyWith(
                        color: c.text,
                        fontSize: base - 1,
                        height: 1.5,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                _EditorToolbar(
                  c: c,
                  onHeading: _toolbarHeading,
                  onBold: () => _toolbarWrap('**'),
                  onItalic: () => _toolbarWrap('_'),
                  onStrikethrough: () => _toolbarWrap('~~'),
                  onInlineCode: () => _toolbarWrap('`'),
                  onCodeBlock: _toolbarCodeBlock,
                  onQuote: () => _toolbarLinePrefix('> '),
                  onBulletList: () => _toolbarLinePrefix('- '),
                  onNumberedList: () => _toolbarLinePrefix('1. '),
                  onTaskList: () => _toolbarLinePrefix('- [ ] '),
                  onLink: _toolbarLink,
                ),
              ],
            )
          : Container(
              color: c.bg,
              child: SelectionArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  child: HtmlWidget(
                    html,
                    factoryBuilder: () => _SvgAwareWidgetFactory(),
                    textStyle: family.copyWith(
                      color: textColor,
                      fontSize: base,
                      height: 1.65,
                    ),
                    onTapUrl: (url) async {
                      final uri = Uri.tryParse(url);
                      if (uri != null) await launchUrl(uri);
                      return true;
                    },
                    customWidgetBuilder: (element) {
                      if (element.localName == 'pre') {
                        return _buildHighlightedCode(
                          element: element,
                          isDark: isDark,
                          mono: mono,
                          base: base,
                          c: c,
                        );
                      }
                      if (element.localName != 'x-latex') return null;
                      final encoded = element.attributes['data-tex'] ?? '';
                      final display =
                          element.attributes['data-mode'] == 'display';
                      String tex;
                      try {
                        tex = utf8.decode(base64Decode(encoded));
                      } catch (_) {
                        tex = '';
                      }
                      final mathWidget = Math.tex(
                        tex,
                        mathStyle: display ? MathStyle.display : MathStyle.text,
                        textStyle: family.copyWith(
                          color: textColor,
                          fontSize: base,
                        ),
                        onErrorFallback: (err) => Text(
                          '⚠ LaTeX 語法錯誤',
                          style: TextStyle(color: c.mute, fontSize: base - 2),
                        ),
                      );
                      if (!display) return mathWidget;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: mathWidget),
                      );
                    },
                    customStylesBuilder: (element) {
                      switch (element.localName) {
                        case 'x-latex':
                          return element.attributes['data-mode'] == 'display'
                              ? {'display': 'block'}
                              : null;
                        case 'h1':
                          return {
                            'color': textHex,
                            'font-family': family.fontFamily ?? '',
                            'font-size': '${base + 10.5}px',
                            'font-weight': '700',
                            'border-bottom': '1px solid $border2Hex',
                            'padding': '0 0 8px 0',
                            'margin': '4px 0 14px 0',
                          };
                        case 'h2':
                          return {
                            'color': textHex,
                            'font-family': family.fontFamily ?? '',
                            'font-size': '${base + 5.5}px',
                            'font-weight': '700',
                            'border-bottom': '1px solid $border2Hex',
                            'padding': '0 0 6px 0',
                            'margin': '4px 0 12px 0',
                          };
                        case 'h3':
                          return {
                            'color': textHex,
                            'font-family': family.fontFamily ?? '',
                            'font-size': '${base + 2.5}px',
                            'font-weight': '600',
                          };
                        case 'h4':
                          return {'color': textHex, 'font-weight': '600'};
                        case 'h5':
                          return {
                            'color': dimHex,
                            'font-size': '${base - 1.5}px',
                            'font-weight': '600',
                          };
                        case 'h6':
                          return {
                            'color': muteHex,
                            'font-size': '${base - 2.5}px',
                            'font-weight': '600',
                          };
                        case 'p':
                          final cls = element.attributes['class'] ?? '';
                          if (cls.contains('-title')) {
                            final calloutHex = _calloutColor(
                              cls,
                              blueHex: blueHex,
                              purpleHex: purpleHex,
                              successHex: successHex,
                              warningHex: warningHex,
                              dangerHex: dangerHex,
                            );
                            return {
                              'color': calloutHex ?? textHex,
                              'font-weight': '700',
                              'margin': '0 0 4px 0',
                            };
                          }
                          return {'color': textHex};
                        case 'li':
                          return {'color': textHex};
                        case 'div':
                          {
                            final cls = element.attributes['class'] ?? '';
                            final calloutHex = _calloutColor(
                              cls,
                              blueHex: blueHex,
                              purpleHex: purpleHex,
                              successHex: successHex,
                              warningHex: warningHex,
                              dangerHex: dangerHex,
                            );
                            if (calloutHex == null) return null;
                            return {
                              'border-left': '3px solid $calloutHex',
                              'background-color': panelHex,
                              'padding': '10px 14px',
                              'margin': '8px 0',
                              'color': textHex,
                            };
                          }
                        case 'strong':
                        case 'b':
                          return {'color': textHex, 'font-weight': '700'};
                        case 'em':
                        case 'i':
                          return {'color': dimHex};
                        case 'del':
                        case 's':
                          return {'color': dimHex};
                        case 'blockquote':
                          return {
                            'border-left': '3px solid $blueHex',
                            'background-color': panelHex,
                            'padding': '10px 14px',
                            'margin': '8px 0',
                            'color': dimHex,
                          };
                        case 'code':
                          return {
                            'color': purpleHex,
                            'background-color': insetHex,
                            'font-family': mono.fontFamily ?? '',
                            'font-size': '${base - 2}px',
                          };
                        case 'pre':
                          return {
                            'background-color': insetHex,
                            'border': '1px solid $borderHex',
                            'padding': '12px',
                          };
                        case 'a':
                          return {'color': blueHex};
                        case 'hr':
                          return {
                            'border': 'none',
                            'border-top': '1px solid $border2Hex',
                          };
                        case 'th':
                          return {
                            'color': textHex,
                            'font-family': mono.fontFamily ?? '',
                            'font-weight': '600',
                            'font-size': '${base - 3}px',
                            'letter-spacing': '0.4px',
                            'border': 'none',
                            'border-bottom': '2px solid $blueHex',
                            'padding': '9px 12px',
                            'text-align': 'left',
                          };
                        case 'td':
                          return {
                            'color': textHex,
                            'font-size': '${base - 2}px',
                            'border': 'none',
                            'border-bottom': '1px solid $borderHex',
                            'padding': '9px 12px',
                          };
                        case 'tr':
                          {
                            final parent = element.parent;
                            if (parent == null || parent.localName != 'tbody') {
                              return null;
                            }
                            final rows = parent.children
                                .where((e) => e.localName == 'tr')
                                .toList();
                            final rowIndex = rows.indexOf(element);
                            if (rowIndex >= 0 && rowIndex.isOdd) {
                              return {'background-color': insetHex};
                            }
                            return null;
                          }
                        case 'table':
                          return {'border': 'none'};
                      }
                      return null;
                    },
                  ),
                ),
              ),
            ),
    );
  }

  void _copyRaw(BuildContext context) {
    Clipboard.setData(
      ClipboardData(text: _editing ? _editController.text : _content),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('原始 Markdown 已複製到剪貼簿 (｡•ᴗ•｡)')),
    );
  }

  void _openReaderSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _ReaderSettingsSheet(prefs: _prefs, onChanged: _updatePrefs);
      },
    );
  }
}

/// A horizontally-scrolling row of Markdown formatting shortcuts, docked
/// directly above the keyboard (it's the last child in the edit body's
/// [Column], which the [Scaffold] pushes up above the software keyboard
/// automatically) so common syntax doesn't have to be typed by hand.
class _EditorToolbar extends StatelessWidget {
  final ItouColors c;
  final VoidCallback onHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onStrikethrough;
  final VoidCallback onInlineCode;
  final VoidCallback onCodeBlock;
  final VoidCallback onQuote;
  final VoidCallback onBulletList;
  final VoidCallback onNumberedList;
  final VoidCallback onTaskList;
  final VoidCallback onLink;

  const _EditorToolbar({
    required this.c,
    required this.onHeading,
    required this.onBold,
    required this.onItalic,
    required this.onStrikethrough,
    required this.onInlineCode,
    required this.onCodeBlock,
    required this.onQuote,
    required this.onBulletList,
    required this.onNumberedList,
    required this.onTaskList,
    required this.onLink,
  });

  Widget _btn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      color: c.text,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      // Toolbar taps must not steal keyboard focus from the TextField —
      // handled by the callbacks themselves (they re-request focus after
      // editing the controller), not by anything here.
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn(Icons.title, '標題', onHeading),
              _btn(Icons.format_bold, '粗體', onBold),
              _btn(Icons.format_italic, '斜體', onItalic),
              _btn(Icons.strikethrough_s, '刪除線', onStrikethrough),
              _btn(Icons.code, '行內程式碼', onInlineCode),
              _btn(Icons.data_object, '程式碼區塊', onCodeBlock),
              _btn(Icons.format_quote, '引用', onQuote),
              _btn(Icons.format_list_bulleted, '項目清單', onBulletList),
              _btn(Icons.format_list_numbered, '編號清單', onNumberedList),
              _btn(Icons.check_box_outlined, '待辦清單', onTaskList),
              _btn(Icons.link, '連結', onLink),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderSettingsSheet extends StatefulWidget {
  final ReaderPrefs prefs;
  final ValueChanged<ReaderPrefs> onChanged;

  const _ReaderSettingsSheet({required this.prefs, required this.onChanged});

  @override
  State<_ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<_ReaderSettingsSheet> {
  late ReaderPrefs _prefs = widget.prefs;

  void _update(ReaderPrefs next) {
    setState(() => _prefs = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final brightness = Theme.of(context).brightness;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.panel,
          border: Border.all(color: c.border2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel('字體'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReaderFontFamily.values.map((f) {
                final selected = _prefs.fontFamily == f;
                return SizedBox(
                  width: 78,
                  child: _ChoiceTile(
                    label: f.label,
                    selected: selected,
                    previewStyle: f.textStyle(),
                    onTap: () => _update(_prefs.copyWith(fontFamily: f)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                SectionLabel('字級'),
                const Spacer(),
                Text(
                  _prefs.fontSize.toStringAsFixed(0),
                  style: TextStyle(color: c.dim, fontSize: 12),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: c.blue,
                inactiveTrackColor: c.border2,
                thumbColor: c.blue,
                overlayColor: c.blue.withValues(alpha: 0.15),
                trackHeight: 2,
              ),
              child: Slider(
                value: _prefs.fontSize,
                min: ReaderPrefs.minFontSize,
                max: ReaderPrefs.maxFontSize,
                divisions:
                    ((ReaderPrefs.maxFontSize - ReaderPrefs.minFontSize) / 0.5)
                        .round(),
                onChanged: (v) => _update(_prefs.copyWith(fontSize: v)),
              ),
            ),
            const SizedBox(height: 10),
            SectionLabel('文字顏色'),
            const SizedBox(height: 12),
            Row(
              children: ReaderTextColor.values.map((tc) {
                final selected = _prefs.textColor == tc;
                final swatch = tc.resolve(c, brightness);
                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: GestureDetector(
                    onTap: () => _update(_prefs.copyWith(textColor: tc)),
                    child: Column(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: swatch,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? c.blue : c.border2,
                              width: selected ? 2.5 : 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tc.label,
                          style: TextStyle(color: c.dim, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final TextStyle? previewStyle;

  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.previewStyle,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final base = previewStyle ?? const TextStyle();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.panelHover : c.inset,
          border: Border.all(color: selected ? c.blue : c.border),
        ),
        child: Text(
          label,
          style: base.copyWith(
            color: selected ? c.text : c.dim,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
