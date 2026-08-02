import 'package:flutter_test/flutter_test.dart';

import 'package:itou_md/services/markdown_diff.dart';

void main() {
  group('mergeLines', () {
    test('完全沒有變更', () {
      final result = mergeLines('A\nB\nC\n', 'A\nB\nC\n', 'A\nB\nC\n');
      expect(result.segments.whereType<ConflictSegment>(), isEmpty);
      expect(result.autoApplied, isEmpty);
      expect(result.resolve(useLocal: true), 'A\nB\nC\n');
      expect(result.remoteAddedLines, 0);
      expect(result.remoteRemovedLines, 0);
    });

    test('遠端單邊新增 → 自動合併', () {
      final result = mergeLines('A\nB\nC\n', 'A\nB\nC\n', 'A\nB\nC\nD\n');
      expect(result.segments.whereType<ConflictSegment>(), isEmpty);
      expect(result.autoApplied, hasLength(1));
      expect(result.remoteAddedLines, 1);
      expect(result.resolve(useLocal: true), 'A\nB\nC\nD\n');
    });

    test('本地單邊修改 → 保留，無衝突', () {
      final result = mergeLines('A\nB\nC\n', 'A\nX\nC\n', 'A\nB\nC\n');
      expect(result.segments.whereType<ConflictSegment>(), isEmpty);
      expect(result.autoApplied, isEmpty);
      expect(result.resolve(useLocal: true), 'A\nX\nC\n');
    });

    test('遠端單邊刪除 → 自動合併', () {
      final result = mergeLines('A\nB\nC\n', 'A\nB\nC\n', 'A\nC\n');
      expect(result.segments.whereType<ConflictSegment>(), isEmpty);
      expect(result.autoApplied, hasLength(1));
      expect(result.remoteRemovedLines, 1);
      expect(result.resolve(useLocal: true), 'A\nC\n');
    });

    test('兩邊改同一行 → 衝突', () {
      final result = mergeLines('A\nB\nC\n', 'A\nL\nC\n', 'A\nR\nC\n');
      final conflicts = result.segments.whereType<ConflictSegment>().toList();
      expect(conflicts, hasLength(1));
      expect(conflicts.single.local, 'L\n');
      expect(conflicts.single.remote, 'R\n');
      expect(result.resolve(useLocal: true), 'A\nL\nC\n');
      expect(result.resolve(useLocal: false), 'A\nR\nC\n');
    });

    test('兩邊改不同行 → 無衝突，兩邊都保留', () {
      final result = mergeLines('A\nB\nC\n', 'A\nL\nC\n', 'A\nB\nR\n');
      expect(result.segments.whereType<ConflictSegment>(), isEmpty);
      expect(result.resolve(useLocal: true), 'A\nL\nR\n');
    });

    test('兩邊加同一行 → 視為相同，不衝突', () {
      final result = mergeLines('A\nB\nC\n', 'A\nB\nC\nD\n', 'A\nB\nC\nD\n');
      expect(result.segments.whereType<ConflictSegment>(), isEmpty);
      expect(result.resolve(useLocal: true), 'A\nB\nC\nD\n');
    });

    test('部分重疊的 hunk → 衝突且不遺失', () {
      // 本地把第 1-2 行換成 X；遠端把第 2 行換成 Y（第 2 行雙方都改）。
      final result = mergeLines('a\nb\nc\nd\n', 'a\nX\nd\n', 'a\nb\nY\nd\n');
      final conflicts = result.segments.whereType<ConflictSegment>().toList();
      expect(conflicts, isNotEmpty);
      final local = result.resolve(useLocal: true);
      final remote = result.resolve(useLocal: false);
      expect(local, contains('X'));
      expect(remote, contains('Y'));
    });

    test('CRLF 與 LF 混用 → 不正規化時不當衝突', () {
      final result = mergeLines('A\r\nB\r\nC\r\n', 'A\nB\nC\n', 'A\nB\nC\n');
      expect(result.segments.whereType<ConflictSegment>(), isEmpty);
      expect(result.resolve(useLocal: true), 'A\nB\nC\n');
    });

    test('空 base 的純新增', () {
      final result = mergeLines('', 'a\nb\n', 'a\nb\n');
      expect(result.segments.whereType<ConflictSegment>(), isEmpty);
      expect(result.resolve(useLocal: true), 'a\nb\n');
    });

    test('遠端新增行數統計', () {
      final result = mergeLines('A\nB\nC\n', 'A\nB\nC\n', 'A\nB\nC\nD\nE\n');
      expect(result.remoteAddedLines, 2);
      expect(result.remoteRemovedLines, 0);
    });
  });
}
