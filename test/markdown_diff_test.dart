import 'package:flutter_test/flutter_test.dart';

import 'package:itou_md/services/markdown_diff.dart';

void main() {
  group('mergeLines', () {
    test('an insertion after an earlier replacement is not dropped', () {
      final result = mergeLines('a\nb\nc\n', 'A\nb\nc\nL\n', 'a\nB\nc\n');
      expect(result.conflictCount, 0);
      expect(result.resolve(useLocal: true), 'A\nB\nc\nL\n');
    });

    test(
      'overlapping replacement choices retain the whole affected region',
      () {
        final result = mergeLines('a\nb\nc\nd\n', 'a\nX\nd\n', 'a\nb\nY\nd\n');
        expect(result.resolve(useLocal: true), 'a\nX\nd\n');
        expect(result.resolve(useLocal: false), 'a\nb\nY\nd\n');
      },
    );

    test('empty text and missing final newline round-trip exactly', () {
      expect(mergeLines('one', 'oneX', 'one').resolve(useLocal: true), 'oneX');
      expect(mergeLines('', '', '').resolve(useLocal: true), '');
      expect(mergeLines('', 'new', '').resolve(useLocal: true), 'new');
    });

    test('removing the final newline conflicts with an appended line', () {
      for (final (base, local, remote) in [
        ('a\n', 'a', 'a\nb\n'),
        ('a\nb\n', 'a', 'a\nb\nc'),
      ]) {
        final result = mergeLines(base, local, remote);
        expect(result.conflictCount, 1);
        expect(result.resolve(useLocal: true), local);
        expect(result.resolve(useLocal: false), remote);
      }
    });

    test('connected overlaps preserve all edits and interior insertions', () {
      const base = 'a\nb\nc\nd\ne\nf\n';
      const local = 'a\nL1\nc\nL2\nf\n';
      const remote = 'a\nb\nR\ne\nf\n';
      final result = mergeLines(base, local, remote);
      expect(result.conflictCount, 1);
      expect(result.resolve(useLocal: true), local);
      expect(result.resolve(useLocal: false), remote);

      final insertion = mergeLines('a\nb\nc\n', 'a\nX\n', 'a\nb\nI\nc\n');
      expect(insertion.conflictCount, 1);
      expect(insertion.resolve(useLocal: true), 'a\nX\n');
      expect(insertion.resolve(useLocal: false), 'a\nb\nI\nc\n');
    });

    test('small-document merges are symmetric and never concatenate lines', () {
      const documents = [
        '', '\n', 'a', 'a\n', 'b', 'b\n', '\n\n',
        'a\na', 'a\nb', 'a\nb\n', 'b\na\n', 'a\n\n',
      ];
      for (final base in documents) {
        for (final local in documents) {
          final unchanged = mergeLines(base, local, base);
          expect(unchanged.conflictCount, 0);
          expect(unchanged.resolve(useLocal: false), local);
          final identical = mergeLines(base, local, local);
          expect(identical.conflictCount, 0);
          expect(identical.resolve(useLocal: true), local);
          for (final remote in documents) {
            final result = mergeLines(base, local, remote);
            final reversed = mergeLines(base, remote, local);
            expect(result.conflictCount, reversed.conflictCount);
            for (final useLocal in [true, false]) {
              final text = result.resolve(useLocal: useLocal);
              expect(text, reversed.resolve(useLocal: !useLocal));
              expect(
                text.split('\n').every((line) => ['', 'a', 'b'].contains(line)),
                isTrue,
                reason: 'base=$base local=$local remote=$remote result=$text',
              );
            }
          }
        }
      }
    });

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

  group('diffTexts', () {
    test('無變更', () {
      final hunks = diffTexts('A\nB\nC\n', 'A\nB\nC\n');
      expect(hunks, isEmpty);
      expect(diffStats(hunks), (0, 0));
    });

    test('純新增', () {
      final hunks = diffTexts('A\nB\n', 'A\nB\nC\nD\n');
      expect(hunks, hasLength(1));
      expect(hunks.single.removed, isEmpty);
      expect(hunks.single.added, ['C', 'D']);
      expect(diffStats(hunks), (2, 0));
    });

    test('純刪除', () {
      final hunks = diffTexts('A\nB\nC\n', 'A\nC\n');
      expect(hunks, hasLength(1));
      expect(hunks.single.removed, ['B']);
      expect(hunks.single.added, isEmpty);
      expect(diffStats(hunks), (0, 1));
    });

    test('修改', () {
      final hunks = diffTexts('A\nB\nC\n', 'A\nX\nC\n');
      expect(hunks, hasLength(1));
      expect(hunks.single.removed, ['B']);
      expect(hunks.single.added, ['X']);
      expect(diffStats(hunks), (1, 1));
    });

    test('CRLF 正規化', () {
      final hunks = diffTexts('A\r\nB\r\n', 'A\nB\n');
      expect(hunks, isEmpty);
    });
  });
}
