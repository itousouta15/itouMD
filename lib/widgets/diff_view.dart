import 'package:flutter/material.dart';

import '../services/markdown_diff.dart';
import '../theme.dart';

const kAddColor = Color(0xFF7FAE83);
const kDelColor = Color(0xFFE0777A);

/// Renders line-level [DiffHunk]s the way the sync conflict screen does:
/// removed lines in red with a `−` marker, added lines in green with a `+`
/// marker, each hunk capped at [maxLinesPerHunk] with a "還有 N 行" tail.
/// Shared by the conflict screen and the AI assistant's add/remove preview.
class DiffView extends StatelessWidget {
  final List<DiffHunk> hunks;
  final int maxLinesPerHunk;
  final ItouColors c;

  const DiffView({
    super.key,
    required this.hunks,
    this.maxLinesPerHunk = 6,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFamily: 'monospace',
      fontSize: 11.5,
      height: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final hunk in hunks) ...[
          for (final line in hunk.removed.take(maxLinesPerHunk))
            _DiffLine(
              text: line,
              color: kDelColor,
              marker: '−',
              mono: mono,
              c: c,
            ),
          if (hunk.removed.length > maxLinesPerHunk)
            _DiffMoreLine(
              count: hunk.removed.length - maxLinesPerHunk,
              color: kDelColor,
              c: c,
            ),
          for (final line in hunk.added.take(maxLinesPerHunk))
            _DiffLine(
              text: line,
              color: kAddColor,
              marker: '+',
              mono: mono,
              c: c,
            ),
          if (hunk.added.length > maxLinesPerHunk)
            _DiffMoreLine(
              count: hunk.added.length - maxLinesPerHunk,
              color: kAddColor,
              c: c,
            ),
        ],
      ],
    );
  }
}

class _DiffLine extends StatelessWidget {
  final String text;
  final Color color;
  final String marker;
  final TextStyle mono;
  final ItouColors c;

  const _DiffLine({
    required this.text,
    required this.color,
    required this.marker,
    required this.mono,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              child: Text(
                marker,
                style: mono.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text(
                text.isEmpty ? '（空行）' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffMoreLine extends StatelessWidget {
  final int count;
  final Color color;
  final ItouColors c;

  const _DiffMoreLine({
    required this.count,
    required this.color,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 2),
      child: Text(
        '… 還有 $count 行',
        style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
      ),
    );
  }
}
