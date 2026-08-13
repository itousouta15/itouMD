import 'package:flutter_test/flutter_test.dart';

import 'package:itou_md/services/github_api.dart';

void main() {
  group('GithubApi.parseUrl', () {
    test('parses a blob URL', () {
      final ref = GithubApi.parseUrl(
        'https://github.com/itousouta15/itouMD/blob/master/README.md',
      );
      expect(ref, isNotNull);
      expect(ref!.owner, 'itousouta15');
      expect(ref.repo, 'itouMD');
      expect(ref.branch, 'master');
      expect(ref.path, 'README.md');
    });

    test('parses a nested blob path', () {
      final ref = GithubApi.parseUrl(
        'https://github.com/owner/repo/blob/main/docs/guide/intro.md',
      );
      expect(ref, isNotNull);
      expect(ref!.branch, 'main');
      expect(ref.path, 'docs/guide/intro.md');
    });

    test('parses a bare repo URL as README.md on the default branch', () {
      final ref = GithubApi.parseUrl('https://github.com/itousouta15/itouMD');
      expect(ref, isNotNull);
      expect(ref!.owner, 'itousouta15');
      expect(ref.repo, 'itouMD');
      expect(ref.branch, isEmpty);
      expect(ref.path, 'README.md');
    });

    test('falls back to the repo README for non-blob URLs under it', () {
      // /tree, /issues, a trailing slash, etc. aren't a specific file link
      // — pasting "the repo" almost always means "open its README".
      for (final url in [
        'https://github.com/o/r/tree/main',
        'https://github.com/o/r/issues/1',
        'https://github.com/o/r/',
      ]) {
        final ref = GithubApi.parseUrl(url);
        expect(ref, isNotNull, reason: url);
        expect(ref!.owner, 'o', reason: url);
        expect(ref.repo, 'r', reason: url);
        expect(ref.branch, isEmpty, reason: url);
        expect(ref.path, 'README.md', reason: url);
      }
    });

    test('rejects non-github URLs and paths without a repo', () {
      expect(GithubApi.parseUrl('https://hackmd.io/abc'), isNull);
      expect(GithubApi.parseUrl('https://github.com/only-owner'), isNull);
    });
  });
}
