/// Pure text-manipulation helpers behind the mobile Markdown editor's
/// formatting toolbar and "continue list on Enter" behaviour. Kept
/// Flutter-free (plain String/int in, plain result out) so the logic can be
/// unit-tested without spinning up widgets, and wired into
/// [TextEditingValue]/[TextSelection] at the call site.
library;

/// A text edit plus the selection it leaves behind.
class EditResult {
  final String text;
  final int selectionStart;
  final int selectionEnd;

  const EditResult(this.text, this.selectionStart, this.selectionEnd);
}

int _lineStartOf(String text, int offset) {
  if (offset <= 0) return 0;
  final idx = text.lastIndexOf('\n', offset - 1);
  return idx == -1 ? 0 : idx + 1;
}

int _lineEndOf(String text, int start) {
  final idx = text.indexOf('\n', start);
  return idx == -1 ? text.length : idx;
}

/// Wraps the selected range with [prefix]/[suffix] (e.g. `**bold**`). With
/// no selection, inserts an empty pair and places the cursor between them
/// so the user can just start typing.
EditResult wrapSelection(
  String text,
  int start,
  int end,
  String prefix, [
  String? suffix,
]) {
  final actualSuffix = suffix ?? prefix;
  final selected = text.substring(start, end);
  final newText = text.replaceRange(
    start,
    end,
    '$prefix$selected$actualSuffix',
  );
  if (selected.isEmpty) {
    final cursor = start + prefix.length;
    return EditResult(newText, cursor, cursor);
  }
  final newStart = start + prefix.length;
  final newEnd = newStart + selected.length;
  return EditResult(newText, newStart, newEnd);
}

/// Toggles a literal prefix (`- `, `> `, `1. `, `- [ ] `) on the line the
/// cursor is on — removes it if already present, otherwise inserts it.
EditResult toggleLinePrefix(String text, int cursor, String prefix) {
  final start = _lineStartOf(text, cursor);
  final lineEnd = _lineEndOf(text, start);
  final line = text.substring(start, lineEnd);

  if (line.startsWith(prefix)) {
    final newText = text.replaceRange(start, start + prefix.length, '');
    final newCursor = (cursor - prefix.length).clamp(start, newText.length);
    return EditResult(newText, newCursor, newCursor);
  }

  final newText = text.replaceRange(start, start, prefix);
  final newCursor = cursor + prefix.length;
  return EditResult(newText, newCursor, newCursor);
}

/// Inserts a Markdown link. An empty selection gets an empty `[]()` with the
/// cursor left inside the brackets (ready to type the link text); a
/// non-empty selection becomes the link text, with the cursor left inside
/// the parens (ready to type/paste the URL).
EditResult insertLink(String text, int start, int end) {
  final selected = text.substring(start, end);
  if (selected.isEmpty) {
    final newText = text.replaceRange(start, end, '[]()');
    final cursor = start + 1;
    return EditResult(newText, cursor, cursor);
  }
  final newText = text.replaceRange(start, end, '[$selected]()');
  final cursor = start + selected.length + 3;
  return EditResult(newText, cursor, cursor);
}

/// Inserts a fenced code block. An empty selection gets an empty fence with
/// the cursor on the blank line inside; a non-empty selection is wrapped by
/// the fence in place.
EditResult insertCodeBlock(String text, int start, int end) {
  final selected = text.substring(start, end);
  if (selected.isEmpty) {
    final newText = text.replaceRange(start, end, '```\n\n```');
    final cursor = start + 4;
    return EditResult(newText, cursor, cursor);
  }
  final newText = text.replaceRange(start, end, '```\n$selected\n```');
  final newStart = start + 4;
  final newEnd = newStart + selected.length;
  return EditResult(newText, newStart, newEnd);
}

final _headingPattern = RegExp(r'^(#{1,6})\s');

/// Cycles the current line through no-heading → `#` → `##` → `###` →
/// back to no-heading, since a toolbar tap has no notion of "which level".
EditResult cycleHeading(String text, int cursor) {
  final start = _lineStartOf(text, cursor);
  final lineEnd = _lineEndOf(text, start);
  final line = text.substring(start, lineEnd);

  final match = _headingPattern.firstMatch(line);
  final currentLevel = match == null ? 0 : match.group(1)!.length;
  final oldPrefixLen = match == null ? 0 : match.group(0)!.length;
  final nextLevel = currentLevel >= 3 ? 0 : currentLevel + 1;
  final newPrefix = nextLevel == 0 ? '' : '${'#' * nextLevel} ';

  final newText = text.replaceRange(start, start + oldPrefixLen, newPrefix);
  final delta = newPrefix.length - oldPrefixLen;
  final newCursor = (cursor + delta).clamp(start, newText.length);
  return EditResult(newText, newCursor, newCursor);
}

/// The result of continuing (or exiting) a list after pressing Enter.
class ListContinuationResult {
  final String text;
  final int cursor;

  const ListContinuationResult(this.text, this.cursor);
}

final _listItemPattern = RegExp(r'^(\s*)([-*+]|\d+\.)(\s+)(\[[ xX]\]\s+)?');
final _orderedMarkerPattern = RegExp(r'^(\d+)\.$');

/// Given the text right after a `\n` was inserted at [newlineIndex], decides
/// whether the line it just split off of was a list item — and if so,
/// either continues the list (same marker, incremented number for ordered
/// lists, fresh unchecked box for task lists) or, if that item was empty,
/// exits the list by stripping the now-orphaned marker instead of piling up
/// empty bullets forever. Returns `null` when the split line wasn't a list
/// item at all, so the caller should leave the plain newline alone.
ListContinuationResult? computeEnterListContinuation(
  String textAfterInsertion,
  int newlineIndex,
) {
  final before = textAfterInsertion.substring(0, newlineIndex);
  final lineStart = before.lastIndexOf('\n') + 1;
  final currentLine = before.substring(lineStart);

  final match = _listItemPattern.firstMatch(currentLine);
  if (match == null) return null;

  final indent = match.group(1) ?? '';
  final marker = match.group(2)!;
  final spacing = match.group(3) ?? ' ';
  final checkbox = match.group(4);
  final contentAfter = currentLine.substring(match.end);

  if (contentAfter.trim().isEmpty) {
    final newText =
        textAfterInsertion.substring(0, lineStart) +
        indent +
        textAfterInsertion.substring(newlineIndex);
    final newCursor = lineStart + indent.length + 1;
    return ListContinuationResult(newText, newCursor);
  }

  var continuationMarker = marker;
  final ordered = _orderedMarkerPattern.firstMatch(marker);
  if (ordered != null) {
    continuationMarker = '${int.parse(ordered.group(1)!) + 1}.';
  }

  final continuation =
      indent + continuationMarker + spacing + (checkbox != null ? '[ ] ' : '');
  final insertAt = newlineIndex + 1;
  final newText =
      textAfterInsertion.substring(0, insertAt) +
      continuation +
      textAfterInsertion.substring(insertAt);
  final newCursor = insertAt + continuation.length;
  return ListContinuationResult(newText, newCursor);
}
