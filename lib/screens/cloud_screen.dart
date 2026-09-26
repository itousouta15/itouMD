import 'package:flutter/material.dart';

import '../services/github_account.dart';
import '../services/github_api.dart';
import '../services/github_document_opener.dart';
import '../services/markdown_source.dart';
import '../services/recent_docs.dart';
import '../theme.dart';
import 'github_account_screen.dart';
import 'github_repo_picker_screen.dart';
import 'hackmd_notes_screen.dart';
import 'viewer_screen.dart';

class CloudScreen extends StatelessWidget {
  final VoidCallback? onRecentsChanged;
  final int refreshToken;

  const CloudScreen({super.key, this.onRecentsChanged, this.refreshToken = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('雲端'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'HackMD'),
              Tab(text: 'GitHub'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            HackmdNotesScreen(
              embedded: true,
              onRecentsChanged: onRecentsChanged,
              refreshToken: refreshToken,
            ),
            _GithubCloudTab(
              onRecentsChanged: onRecentsChanged,
              refreshToken: refreshToken,
            ),
          ],
        ),
      ),
    );
  }
}

class _GithubCloudTab extends StatefulWidget {
  final VoidCallback? onRecentsChanged;
  final int refreshToken;

  const _GithubCloudTab({this.onRecentsChanged, required this.refreshToken});

  @override
  State<_GithubCloudTab> createState() => _GithubCloudTabState();
}

class _GithubCloudTabState extends State<_GithubCloudTab> {
  final _repoController = TextEditingController();
  bool _busy = false;
  bool _connected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshAccount();
  }

  @override
  void didUpdateWidget(covariant _GithubCloudTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) _refreshAccount();
  }

  Future<void> _refreshAccount() async {
    String? token;
    try {
      token = await GithubAccount.getToken();
    } catch (_) {
      token = null;
    }
    if (mounted) setState(() => _connected = token != null && token.isNotEmpty);
  }

  @override
  void dispose() {
    _repoController.dispose();
    super.dispose();
  }

  Future<void> _openRepo([String? selected]) async {
    final input = (selected ?? _repoController.text).trim();
    if (input.isEmpty) {
      setState(() => _error = '請輸入 owner/repo 或 GitHub 網址');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final doc = await openGithubDocument(input);
      if (!mounted) return;
      await RecentDocs.add(
        RecentDoc(
          title: doc.title,
          content: doc.content,
          source: RecentDocSource.url,
          sourceRef: doc.sourceRef,
          openedAt: DateTime.now(),
        ),
      );
      widget.onRecentsChanged?.call();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ViewerScreen(
            title: doc.title,
            content: doc.content,
            source: RecentDocSource.url,
            sourceRef: doc.sourceRef,
            githubLinkContext: doc.linkContext,
          ),
        ),
      );
      widget.onRecentsChanged?.call();
    } on MarkdownFetchException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on GithubApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '開啟失敗，再試一次看看');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _browseRepos() async {
    var token = await GithubAccount.getToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GithubAccountScreen()),
      );
      if (!mounted) return;
      await _refreshAccount();
      token = await GithubAccount.getToken();
      if (!mounted || token == null || token.isEmpty) return;
    }
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => GithubRepoPickerScreen(token: token!)),
    );
    if (picked == null || !mounted) return;
    _repoController.text = picked;
    await _openRepo(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
      children: [
        Text('開啟 GitHub 文件', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          '輸入 Repo 或文件網址，即可閱讀 README 和 Markdown。',
          style: TextStyle(color: c.dim, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _repoController,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _busy ? null : _openRepo(),
          decoration: const InputDecoration(
            hintText: 'owner/repo 或 GitHub 網址',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: ItouColors.danger)),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _openRepo,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_stories_outlined),
            label: const Text('開啟文件'),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('我的 Repo', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  _connected
                      ? '從你的 Repo 清單選擇，包含私人專案。'
                      : '連結 GitHub 後可瀏覽你的 Repo 與私人專案。',
                  style: TextStyle(color: c.dim, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _browseRepos,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(_connected ? '瀏覽 Repo' : '連結 GitHub 帳號'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
