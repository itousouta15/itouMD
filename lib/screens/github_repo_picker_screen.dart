import 'package:flutter/material.dart';

import '../services/github_api.dart';
import '../theme.dart';
import '../widgets/loader_ring.dart';

/// Browses the linked GitHub account's repos (most recently updated first)
/// so opening one doesn't require typing `owner/repo` by hand. Tapping a
/// row pops the picker with that repo's `owner/repo` string.
class GithubRepoPickerScreen extends StatefulWidget {
  final String token;

  const GithubRepoPickerScreen({super.key, required this.token});

  @override
  State<GithubRepoPickerScreen> createState() => _GithubRepoPickerScreenState();
}

class _GithubRepoPickerScreenState extends State<GithubRepoPickerScreen> {
  List<GithubRepoSummary> _repos = [];
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repos = await GithubApi.listRepos(widget.token);
      if (!mounted) return;
      setState(() {
        _repos = repos;
        _loading = false;
      });
    } on GithubApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '讀不到 repo 清單，再試一次看看 (´;ω;`)';
        _loading = false;
      });
    }
  }

  List<GithubRepoSummary> get _filtered {
    if (_query.isEmpty) return _repos;
    return _repos
        .where(
          (r) =>
              r.fullName.toLowerCase().contains(_query) ||
              (r.description?.toLowerCase().contains(_query) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('選擇 GitHub Repo')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: c.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜尋 repo…',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: c.inset,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: c.border),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(c)),
        ],
      ),
    );
  }

  Widget _buildBody(ItouColors c) {
    if (_loading) {
      return const Center(child: LoaderRing());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ItouColors.danger, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('重試')),
            ],
          ),
        ),
      );
    }
    final repos = _filtered;
    if (repos.isEmpty) {
      return Center(
        child: Text(
          _repos.isEmpty ? '沒有任何 repo' : '找不到符合的 repo',
          style: TextStyle(color: c.mute, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: repos.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
      itemBuilder: (context, index) {
        final repo = repos[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            repo.private ? Icons.lock_outline : Icons.folder_outlined,
            size: 20,
            color: c.dim,
          ),
          title: Text(
            repo.fullName,
            style: TextStyle(color: c.text, fontSize: 14),
          ),
          subtitle: repo.description == null || repo.description!.isEmpty
              ? null
              : Text(
                  repo.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.mute, fontSize: 12),
                ),
          onTap: () => Navigator.of(context).pop(repo.fullName),
        );
      },
    );
  }
}
