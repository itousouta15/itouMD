import 'package:html/parser.dart' as html_parser;

import 'github_api.dart';

/// Where a fetched GitHub file lives — the viewer otherwise has no notion
/// of "current directory", so a README's relative links/images
/// (`docs/guide.md`, `./LICENSE`, `assets/logo.png`) have nothing to
/// resolve against and are just dead text when tapped.
class GithubLinkContext {
  final String owner;
  final String repo;

  /// Branch name or commit SHA — whichever [GithubFile.downloadUrl]
  /// actually resolved to, so this is correct even when the caller only
  /// asked for "the default branch" without knowing its name.
  final String ref;

  /// Directory the fetched file lives in, no leading/trailing slash
  /// (`''` for the repo root).
  final String dirPath;

  const GithubLinkContext({
    required this.owner,
    required this.repo,
    required this.ref,
    required this.dirPath,
  });

  /// Builds the context for a file fetched via [GithubApi.getFile] or
  /// [GithubApi.getReadme] — `null` if the response didn't carry a
  /// `download_url` to recover the resolved ref from.
  static GithubLinkContext? fromFile(
    String owner,
    String repo,
    GithubFile file,
  ) {
    final downloadUrl = file.downloadUrl;
    if (downloadUrl == null) return null;
    final uri = Uri.tryParse(downloadUrl);
    // raw.githubusercontent.com/{owner}/{repo}/{ref}/{...path}
    if (uri == null || uri.pathSegments.length < 3) return null;
    final ref = uri.pathSegments[2];
    final path = file.path;
    final slash = path.lastIndexOf('/');
    return GithubLinkContext(
      owner: owner,
      repo: repo,
      ref: ref,
      dirPath: slash < 0 ? '' : path.substring(0, slash),
    );
  }

  /// Applies `.`/`..` segments from [relative] onto [dirPath].
  List<String> _resolveSegments(String relative) {
    final segments = dirPath.isEmpty
        ? <String>[]
        : dirPath.split('/').where((s) => s.isNotEmpty).toList();
    for (final part in relative.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(part);
      }
    }
    return segments;
  }

  /// Resolves a link `href` — an absolute URL or a pure `#anchor` passes
  /// through unchanged; a repo-relative path becomes a `github.com` blob
  /// URL (GitHub's own routing redirects that to the tree view if the
  /// target turns out to be a directory, so this doesn't need to know
  /// which).
  String resolveLink(String href) {
    if (href.isEmpty || href.startsWith('#')) return href;
    final uri = Uri.tryParse(href);
    if (uri == null || uri.hasScheme || uri.host.isNotEmpty) return href;
    final path = _resolveSegments(uri.path).join('/');
    final fragment = uri.fragment.isEmpty ? '' : '#${uri.fragment}';
    return 'https://github.com/$owner/$repo/blob/$ref/$path$fragment';
  }

  /// Resolves an image `src` — needs actual bytes to render, so a
  /// relative path becomes a `raw.githubusercontent.com` URL instead of
  /// the (HTML) blob viewer page [resolveLink] targets.
  String resolveImage(String src) {
    final uri = Uri.tryParse(src);
    if (uri == null || uri.hasScheme || uri.host.isNotEmpty) return src;
    final path = _resolveSegments(uri.path).join('/');
    return 'https://raw.githubusercontent.com/$owner/$repo/$ref/$path';
  }
}

/// Rewrites relative `<a href>`/`<img src>` in [html] (as produced by
/// `convertMarkdownToHtml`) into absolute GitHub URLs per [context], so a
/// README's links to its own repo's files/images actually resolve instead
/// of being relative paths with no base.
String rewriteGithubRelativeLinks(String html, GithubLinkContext context) {
  final fragment = html_parser.parseFragment(html);
  for (final a in fragment.querySelectorAll('a[href]')) {
    final href = a.attributes['href'];
    if (href != null) a.attributes['href'] = context.resolveLink(href);
  }
  for (final img in fragment.querySelectorAll('img[src]')) {
    final src = img.attributes['src'];
    if (src != null) img.attributes['src'] = context.resolveImage(src);
  }
  return fragment.outerHtml;
}
