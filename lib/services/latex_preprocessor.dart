import 'dart:convert';

/// Replaces LaTeX math spans (`$...$` and `$$...$$`) in [source] with
/// placeholder `<x-latex>` tags carrying base64-encoded TeX in a data
/// attribute, so the raw expression text never gets reinterpreted as
/// Markdown syntax (e.g. `_` inside a subscript). Fenced code blocks and
/// inline code spans are left completely untouched.
String protectMathAsHtml(String source) {
  final fence = RegExp(r'(^|\n)([`~]{3,})[^\n]*\n[\s\S]*?\n\2(?=\n|$)');
  final buffer = StringBuffer();
  var last = 0;
  for (final m in fence.allMatches(source)) {
    buffer.write(_protectProse(source.substring(last, m.start)));
    buffer.write(source.substring(m.start, m.end));
    last = m.end;
  }
  buffer.write(_protectProse(source.substring(last)));
  return buffer.toString();
}

String _protectProse(String text) {
  final inlineCode = RegExp(r'`[^`\n]+`');
  final buffer = StringBuffer();
  var last = 0;
  for (final m in inlineCode.allMatches(text)) {
    buffer.write(_replaceMath(text.substring(last, m.start)));
    buffer.write(text.substring(m.start, m.end));
    last = m.end;
  }
  buffer.write(_replaceMath(text.substring(last)));
  return buffer.toString();
}

String _replaceMath(String text) {
  text = text.replaceAllMapped(
    RegExp(r'\$\$([\s\S]+?)\$\$'),
    (m) => _tag(m.group(1)!, display: true),
  );
  text = text.replaceAllMapped(
    RegExp(r'\$([^\s$](?:[^$\n]*[^\s$])?)\$'),
    (m) => _tag(m.group(1)!, display: false),
  );
  return text;
}

String _tag(String tex, {required bool display}) {
  final encoded = base64Encode(utf8.encode(tex));
  final mode = display ? 'display' : 'inline';
  return '<x-latex data-tex="$encoded" data-mode="$mode"></x-latex>';
}
