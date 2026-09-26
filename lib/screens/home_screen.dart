import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/github_link_rewriter.dart';
import '../services/hackmd_account.dart';
import '../services/hackmd_api.dart';
import '../services/local_file_saver.dart';
import '../services/markdown_source.dart';
import '../services/recent_docs.dart';
import '../services/update_checker.dart';
import '../theme.dart';
import '../widgets/loader_ring.dart';
import '../widgets/update_dialog.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  final int reloadRecentsToken;

  const HomeScreen({super.key, this.reloadRecentsToken = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pasteController = TextEditingController();
  final _urlController = TextEditingController();
  bool _busy = false;
  String? _error;
  List<RecentDoc> _recents = [];

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _checkUpdateSilently();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reloadRecentsToken != oldWidget.reloadRecentsToken) {
      _loadRecents();
    }
  }

  Future<void> _loadRecents() async {
    final docs = await RecentDocs.load();
    if (mounted) setState(() => _recents = docs);
  }

  /// Silent update check on launch: only shows anything when a newer
  /// version actually exists; failures and "already latest" do nothing.
  Future<void> _checkUpdateSilently() async {
    final info = await UpdateChecker.checkForUpdate();
    if (!mounted || info == null) return;
    String version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await showUpdateAvailableDialog(context, info, currentVersion: version);
  }

  @override
  void dispose() {
    _pasteController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _openViewer(
    String title,
    String content, {
    RecentDocSource source = RecentDocSource.paste,
    String? sourceRef,
    GithubLinkContext? githubLinkContext,
    String? localPath,
    String? localUri,
  }) async {
    if (content.trim().isEmpty) {
      setState(() => _error = '內容是空的喔 (´;ω;`)');
      return;
    }
    setState(() => _error = null);
    final docs = await RecentDocs.add(
      RecentDoc(
        title: title,
        content: content,
        source: source,
        sourceRef: sourceRef,
        localPath: localPath,
        localUri: localUri,
        openedAt: DateTime.now(),
      ),
    );
    if (mounted) setState(() => _recents = docs);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewerScreen(
          title: title,
          content: content,
          source: source,
          sourceRef: sourceRef,
          githubLinkContext: githubLinkContext,
          localPath: localPath,
          localUri: localUri,
        ),
      ),
    );
    // The viewer persists edits (and syncs) into the recent-docs store while
    // this screen is underneath; reload so the in-memory list doesn't stay
    // stale — otherwise tapping the same entry again re-opens the OLD
    // content and overwrites the edited copy.
    if (mounted) await _loadRecents();
  }

  Future<void> _removeRecent(RecentDoc doc) async {
    final docs = await RecentDocs.remove(doc);
    if (mounted) setState(() => _recents = docs);
  }

  Future<void> _clearRecents() async {
    await RecentDocs.clear();
    if (mounted) setState(() => _recents = []);
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'mdx', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _error = '讀不到這個檔案 (´;ω;`)');
        return;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) return;
      // Keep the picked file's write grant alive across restarts so the
      // identifier stored in recent docs stays usable for 存回原檔 later.
      await LocalFileSaver.persistPermission(file.identifier);
      if (!mounted) return;
      _openViewer(
        file.name,
        text,
        source: RecentDocSource.file,
        localPath: file.path,
        localUri: file.identifier,
      );
    } catch (_) {
      setState(() => _error = '選擇檔案時出了點問題 (´;ω;`)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetchUrl() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await fetchMarkdownFromUrl(input);
      if (!mounted) return;
      final segments = Uri.tryParse(input)?.pathSegments ?? const <String>[];
      final niceTitle =
          extractDocTitle(text) ??
          (segments.isNotEmpty ? segments.last : input);
      _openViewer(
        niceTitle,
        text,
        source: RecentDocSource.url,
        sourceRef: input,
      );
    } on MarkdownFetchException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = '抓取失敗，再試一次看看 (´;ω;`)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for a title, then starts a fresh document. When a HackMD account
  /// is linked, tries to create the note on the cloud first (the official
  /// API may reject some tokens; any failure falls back to a local draft).
  Future<void> _createNewDoc() async {
    final titleController = TextEditingController(text: '未命名');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = ItouColorsExt.of(ctx);
        return AlertDialog(
          title: const Text('新建文件'),
          content: TextField(
            controller: titleController,
            autofocus: true,
            maxLength: 40,
            style: TextStyle(color: c.text, fontSize: 14),
            decoration: const InputDecoration(
              hintText: '輸入標題...',
              border: InputBorder.none,
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(titleController.text),
              child: const Text('建立'),
            ),
          ],
        );
      },
    );
    if (!mounted || title == null) return;
    final safeTitle = title.trim();
    if (safeTitle.isEmpty) return;
    final name = safeTitle.length > 40 ? safeTitle.substring(0, 40) : safeTitle;

    var content = '# $name\n';
    var source = RecentDocSource.paste;
    String? sourceRef;

    final token = await HackmdAccount.getToken();
    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      try {
        final note = await HackmdApi.createNote(token, content);
        content = note.content;
        source = RecentDocSource.url;
        sourceRef = 'https://hackmd.io/${note.permalink ?? note.id}';
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已在 HackMD 建立筆記 (｡•ᴗ•｡)')));
      } on HackmdApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${e.message} 改為建立本地草稿')));
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法連到 HackMD，改為建立本地草稿 (´;ω;`)')),
        );
      }
    }
    if (!mounted) return;
    await _openViewer(name, content, source: source, sourceRef: sourceRef);
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(c: c, isDark: isDark),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: c.panel,
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '隨時隨地編輯.md',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '開啟 Markdown、整理想法，或接著編輯上次的內容。',
                            style: TextStyle(color: c.dim, height: 1.6),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _busy ? null : _createNewDoc,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('建立新文件'),
                          ),
                        ],
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 16),
                      const Center(child: LoaderRing()),
                    ],
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.panel,
                          border: Border.all(color: ItouColors.danger),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: ItouColors.danger),
                        ),
                      ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text(
                          '最近開啟',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        if (_recents.isNotEmpty)
                          TextButton(
                            onPressed: _clearRecents,
                            child: const Text('清除紀錄'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_recents.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: c.panel,
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.history_rounded, color: c.dim),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '開啟過的文件會出現在這裡',
                                style: TextStyle(color: c.dim, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      _RecentDocsPanel(
                        docs: _recents,
                        onOpen: (doc) => _openViewer(
                          doc.title,
                          doc.content,
                          source: doc.source,
                          sourceRef: doc.sourceRef,
                          localPath: doc.localPath,
                          localUri: doc.localUri,
                        ),
                        onRemove: _removeRecent,
                      ),
                    const SizedBox(height: 28),
                    Text(
                      '開啟文件',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: c.panel,
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Column(
                        children: [
                          _OpenAction(
                            icon: Icons.content_paste_outlined,
                            title: '貼上文字',
                            subtitle: '從剪貼簿貼上 Markdown',
                            onTap: () => _showInputSheet(isUrl: false),
                          ),
                          Divider(height: 1, indent: 56, color: c.border),
                          _OpenAction(
                            icon: Icons.folder_open_outlined,
                            title: '選擇本機檔案',
                            subtitle: '開啟 .md、.mdx 或 .txt',
                            onTap: _busy ? null : _pickFile,
                          ),
                          Divider(height: 1, indent: 56, color: c.border),
                          _OpenAction(
                            icon: Icons.link_rounded,
                            title: '貼上網址',
                            subtitle: '從 GitHub、Gist 或 HackMD 抓取',
                            onTap: () => _showInputSheet(isUrl: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showInputSheet({required bool isUrl}) async {
    final controller = isUrl ? _urlController : _pasteController;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isUrl ? '從網址開啟' : '貼上 Markdown',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: isUrl
                      ? TextInputType.url
                      : TextInputType.multiline,
                  minLines: isUrl ? 1 : 5,
                  maxLines: isUrl ? 2 : 8,
                  decoration: InputDecoration(
                    hintText: isUrl
                        ? '貼上 GitHub、Gist 或 HackMD 網址'
                        : '# 貼上你的 Markdown 原始碼…',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    if (isUrl) {
                      _fetchUrl();
                    } else {
                      _openViewer('貼上的內容', controller.text);
                    }
                  },
                  child: Text(isUrl ? '從網址抓取' : '開始檢視'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatefulWidget {
  final ItouColors c;
  final bool isDark;

  const _Header({required this.c, required this.isDark});

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  // The theme's own colours crossfade instantly via AnimatedTheme; the logo
  // swap is held back a beat so it reads as following that transition
  // rather than leading it, then fades between the two artworks itself.
  late bool _logoIsDark = widget.isDark;

  @override
  void didUpdateWidget(covariant _Header oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _logoIsDark = widget.isDark);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Image.asset(
                _logoIsDark
                    ? 'assets/logo/logo_nbg.webp'
                    : 'assets/logo/logo_wtnbg.webp',
                key: ValueKey(_logoIsDark),
                height: 42,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'itouMD',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: c.text),
                ),
                Text(
                  '手機也能好好用 MD',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.dim, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _OpenAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: c.blue, size: 22),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.mute, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentDocsPanel extends StatelessWidget {
  final List<RecentDoc> docs;
  final ValueChanged<RecentDoc> onOpen;
  final ValueChanged<RecentDoc> onRemove;

  const _RecentDocsPanel({
    required this.docs,
    required this.onOpen,
    required this.onRemove,
  });

  IconData _iconFor(RecentDocSource source) => switch (source) {
    RecentDocSource.paste => Icons.content_paste_outlined,
    RecentDocSource.file => Icons.description_outlined,
    RecentDocSource.url => Icons.link_outlined,
  };

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
    if (diff.inHours < 24) return '${diff.inHours} 小時前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.year}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < docs.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.border),
            InkWell(
              onTap: () => onOpen(docs[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(_iconFor(docs[i].source), size: 18, color: c.dim),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            docs[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _relativeTime(docs[i].openedAt),
                            style: TextStyle(color: c.mute, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '移除 ${docs[i].title}',
                      onPressed: () => onRemove(docs[i]),
                      icon: Icon(Icons.close_rounded, size: 18, color: c.mute),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
