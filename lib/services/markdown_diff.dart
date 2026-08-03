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
  final b = _lines(base);
  final l = _lines(local);
  final r = _lines(remote);
  final lHunks = _toHunks(b, l);
  final rHunks = _toHunks(b, r);

  final segments = <MergeSegment>[];
  final autoApplied = <AutoAppliedHunk>[];
  var removedCount = 0;
  var addedCount = 0;

  for (final h in rHunks) {
    removedCount += h.baseEnd - h.baseStart;
    addedCount += h.lines.length;
  }

  // Every emitted segment carries its own trailing newline, so the merged
  // result is a plain concatenation of segment texts. A pure deletion
  // (empty replacement) emits no text at all.
  String hunkText(_Hunk h) => h.lines.isEmpty ? '' : '${h.lines.join('\n')}\n';
  String lineText(String s) => '$s\n';

  // Base line index ??the hunk that replaces it (non-insertion hunks only).
  final lCoverage = <int, _Hunk>{};
  for (final h in lHunks) {
    if (h.isInsertion) continue;
    for (var j = h.baseStart; j < h.baseEnd; j++) {
      lCoverage[j] = h;
    }
  }
  final rCoverage = <int, _Hunk>{};
  for (final h in rHunks) {
    if (h.isInsertion) continue;
    for (var j = h.baseStart; j < h.baseEnd; j++) {
      rCoverage[j] = h;
    }
  }

  // Hunks whose base ranges overlap (both sides edited the same lines).
  final lConflictWith = <_Hunk, _Hunk>{};
  final rConflictWith = <_Hunk, _Hunk>{};
  for (final lh in lCoverage.values.toSet()) {
    for (final rh in rCoverage.values.toSet()) {
      if (lh.baseStart < rh.baseEnd && rh.baseStart < lh.baseEnd) {
        lConflictWith[lh] = rh;
        rConflictWith[rh] = lh;
      }
    }
  }

  final emittedL = <_Hunk>{};
  final emittedR = <_Hunk>{};

  // Both sides changed the same region. Identical changes are not a
  // conflict; only genuinely different variants are.
  void emitConflict(_Hunk lH, _Hunk rH) {
    if (listEquals(lH.lines, rH.lines)) {
      segments.add(TextSegment(hunkText(lH)));
    } else {
      segments.add(ConflictSegment(local: hunkText(lH), remote: hunkText(rH)));
    }
    emittedL.add(lH);
    emittedR.add(rH);
  }

  void emitLocalOnly(_Hunk h) {
    segments.add(TextSegment(hunkText(h)));
    emittedL.add(h);
  }

  void emitRemoteOnly(_Hunk h) {
    segments.add(TextSegment(hunkText(h)));
    emittedR.add(h);
    autoApplied.add(
      AutoAppliedHunk(
        removed: b.sublist(h.baseStart, h.baseEnd).toList(),
        added: h.lines,
      ),
    );
  }

  // Insertions attached to a boundary, pulled from the sorted hunk lists.
  List<_Hunk> takeInsertions(List<_Hunk> hunks, int at, int from) {
    final out = <_Hunk>[];
    var i = from;
    while (i < hunks.length &&
        (hunks[i].isInsertion && hunks[i].baseStart == at)) {
      out.add(hunks[i++]);
    }
    return out;
  }

  var li = 0;
  var ri = 0;

  void flushInsertions(int boundary) {
    final lIns = takeInsertions(lHunks, boundary, li);
    final rIns = takeInsertions(rHunks, boundary, ri);
    li += lIns.length;
    ri += rIns.length;
    if (lIns.isEmpty && rIns.isEmpty) return;
    if (lIns.isNotEmpty && rIns.isNotEmpty) {
      emitConflict(lIns.first, rIns.first);
    } else if (lIns.isNotEmpty) {
      segments.add(TextSegment(lIns.map(hunkText).join()));
    } else {
      segments.add(TextSegment(rIns.map(hunkText).join()));
      autoApplied.add(
        AutoAppliedHunk(
          removed: const [],
          added: rIns.expand((h) => h.lines).toList(),
        ),
      );
    }
  }

  for (var i = 0; i < b.length; i++) {
    flushInsertions(i);

    final lH = lCoverage[i];
    final rH = rCoverage[i];
    if (lH != null && rH != null) {
      // Both sides cover this line ??a conflict, emitted once at the first
      // overlapping line.
      if (emittedL.contains(lH) && emittedR.contains(rH)) continue;
      emitConflict(lH, rH);
      continue;
    }
    if (lH != null) {
      // Part of a conflict pair: wait for the overlap line instead of
      // emitting local-only text that the conflict would supersede.
      if (lConflictWith.containsKey(lH)) continue;
      if (emittedL.contains(lH)) continue;
      emitLocalOnly(lH);
      continue;
    }
    if (rH != null) {
      if (rConflictWith.containsKey(rH)) continue;
      if (emittedR.contains(rH)) continue;
      emitRemoteOnly(rH);
      continue;
    }

    segments.add(TextSegment(lineText(b[i])));
  }

  flushInsertions(b.length);

  return MergeResult(
    segments: segments,
    autoApplied: autoApplied,
    remoteAddedLines: addedCount,
    remoteRemovedLines: removedCount,
  );
}

bool listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
