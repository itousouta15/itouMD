import 'package:flutter/material.dart';

import '../services/markdown_diff.dart';
import '../theme.dart';

enum MergeAction { merged, overwrite }

class MergeOutcome {
  final MergeAction action;
  final String text;

  const MergeOutcome(this.action, this.text);
}

const _kMaxDiffLines = 6;

/// Conflict resolution UI for the sync flow. Shows what the remote changed
/// vs what's in the local copy, auto-merges non-conflicting remote changes,
/// and lets the user pick a variant for each genuine conflict.
class ConflictScreen extends StatefulWidget {
  final String base;
  final String local;
  final String remote;

  const ConflictScreen({
    super.key,
    required this.base,
    required this.local,
    required this.remote,
  });

  @override
  State<ConflictScreen> createState() => _ConflictScreenState();
}

class _ConflictScreenState extends State<ConflictScreen>
    with SingleTickerProviderStateMixin {
  late final MergeResult _result = mergeLines(
    widget.base,
    widget.local,
    widget.remote,
  );
  late final List<bool> _useLocal = List.filled(_result.conflictCount, true);
  late final AnimationController _enterCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  String get _mergedText {
    final buffer = StringBuffer();
    var conflictIdx = 0;
    for (final segment in _result.segments) {
      switch (segment) {
        case TextSegment(:final text):
          buffer.write(text);
        case ConflictSegment(:final local, :final remote):
          buffer.write(_useLocal[conflictIdx] ? local : remote);
          conflictIdx++;
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('合併衝突')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _EnterItem(
                  animation: _enterCtrl,
                  index: 0,
                  child: _SummaryPanel(result: _result, c: c),
                ),
                if (_result.autoApplied.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _EnterItem(
                    animation: _enterCtrl,
                    index: 1,
                    child: _AutoMergeSection(result: _result, c: c),
                  ),
                ],
                if (_result.conflictCount > 0) ...[
                  const SizedBox(height: 20),
                  _EnterItem(
                    animation: _enterCtrl,
                    index: 2,
                    child: _ConflictSection(
                      result: _result,
                      useLocal: _useLocal,
                      onChanged: (i, v) => setState(() => _useLocal[i] = v),
                      c: c,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _EnterItem(
                  animation: _enterCtrl,
                  index: 3,
                  child: _PreviewToggle(
                    expanded: _showPreview,
                    text: _mergedText,
                    onTap: () => setState(() => _showPreview = !_showPreview),
                    c: c,
                  ),
                ),
              ],
            ),
          ),
          _BottomBar(
            onCancel: () => Navigator.of(context).pop(),
            onOverwrite: () => Navigator.of(
              context,
            ).pop(MergeOutcome(MergeAction.overwrite, widget.local)),
            onMerge: () => Navigator.of(
              context,
            ).pop(MergeOutcome(MergeAction.merged, _mergedText)),
            c: c,
          ),
        ],
      ),
    );
  }
}

/// Staggered fade-and-rise entrance; each block starts a beat later than
/// the previous one so the sections read in order.
class _EnterItem extends StatelessWidget {
  final Animation<double> animation;
  final int index;
  final Widget child;

  const _EnterItem({
    required this.animation,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.12).clamp(0.0, 0.55);
    final anim = CurvedAnimation(
      parent: animation,
      curve: Interval(
        start,
        (start + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  final MergeResult result;
  final ItouColors c;

  const _SummaryPanel({required this.result, required this.c});

  @override
  Widget build(BuildContext context) {
    final add = result.remoteAddedLines;
    final del = result.remoteRemovedLines;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '遠端版本',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '+$add 行',
                style: const TextStyle(color: ItouColors.success, fontSize: 12),
              ),
              const SizedBox(width: 10),
              Text(
                '-$del 行',
                style: const TextStyle(color: ItouColors.danger, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.conflictCount > 0
                ? '兩邊都改到 ${result.conflictCount} 個區塊，需要你選擇要保留哪一邊。'
                : '遠端的新變更與你的編輯沒有衝突，會自動合併。',
            style: TextStyle(color: c.dim, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _AutoMergeSection extends StatelessWidget {
  final MergeResult result;
  final ItouColors c;

  const _AutoMergeSection({required this.result, required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '自動合併',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ItouColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '將自動合併',
                style: const TextStyle(color: ItouColors.success, fontSize: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.panel,
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var h = 0; h < result.autoApplied.length; h++) ...[
                if (h > 0) Divider(height: 1, thickness: 1, color: c.border),
                _HunkDiffView(hunk: result.autoApplied[h], c: c),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HunkDiffView extends StatelessWidget {
  final AutoAppliedHunk hunk;
  final ItouColors c;

  const _HunkDiffView({required this.hunk, required this.c});

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFamily: 'monospace',
      fontSize: 11.5,
      height: 1.5,
    );
    final removed = hunk.removed;
    final added = hunk.added;
    final removedShown = removed.take(_kMaxDiffLines).toList();
    final addedShown = added.take(_kMaxDiffLines).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in removedShown)
            _DiffLine(
              text: line,
              color: ItouColors.danger,
              marker: '−',
              mono: mono,
              c: c,
            ),
          if (removed.length > removedShown.length)
            _DiffMoreLine(
              count: removed.length - removedShown.length,
              color: ItouColors.danger,
              c: c,
            ),
          for (final line in addedShown)
            _DiffLine(
              text: line,
              color: ItouColors.success,
              marker: '+',
              mono: mono,
              c: c,
            ),
          if (added.length > addedShown.length)
            _DiffMoreLine(
              count: added.length - addedShown.length,
              color: ItouColors.success,
              c: c,
            ),
        ],
      ),
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

class _ConflictSection extends StatelessWidget {
  final MergeResult result;
  final List<bool> useLocal;
  final void Function(int, bool) onChanged;
  final ItouColors c;

  const _ConflictSection({
    required this.result,
    required this.useLocal,
    required this.onChanged,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final conflicts = result.segments.whereType<ConflictSegment>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '衝突區塊（${conflicts.length}）',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < conflicts.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ConflictCard(
            index: i,
            conflict: conflicts[i],
            useLocal: useLocal[i],
            onChanged: (v) => onChanged(i, v),
            c: c,
          ),
        ],
      ],
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final int index;
  final ConflictSegment conflict;
  final bool useLocal;
  final ValueChanged<bool> onChanged;
  final ItouColors c;

  const _ConflictCard({
    required this.index,
    required this.conflict,
    required this.useLocal,
    required this.onChanged,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFamily: 'monospace',
      fontSize: 11.5,
      height: 1.5,
    );
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              '衝突 ${index + 1} · 兩邊都改過這裡',
              style: TextStyle(color: c.mute, fontSize: 11),
            ),
          ),
          _VariantOption(
            label: '保留本地',
            icon: Icons.edit_outlined,
            text: conflict.local,
            selected: useLocal,
            mono: mono,
            c: c,
            onTap: () => onChanged(true),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
          _VariantOption(
            label: '保留遠端',
            icon: Icons.cloud_outlined,
            text: conflict.remote,
            selected: !useLocal,
            mono: mono,
            c: c,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _VariantOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final String text;
  final bool selected;
  final TextStyle mono;
  final ItouColors c;
  final VoidCallback onTap;

  const _VariantOption({
    required this.label,
    required this.icon,
    required this.text,
    required this.selected,
    required this.mono,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').where((l) => l.isNotEmpty).toList();
    final shown = lines.take(_kMaxDiffLines).toList();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: selected ? c.panelHover : Colors.transparent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.blue : Colors.transparent,
                  border: Border.all(
                    color: selected ? c.blue : c.border2,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: selected ? 1 : 0.55,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 13, color: c.dim),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final line in shown)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            line.isEmpty ? '（空行）' : line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono.copyWith(color: c.text),
                          ),
                        ),
                      if (lines.length > shown.length)
                        Text(
                          '… 還有 ${lines.length - shown.length} 行',
                          style: TextStyle(color: c.mute, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewToggle extends StatelessWidget {
  final bool expanded;
  final String text;
  final VoidCallback onTap;
  final ItouColors c;

  const _PreviewToggle({
    required this.expanded,
    required this.text,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFamily: 'monospace',
      fontSize: 11.5,
      height: 1.5,
    );
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  const Text(
                    '合併結果預覽',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.expand_more, size: 20, color: c.dim),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    width: double.infinity,
                    color: c.inset,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          text,
                          key: ValueKey(text),
                          style: mono.copyWith(color: c.text),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onOverwrite;
  final VoidCallback onMerge;
  final ItouColors c;

  const _BottomBar({
    required this.onCancel,
    required this.onOverwrite,
    required this.onMerge,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              TextButton(onPressed: onCancel, child: const Text('取消')),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onOverwrite,
                  child: const Text('直接用本地覆蓋'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: onMerge,
                  child: const Text('合併並同步'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
