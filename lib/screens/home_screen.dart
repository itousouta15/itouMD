import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/hackmd_account.dart';
import '../services/hackmd_api.dart';
import '../services/markdown_source.dart';
import '../services/recent_docs.dart';
import '../services/theme_prefs.dart';
import '../services/ui_prefs.dart';
import '../services/update_checker.dart';
import '../theme.dart';
import '../widgets/loader_ring.dart';
import '../widgets/update_dialog.dart';
import 'hackmd_account_screen.dart';
import 'hackmd_notes_screen.dart';
import 'settings_screen.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeCustomization customization;
  final ValueChanged<ThemeCustomization> onCustomizationChanged;
  final UiScale uiScale;
  final ValueChanged<UiScale> onUiScaleChanged;

  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.customization,
    required this.onCustomizationChanged,
    required this.uiScale,
    required this.onUiScaleChanged,
  });

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
        ),
      ),
    );
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
      _openViewer(file.name, text, source: RecentDocSource.file);
    } catch (_) {
      setState(() => _error = '選擇檔案時出了點問題 (´;ω;`)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openHackmdNotes() async {
    final token = await HackmdAccount.getToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('還沒連結 HackMD 帳號'),
          action: SnackBarAction(
            label: '設定',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HackmdAccountScreen()),
            ),
          ),
        ),
      );
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HackmdNotesScreen()));
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

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final isDark = widget.themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                c: c,
                isDark: isDark,
                onOpenSettings: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      themeMode: widget.themeMode,
                      onThemeModeChanged: widget.onThemeModeChanged,
                      customization: widget.customization,
                      onCustomizationChanged: widget.onCustomizationChanged,
                      uiScale: widget.uiScale,
                      onUiScaleChanged: widget.onUiScaleChanged,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_recents.isNotEmpty) ...[
                      Row(
                        children: [
                          const SectionLabel('最近開啟'),
                          const Spacer(),
                          GestureDetector(
                            onTap: _clearRecents,
                            child: Text(
                              '清除紀錄',
                              style: TextStyle(color: c.mute, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _RecentDocsPanel(
                        docs: _recents,
                        onOpen: (doc) => _openViewer(
                          doc.title,
                          doc.content,
                          source: doc.source,
                          sourceRef: doc.sourceRef,
                        ),
                        onRemove: _removeRecent,
                      ),
                      const SizedBox(height: 24),
                    ],

                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [LoaderRing()],
                        ),
                      ),

                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.panel,
                          border: Border.all(color: const Color(0xFFE0777A)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFE0777A),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFE0777A),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    _StepCard(
                      step: '01',
                      title: '貼上文字',
                      accent: c.blue,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _pasteController,
                            maxLines: 6,
                            minLines: 4,
                            style: TextStyle(color: c.text, fontSize: 13.5),
                            decoration: const InputDecoration(
                              hintText: '# 貼上你的 Markdown 原始碼...',
                              border: InputBorder.none,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _openViewer('貼上的內容', _pasteController.text),
                            icon: const Icon(
                              Icons.auto_stories_outlined,
                              size: 18,
                            ),
                            label: const Text('開始檢視'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _StepCard(
                      step: '02',
                      title: '選擇本機檔案',
                      accent: c.blue,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _pickFile,
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        label: const Text('選擇 .md 檔案'),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _StepCard(
                      step: '03',
                      title: '貼上網址',
                      accent: c.blue,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _urlController,
                            keyboardType: TextInputType.url,
                            style: TextStyle(color: c.text, fontSize: 13.5),
                            decoration: const InputDecoration(
                              hintText:
                                  'https://github.com/.../blob/main/README.md',
                              border: InputBorder.none,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _busy ? null : _fetchUrl,
                            icon: const Icon(
                              Icons.cloud_download_outlined,
                              size: 18,
                            ),
                            label: const Text('從網址抓取'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _StepCard(
                      step: '04',
                      title: '瀏覽我的 HackMD 筆記',
                      accent: c.blue,
                      child: ElevatedButton.icon(
                        onPressed: _openHackmdNotes,
                        icon: const Icon(Icons.cloud_queue_outlined, size: 18),
                        label: const Text('開啟筆記列表'),
                      ),
                    ),
                    const SizedBox(height: 36),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () =>
                                launchUrl(Uri.parse('https://itousouta.me')),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Made with ♥ by ',
                                    style: TextStyle(
                                      color: c.mute,
                                      fontSize: 14,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'itouSouta',
                                    style: TextStyle(
                                      color: c.blue,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => launchUrl(
                              Uri.parse('https://github.com/itousouta15/itouMD'),
                            ),
                            child: Text(
                              '如果喜歡的話歡迎到 GitHub 給個 star ♡',
                              style: TextStyle(color: c.mute, fontSize: 14),
                            ),
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
}

class _Header extends StatefulWidget {
  final ItouColors c;
  final bool isDark;
  final VoidCallback onOpenSettings;

  const _Header({
    required this.c,
    required this.isDark,
    required this.onOpenSettings,
  });

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
    final mono = Theme.of(context).textTheme.labelSmall!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
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
                height: 50,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'itouMD',
                    style: mono.copyWith(
                      color: c.text,
                      fontSize: 20,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '手機也能好好用 MD (｡•ᴗ•｡)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.dim, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '設定',
            icon: Icon(Icons.settings_outlined, color: c.dim),
            onPressed: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String step;
  final String title;
  final Color accent;
  final Widget child;

  const _StepCard({
    required this.step,
    required this.title,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final mono = Theme.of(context).textTheme.labelSmall!;
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: accent)),
                  child: Text(
                    step,
                    style: mono.copyWith(color: accent, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
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
                    GestureDetector(
                      onTap: () => onRemove(docs[i]),
                      child: Icon(Icons.close, size: 16, color: c.mute),
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
