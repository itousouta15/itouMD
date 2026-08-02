import 'package:flutter/material.dart';

import '../services/hackmd_account.dart';
import '../services/hackmd_api.dart';
import '../services/markdown_source.dart';
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
    } on HackmdApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '讀取筆記失敗，再試一次看看 (´;ω;`)';
      });
    }
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
          children: _personal
              .map((n) => _NoteTile(
                note: n,
                subtitle: n.permalink ?? n.id,
                busy: _openingNoteId == n.id,
                onTap: () => _openNote(n, null),
                c: c,
              ))
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
          children: notes
              .map((n) => _NoteTile(
                note: n,
                subtitle: n.permalink ?? n.id,
                busy: _openingNoteId == n.id,
                onTap: () => _openNote(n, team),
                c: c,
              ))
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
          for (final section in sections) ...[
            section,
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.panel,
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: c.border),
                children[i],
              ],
            ],
          ),
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
            Icon(Icons.description_outlined, size: 18, color: c.dim),
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
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.mute, fontSize: 11),
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
