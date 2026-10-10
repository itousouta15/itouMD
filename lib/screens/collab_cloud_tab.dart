import 'package:flutter/material.dart';

import '../services/collab_api.dart';
import '../services/collab_drafts.dart';
import '../services/collab_session.dart';
import 'viewer_screen.dart';

class CollabCloudTab extends StatefulWidget {
  final CollabDraftStore? store;
  final CollabApi Function(CollabEndpoint)? apiFactory;
  const CollabCloudTab({super.key, this.store, this.apiFactory});

  @override
  State<CollabCloudTab> createState() => _CollabCloudTabState();
}

class _CollabCloudTabState extends State<CollabCloudTab> {
  final _server = TextEditingController(text: 'http://127.0.0.1:8787');
  final _room = TextEditingController(text: 'demo');
  late final _store = widget.store ?? CollabDraftStore();
  List<CollabDraft> _drafts = [];
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load(restore: true);
  }

  Future<void> _load({bool restore = false}) async {
    try {
      final listing = await _store.list();
      final drafts = listing.drafts;
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        if (listing.unreadable > 0) {
          _error = '有 ${listing.unreadable} 份協作草稿無法讀取。可讀草稿仍列於下方，損壞資料已保留。';
        }
        if (restore && drafts.isNotEmpty) {
          _server.text = drafts.first.endpoint.server.toString();
          _room.text = drafts.first.endpoint.room;
        }
      });
    } on CollabException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '無法讀取本機草稿，請重試。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open([CollabEndpoint? selected]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    CollabSession? session;
    try {
      final endpoint =
          selected ?? CollabEndpoint.parse(_server.text, _room.text);
      session = await CollabSession.open(
        endpoint,
        store: _store,
        api: widget.apiFactory?.call(endpoint),
      );
      if (!mounted) return;
      final opened = session;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ViewerScreen(
            title: endpoint.room,
            content: opened.draft.text,
            collaboration: opened,
          ),
        ),
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on CollabException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '開啟協作草稿失敗，請重試。');
    } finally {
      session?.dispose();
      if (mounted) await _load();
    }
  }

  @override
  void dispose() {
    _server.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('本機協作文件', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        '在 App 閱讀與編輯 Markdown，草稿自動存於本機。開啟後按「同步 / 重試」讀取或送出版本；瀏覽器端仍使用即時 Yjs 協作。',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _server,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: '協作伺服器',
          hintText: 'http://127.0.0.1:8787',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _room,
        enabled: !_busy,
        autocorrect: false,
        decoration: const InputDecoration(labelText: '房間名稱（區分大小寫）'),
        onSubmitted: (_) {
          if (!_busy) _open();
        },
      ),
      const SizedBox(height: 12),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      FilledButton.icon(
        onPressed: _busy ? null : () => _open(),
        icon: const Icon(Icons.edit_document),
        label: const Text('開啟協作草稿'),
      ),
      const SizedBox(height: 8),
      const Text(
        '僅供可信任的本機原型使用，網址不含帳密或權杖。Android USB 測試可用 adb reverse tcp:8787 tcp:8787；localhost 指目前裝置。',
      ),
      const SizedBox(height: 24),
      Text('本機協作草稿', style: Theme.of(context).textTheme.titleMedium),
      if (_drafts.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('尚無協作草稿。離線也能建立。'),
        ),
      for (final draft in _drafts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: Text(draft.endpoint.room),
          subtitle: Text(
            '${draft.endpoint.server}\n${draft.base == null
                ? '尚未同步'
                : draft.text != draft.base!.content
                ? '有待同步編輯'
                : '已保存上次同步版本'}',
          ),
          isThreeLine: true,
          onTap: _busy ? null : () => _open(draft.endpoint),
        ),
    ],
  );
}
