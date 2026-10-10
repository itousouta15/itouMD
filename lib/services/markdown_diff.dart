/// Line-level diff and three-way merge used by the sync conflict screen.
///
/// Pure Dart ??no Flutter imports ??so the logic is unit-testable in
/// isolation. Line endings are normalised to `\n` before comparing so that
/// CRLF/LF noise never shows up as a phantom conflict.
library;

/// A block of merged output. [TextSegment] is settled text (base copy or an
/// auto-applied change); [ConflictSegment] is a region both sides edited,
/// carrying the local and remote variants for the user to choose between.
sealed class MergeSegment {
  const MergeSegment();
}

class TextSegment extends MergeSegment {
  final String text;
  const TextSegment(this.text);
}

class ConflictSegment extends MergeSegment {
  final String local;
  final String remote;

  const ConflictSegment({required this.local, required this.remote});
}

/// A remote-side change that was merged in automatically because it didn't
/// touch any lines the local side also changed.
class AutoAppliedHunk {
  /// Base lines the remote side deleted in this hunk.
  final List<String> removed;

  /// Lines the remote side inserted in this hunk.
  final List<String> added;

  const AutoAppliedHunk({required this.removed, required this.added});
}

/// A line-level change between two texts: [removed] lines from the original
/// were replaced by [added] lines (either may be empty for pure
/// insert/delete hunks).
class DiffHunk {
  final List<String> removed;
  final List<String> added;

  const DiffHunk({required this.removed, required this.added});
}

/// Two-way line diff: what it would take to turn [original] into [revised]
/// (line endings normalised to `\n`). Used by the AI assistant's
/// add/remove preview — the same Myers machinery as the merge.
List<DiffHunk> diffTexts(String original, String revised) {
  final a = _lines(original);
  final b = _lines(revised);
  final hunks = _toHunks(a, b);
  return hunks
      .map(
        (h) => DiffHunk(
          removed: a.sublist(h.baseStart, h.baseEnd).toList(),
          added: h.lines,
        ),
      )
      .toList();
}

/// Total added/removed line counts across [hunks].
(int added, int removed) diffStats(List<DiffHunk> hunks) {
  var added = 0;
  var removed = 0;
  for (final hunk in hunks) {
    added += hunk.added.length;
    removed += hunk.removed.length;
  }
  return (added, removed);
}

class MergeResult {
  final List<MergeSegment> segments;
  final List<AutoAppliedHunk> autoApplied;
  final int remoteAddedLines;
  final int remoteRemovedLines;

  const MergeResult({
    required this.segments,
    required this.autoApplied,
    required this.remoteAddedLines,
    required this.remoteRemovedLines,
  });

  /// The merged text with every conflict resolved towards [useLocal].
  String resolve({required bool useLocal}) {
    final buffer = StringBuffer();
    for (final segment in segments) {
      switch (segment) {
        case TextSegment(:final text):
          buffer.write(text);
        case ConflictSegment(:final local, :final remote):
          buffer.write(useLocal ? local : remote);
      }
    }
    return buffer.toString();
  }

  int get conflictCount => segments.whereType<ConflictSegment>().length;
}

enum _Op { keep, add, remove }

class _Hunk {
  final int baseStart;
  final int baseEnd;
  final List<String> lines;

  const _Hunk({
    required this.baseStart,
    required this.baseEnd,
    required this.lines,
  });

  bool get isInsertion => baseStart == baseEnd;
}

List<String> _lines(String s) {
  final normalized = s.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Classic Myers O(ND) shortest edit script, backtracked into a forward ops
/// list ([keep] first).
List<_Op> _myers(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final v = <int, int>{1: 0};
  final trace = <Map<int, int>>[];
  var foundD = -1;
  for (var rd = 0; rd <= n + m && foundD < 0; rd++) {
    trace.add(Map<int, int>.from(v));
    for (var k = -rd; k <= rd; k += 2) {
      int x;
      if (k == -rd || (k != rd && v[k - 1]! < v[k + 1]!)) {
        x = v[k + 1]!;
      } else {
        x = v[k - 1]! + 1;
      }
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[k] = x;
      if (x >= n && y >= m) {
        foundD = rd;
        break;
      }
    }
  }

  final ops = <_Op>[];
  var x = n;
  var y = m;
  for (var dd = foundD; dd > 0; dd--) {
    final vPrev = trace[dd];
    final k = x - y;
    final prevK = (k == -dd || (k != dd && vPrev[k - 1]! < vPrev[k + 1]!))
        ? k + 1
        : k - 1;
    final prevX = vPrev[prevK]!;
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      ops.add(_Op.keep);
      x--;
      y--;
    }
    if (x == prevX) {
      ops.add(_Op.add);
    } else {
      ops.add(_Op.remove);
    }
    x = prevX;
    y = prevY;
  }
  while (x > 0 && y > 0) {
    ops.add(_Op.keep);
    x--;
    y--;
  }
  return ops.reversed.toList();
}

/// Groups a diff's ops into non-overlapping hunks in base coordinates.
List<_Hunk> _toHunks(List<String> baseLines, List<String> newLines) {
  final ops = _myers(baseLines, newLines);
  final hunks = <_Hunk>[];
  var baseStart = -1;
  var baseEnd = 0;
  final added = <String>[];
  var bi = 0;
  var ni = 0;

  void flush() {
    if (baseStart == -1) return;
    hunks.add(
      _Hunk(baseStart: baseStart, baseEnd: baseEnd, lines: List.of(added)),
    );
    baseStart = -1;
    added.clear();
  }

  for (final op in ops) {
    switch (op) {
      case _Op.keep:
        flush();
        bi++;
        ni++;
      case _Op.remove:
        if (baseStart == -1) baseStart = bi;
        bi++;
        baseEnd = bi;
      case _Op.add:
        if (baseStart == -1) baseStart = bi;
        added.add(newLines[ni++]);
        baseEnd = bi;
    }
  }
  flush();
  return hunks;
}

MergeResult mergeLines(String base, String local, String remote) {
  // Keep line terminators in merge tokens: otherwise an empty document becomes
  // a blank line and every sync silently adds a final newline.
  List<String> tokens(String text) => RegExp(r'[^\n]*\n|[^\n]+$')
      .allMatches(text.replaceAll('\r\n', '\n'))
      .map((match) => match[0]!)
      .toList();
  List<String> displayLines(List<String> lines) => lines
      .map(
        (line) =>
            line.endsWith('\n') ? line.substring(0, line.length - 1) : line,
      )
      .toList();
  final b = tokens(base);
  final l = tokens(local);
  final r = tokens(remote);
  final lHunks = _toHunks(b, l);
  final rHunks = _toHunks(b, r);
  final segments = <MergeSegment>[];
  final autoApplied = <AutoAppliedHunk>[];
  final changes =
      [
        for (final hunk in lHunks) (local: true, hunk: hunk),
        for (final hunk in rHunks) (local: false, hunk: hunk),
      ]..sort((a, b) {
        final order = a.hunk.baseStart.compareTo(b.hunk.baseStart);
        return order != 0 ? order : a.hunk.baseEnd.compareTo(b.hunk.baseEnd);
      });

  List<String> variant(List<_Hunk> hunks, int start, int end) {
    final lines = <String>[];
    var cursor = start;
    for (final hunk in hunks) {
      lines.addAll(b.sublist(cursor, hunk.baseStart));
      lines.addAll(hunk.lines);
      cursor = hunk.baseEnd;
    }
    lines.addAll(b.sublist(cursor, end));
    return lines;
  }

  // Merge two sides whose replaced base ranges are disjoint. Returns null when
  // either side is an insertion, when the ranges overlap, or when splicing the
  // two edits together would fuse two tokens into a single line (the one
  // outcome the conflict screen must never produce silently).
  List<String>? autoMerge(
    List<_Hunk> local,
    List<_Hunk> remote,
    int start,
    int end,
  ) {
    if (local.any((h) => h.isInsertion) || remote.any((h) => h.isInsertion)) {
      return null;
    }
    final all = [...local, ...remote]
      ..sort((a, c) => a.baseStart.compareTo(c.baseStart));
    var previousEnd = start;
    for (final hunk in all) {
      if (hunk.baseStart < previousEnd || hunk.baseEnd > end) return null;
      previousEnd = hunk.baseEnd;
    }
    final merged = <String>[];
    var at = start;
    for (final hunk in all) {
      merged.addAll(b.sublist(at, hunk.baseStart));
      merged.addAll(hunk.lines);
      at = hunk.baseEnd;
    }
    merged.addAll(b.sublist(at, end));
    // Any token that is followed by more output must end a line; otherwise the
    // merge would concatenate two lines. Defer to a conflict in that case.
    for (var j = 0; j + 1 < merged.length; j++) {
      if (!merged[j].endsWith('\n')) return null;
    }
    if (merged.isNotEmpty && !merged.last.endsWith('\n') && end < b.length) {
      return null;
    }
    return merged;
  }

  // Group touching or overlapping changes into one region. Each conflict then
  // carries both FULL variants of the region, including unchanged lines one side
  // still retains. Genuinely independent edits on disjoint lines still merge.
  var cursor = 0;
  var index = 0;
  while (index < changes.length) {
    final start = changes[index].hunk.baseStart;
    var end = changes[index].hunk.baseEnd;
    final localHunks = <_Hunk>[];
    final remoteHunks = <_Hunk>[];
    do {
      final change = changes[index++];
      (change.local ? localHunks : remoteHunks).add(change.hunk);
      if (change.hunk.baseEnd > end) end = change.hunk.baseEnd;
    } while (index < changes.length && changes[index].hunk.baseStart <= end);
    segments.add(TextSegment(b.sublist(cursor, start).join()));
    final left = variant(localHunks, start, end);
    final right = variant(remoteHunks, start, end);
    if (localHunks.isEmpty) {
      segments.add(TextSegment(right.join()));
      autoApplied.add(
        AutoAppliedHunk(
          removed: displayLines(b.sublist(start, end)),
          added: displayLines(right),
        ),
      );
    } else if (remoteHunks.isEmpty) {
      segments.add(TextSegment(left.join()));
    } else if (listEquals(left, right)) {
      segments.add(TextSegment(left.join()));
    } else {
      final merged = autoMerge(localHunks, remoteHunks, start, end);
      if (merged != null) {
        segments.add(TextSegment(merged.join()));
      } else {
        segments.add(ConflictSegment(local: left.join(), remote: right.join()));
      }
    }
    cursor = end;
  }
  segments.add(TextSegment(b.sublist(cursor).join()));

  return MergeResult(
    segments: segments,
    autoApplied: autoApplied,
    remoteAddedLines: rHunks.fold(
      0,
      (count, hunk) => count + hunk.lines.length,
    ),
    remoteRemovedLines: rHunks.fold(
      0,
      (count, hunk) => count + hunk.baseEnd - hunk.baseStart,
    ),
  );
}

bool listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
