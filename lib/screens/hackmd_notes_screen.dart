import 'package:flutter/material.dart';

import '../services/hackmd_account.dart';
import '../services/hackmd_api.dart';
import '../services/markdown_source.dart';
import '../services/note_cache.dart';
import '../services/recent_docs.dart';
import '../theme.dart';
import '../widgets/loader_ring.dart';
import 'hackmd_account_screen.dart';
import 'viewer_screen.dart';

/// A browsable list of the linked account's HackMD notes — personal workspace
/// first, then each team the account belongs to. Tapping a note opens it in
/// the viewer with its canonical `hackmd.io` URL as the source ref, so the
/// "sync back to the cloud" action keeps working without pasting a URL.
class HackmdNotesScreen extends StatefulWidget {
  const HackmdNotesScreen({super.key});

  @override
  State<HackmdNotesScreen> createState() => _HackmdNotesScreenState();
}

class _HackmdNotesScreenState extends State<HackmdNotesScreen> {
  List<HackmdNote> _personal = [];
  final List<HackmdTeam> _teams = [];
  final Map<String, List<HackmdNote>> _teamNotes = {};
  bool _loading = true;
  bool _offline = false;
  String? _error;
  String? _openingNoteId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    final token = await HackmdAccount.getToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = '還沒連結 HackMD 帳號';
      });
      return;
    }
    try {
      final results = await Future.wait<Object>([
        HackmdApi.listNotes(token),
        HackmdApi.listTeams(token),
      ]);
      if (!mounted) return;
      final personal = results[0] as List<HackmdNote>;
      final teams = results[1] as List<HackmdTeam>;
      final teamNotes = <String, List<HackmdNote>>{};
      for (final team in teams) {
        if (team.path.isEmpty) continue;
        teamNotes[team.path] = await HackmdApi.listTeamNotes(token, team.path);
      }
      if (!mounted) return;
      setState(() {
        _personal = personal;
        _teams
          ..clear()
          ..addAll(teams);
        _teamNotes
          ..clear()
          ..addAll(teamNotes);
        _loading = false;
      });
      // Keep a snapshot so the list stays usable offline.
      NoteCache.saveList(
        NoteListSnapshot(
          personal: personal,
          teams: teams,
          teamNotes: teamNotes,
          savedAt: DateTime.now(),
        ),
      );
    } on HackmdApiException catch (e) {
      if (!mounted) return;
      final loadedOffline = await _tryOfflineList();
      if (!mounted) return;
      if (!loadedOffline) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      final loadedOffline = await _tryOfflineList();
      if (!mounted) return;
      if (!loadedOffline) {
        setState(() {
          _loading = false;
          _error = '讀取筆記失敗，再試一次看看 (´;ω;`)';
        });
      }
    }
  }

  /// Falls back to the cached list snapshot when the fetch fails. Returns
  /// `true` when the cached data was loaded (and `false` when there is
  /// nothing cached, leaving the caller to surface the error).
  Future<bool> _tryOfflineList() async {
    final snapshot = await NoteCache.loadList();
    if (!mounted) return true;
    if (snapshot == null) return false;
    setState(() {
      _personal = snapshot.personal;
      _teams
        ..clear()
        ..addAll(snapshot.teams);
      _teamNotes
        ..clear()
        ..addAll(snapshot.teamNotes);
      _loading = false;
      _offline = true;
    });
    return true;
  }

  String _noteTitle(HackmdNote note, String content) {
    return note.title ??
        extractDocTitle(content) ??
        (note.permalink != null ? note.permalink! : note.id);
  }

  String _noteUrl(HackmdNote note, HackmdTeam? team) {
    if (team != null) {
      final slug = note.teamPath?.replaceFirst('@', '') ?? team.urlSlug;
      return 'https://hackmd.io/@$slug/${note.permalink ?? note.id}';
    }
    return 'https://hackmd.io/${note.id}';
  }

  Future<void> _openNote(HackmdNote note, HackmdTeam? team) async {
    final token = await HackmdAccount.getToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) return;
    setState(() => _openingNoteId = note.id);
    try {
      final full = team != null
          ? await HackmdApi.getTeamNote(token, team.path, note.id)
          : await HackmdApi.getNote(token, note.id);
      if (!mounted) return;
      final url = _noteUrl(note, team);
      final title = _noteTitle(full, full.content);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ViewerScreen(
            title: title,
            content: full.content,
            source: RecentDocSource.url,
            sourceRef: url,
          ),
        ),
      );
    } on HackmdApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('開啟失敗，再試一次看看 (´;ω;`)')));
    } finally {
      if (mounted) setState(() => _openingNoteId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('我的 HackMD 筆記')),
      body: _buildBody(c),
    );
  }

  Widget _buildBody(ItouColors c) {
    if (_loading) {
      return const Center(child: LoaderRing());
    }
    if (_error != null) {
      return _ErrorPanel(error: _error!, onRetry: _load, c: c);
    }
    final hasPersonal = _personal.isNotEmpty;
    final teamSectionTitles = _teams.where((t) => t.path.isNotEmpty);
    final hasTeams = teamSectionTitles.isNotEmpty;
    if (!hasPersonal && !hasTeams) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '你的帳號底下還沒有筆記 (´;ω;`)',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.dim, fontSize: 13),
          ),
        ),
      );
    }

    final sections = <Widget>[];
    if (hasPersonal) {
      sections.add(
        _Section(
          title: '個人筆記',
          icon: Icons.person_outline,
          children: _personal
              .map(
                (n) => _NoteTile(
                  note: n,
                  subtitle: n.permalink ?? n.id,
                  busy: _openingNoteId == n.id,
                  onTap: () => _openNote(n, null),
                  c: c,
                ),
              )
              .toList(),
        ),
      );
    }
    for (final team in teamSectionTitles) {
      final notes = _teamNotes[team.path] ?? const <HackmdNote>[];
      if (notes.isEmpty) continue;
      sections.add(
        _Section(
          title: '@${team.urlSlug}',
          icon: Icons.groups_outlined,
          children: notes
              .map(
                (n) => _NoteTile(
                  note: n,
                  subtitle: n.permalink ?? n.id,
                  busy: _openingNoteId == n.id,
                  onTap: () => _openNote(n, team),
                  c: c,
                ),
              )
              .toList(),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: c.blue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_offline)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.panel,
                border: Border.all(color: const Color(0xFFAD8B5C)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 16,
                    color: Color(0xFFAD8B5C),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '離線資料（上次成功更新的內容）',
                      style: TextStyle(color: Color(0xFFAD8B5C), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          for (final section in sections) ...[
            section,
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  // Collapsed by default — long lists stay compact; tap a section header to
  // expand just the one you need.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.panel,
                border: Border.all(
                  color: _expanded ? c.blue.withValues(alpha: 0.45) : c.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 17, color: c.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.inset,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${widget.children.length}',
                      style: TextStyle(color: c.dim, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, size: 22, color: c.dim),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: c.panel,
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.children.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, thickness: 1, color: c.border),
                        widget.children[i],
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  final HackmdNote note;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;
  final ItouColors c;

  const _NoteTile({
    required this.note,
    required this.subtitle,
    required this.busy,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final title = note.title ?? subtitle;
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.inset,
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.description_outlined, size: 16, color: c.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.dim, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.chevron_right, size: 18, color: c.mute),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final ItouColors c;

  const _ErrorPanel({
    required this.error,
    required this.onRetry,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    if (error == '還沒連結 HackMD 帳號') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFE0777A), fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HackmdAccountScreen(),
                  ),
                ),
                child: const Text('設定 HackMD 帳號'),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE0777A), fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重試')),
          ],
        ),
      ),
    );
  }
}
