import 'github_account.dart';
import 'github_api.dart';
import 'github_link_rewriter.dart';
import 'markdown_source.dart';

class OpenedGithubDocument {
  final String title;
  final String content;
  final String sourceRef;
  final GithubLinkContext? linkContext;

  const OpenedGithubDocument({
    required this.title,
    required this.content,
    required this.sourceRef,
    this.linkContext,
  });
}

/// Shared by the home input and the cloud tab so both entry points resolve
/// public and private repo READMEs in exactly the same way.
Future<OpenedGithubDocument> openGithubDocument(String input) async {
  final hasScheme = Uri.tryParse(input)?.hasScheme ?? false;
  final url = hasScheme ? input : 'https://github.com/$input';
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != 'github.com') {
    throw MarkdownFetchException('請輸入 owner/repo 或 github.com 網址 (´;ω;`)');
  }
  final ref = GithubApi.parseUrl(url);
  if (ref == null) {
    throw MarkdownFetchException('這個 GitHub 網址格式不支援 (´;ω;`)');
  }

  final token = await GithubAccount.getToken();
  if (ref.branch.isEmpty && ref.path == 'README.md') {
    final file = await GithubApi.getReadme(ref, token: token);
    return OpenedGithubDocument(
      title: ref.displayName,
      content: file.content,
      sourceRef: url,
      linkContext: GithubLinkContext.fromFile(ref.owner, ref.repo, file),
    );
  }
  if (token != null && token.isNotEmpty) {
    final file = await GithubApi.getFile(token, ref);
    return OpenedGithubDocument(
      title: ref.displayName,
      content: file.content,
      sourceRef: url,
      linkContext: GithubLinkContext.fromFile(ref.owner, ref.repo, file),
    );
  }
  final content = await fetchMarkdownFromUrl(url);
  return OpenedGithubDocument(
    title: extractDocTitle(content) ?? ref.displayName,
    content: content,
    sourceRef: url,
  );
}
