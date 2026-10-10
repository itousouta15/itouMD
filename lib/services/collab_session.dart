import 'dart:async';

import 'package:flutter/foundation.dart';

import 'collab_api.dart';
import 'collab_drafts.dart';

typedef CollabResolver =
    Future<String?> Function(String base, String local, String remote);

/// Explicit snapshot synchronization, not a native CRDT. All writes use CAS,
/// including a user's conflict resolution. A second race must be reviewed again.
class CollabSession extends ChangeNotifier {
  final CollabApi api;
  final CollabDraftStore store;
  CollabDraft _draft;
  Future<void> _writes = Future.value();
  int _pendingWrites = 0;
  int _generation = 0;
  bool _disposed = false;
  bool busy = false;
  String? localError;
  String message = '尚未同步；可先編輯本機草稿。';

  CollabSession._(this.api, this.store, this._draft);

  static Future<CollabSession> open(
    CollabEndpoint endpoint, {
    CollabApi? api,
    CollabDraftStore? store,
  }) async {
    final storage = store ?? CollabDraftStore();
    final saved = await storage.load(endpoint);
    final session = CollabSession._(
      api ?? CollabApi(endpoint),
      storage,
      saved ??
          CollabDraft(
            endpoint: endpoint,
            text: '',
            base: null,
            updatedAt: DateTime.now(),
          ),
    );
    session._replace();
    await session.flush();
    return session;
  }

  CollabDraft get draft => _draft;
  bool get dirty => _draft.text != (_draft.base?.content ?? '');
  bool get saving => _pendingWrites > 0;
  String get localStatus => localError ?? (saving ? '正在儲存本機草稿…' : '草稿已存於本機');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void edit(String text) {
    if (_disposed || text == _draft.text) return;
    _generation++;
    _replace(text: text);
    _persist();
  }

  void _replace({String? text, CollabSnapshot? base}) {
    _draft = CollabDraft(
      endpoint: _draft.endpoint,
      text: text ?? _draft.text,
      base: base ?? _draft.base,
      updatedAt: DateTime.now(),
    );
  }

  void _persist() {
    final snapshot = _draft;
    _pendingWrites++;
    _notify();
    // Serialize snapshots so a slower earlier write cannot overwrite a newer draft/base.
    _writes = _writes.then((_) async {
      try {
        await store.save(snapshot);
        localError = null;
      } catch (_) {
        localError = '本機草稿儲存失敗；請重試或先另存新檔。';
      }
      _pendingWrites--;
      _notify();
    });
  }

  Future<bool> flush() async {
    _persist();
    while (_pendingWrites > 0) {
      await _writes;
    }
    return localError == null;
  }

  Future<void> synchronize(CollabResolver resolve) async {
    if (busy || _disposed) return;
    busy = true;
    message = '正在同步快照…';
    _notify();
    try {
      if (!await flush()) {
        message = '尚未連線：請先重試本機儲存。';
        return;
      }
      var generation = _generation;
      var remote = await api.get();
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_disposed) return;
        if (_generation != generation) {
          message = '同步期間草稿有新編輯，已保留；請再按同步。';
          return;
        }
        if (remote.pending) {
          throw const CollabException('伺服器仍在等待瀏覽器的因果更新，請稍後重試。草稿已保留。');
        }
        final local = _draft.text;
        final base = _draft.base?.content ?? '';
        if (local == base || local == remote.content) {
          _replace(text: remote.content, base: remote);
          await flush();
          message = '已讀取伺服器版本。';
          return;
        }
        var next = local;
        if (remote.content != base) {
          final merged = await resolve(base, local, remote.content);
          if (_disposed) return;
          if (merged == null || generation != _generation) {
            message = '未送出合併；本機草稿已保留。';
            return;
          }
          next = merged;
        }
        // Persist the reviewed merge against its exact new base BEFORE sending it.
        _replace(text: next, base: remote);
        _generation++;
        generation = _generation;
        if (!await flush()) {
          message = '尚未送出：請先重試本機儲存。';
          return;
        }
        if (_generation != generation) {
          message = '草稿有新編輯，請再按同步。';
          return;
        }
        try {
          final saved = await api.put(next, remote.revision);
          if (saved.content != next || saved.pending) {
            throw const CollabException('伺服器確認內容不符，草稿已保留，請重試。');
          }
          // Editing can continue during the HTTP request. Advance the confirmed base,
          // but never replace newer local text with the response to an older upload.
          _replace(base: saved);
          await flush();
          message = dirty ? '先前版本已同步；新編輯仍待同步。' : '已同步到伺服器。';
          return;
        } on CollabConflict catch (conflict) {
          remote = conflict.current;
        }
      }
      message = '伺服器持續變動，請稍後再按同步。草稿與合併結果已保留。';
    } on CollabException catch (error) {
      message = error.message;
    } catch (_) {
      message = '同步失敗，草稿已保留；請重試。';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    api.close();
    super.dispose();
  }
}
