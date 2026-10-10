import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:itou_md/services/collab_api.dart';
import 'package:itou_md/services/collab_drafts.dart';
import 'package:itou_md/services/collab_session.dart';

class MemoryServer {
  String text = 'base\n';
  int revision = 1;
  bool offline = false;
  bool loseResponse = false;
  int puts = 0;
  void Function()? beforePut;
  Completer<void>? putStarted;
  Completer<void>? putRelease;
  Completer<void>? getStarted;
  Completer<void>? getRelease;

  Map<String, dynamic> snapshot(String room) => {
    'room': room,
    'content': text,
    'revision': '$revision',
    'pending': false,
  };
  http.Response json(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    expect(request.followRedirects, false);
    final room = request.url.queryParameters['room']!;
    if (request.method == 'GET') {
      getStarted?.complete();
      await getRelease?.future;
      return json(snapshot(room));
    }
    puts++;
    beforePut?.call();
    putStarted?.complete();
    await putRelease?.future;
    final body = jsonDecode(request.body);
    if (body['revision'] != '$revision') {
      return json({'current': snapshot(room)}, 409);
    }
    text = body['content'];
    revision++;
    if (loseResponse) {
      loseResponse = false;
      throw http.ClientException('response lost after commit');
    }
    return json(snapshot(room));
  }
}

class FailableStore extends CollabDraftStore {
  bool fail = false;
  Completer<void>? hold;
  final started = <String>[];
  @override
  Future<void> save(CollabDraft draft) async {
    if (fail) throw StateError('disk full');
    started.add(draft.text);
    if (draft.text == 'first') await hold?.future;
    await super.save(draft);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final endpoint = CollabEndpoint.parse('http://127.0.0.1:8787', 'Demo');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<CollabSession> open(
    MemoryServer server, {
    CollabDraftStore? store,
  }) async {
    final session = await CollabSession.open(
      endpoint,
      store: store,
      api: CollabApi(endpoint, client: MockClient(server.handle)),
    );
    addTearDown(session.dispose);
    return session;
  }

  Future<String?> noConflict(String base, String local, String remote) async =>
      fail('Unexpected conflict');

  test(
    'endpoint validation rejects secret/path URLs and keeps room identity case-sensitive',
    () {
      for (final url in [
        'ftp://localhost',
        'http://user:secret@localhost',
        'http://@localhost',
        'http://localhost/path',
        'http://localhost?token=secret',
        'http://localhost#secret',
        'http://localhost:0',
        'http://localhost:99999',
        'not a server',
        'http://local host',
      ]) {
        expect(
          () => CollabEndpoint.parse(url, 'Demo'),
          throwsFormatException,
          reason: url,
        );
      }
      expect(
        () => CollabEndpoint.parse('http://localhost', ' room'),
        throwsFormatException,
      );
      expect(
        () => CollabEndpoint.parse('http://localhost', 'bad.room'),
        throwsFormatException,
      );
      expect(
        () => CollabEndpoint.parse('http://localhost', 'room\n'),
        throwsFormatException,
      );
      expect(
        CollabEndpoint.parse('http://LOCALHOST:80/', 'Demo').key,
        CollabEndpoint.parse('http://localhost', 'Demo').key,
      );
      expect(
        endpoint.key,
        isNot(CollabEndpoint.parse('http://127.0.0.1:8787', 'demo').key),
      );
      expect(
        endpoint.key,
        isNot(CollabEndpoint.parse('http://127.0.0.1:8788', 'Demo').key),
      );
    },
  );

  test(
    'native draft and base survive offline failure and reopening without a network request',
    () async {
      final server = MemoryServer();
      final session = await open(server);
      await session.synchronize(noConflict);
      session.edit('native offline\n');
      server.offline = true;
      await session.synchronize(noConflict);
      expect(session.message, contains('無法連到'));
      final reopened = await open(server);
      expect(reopened.draft.text, 'native offline\n');
      expect(reopened.draft.base!.content, 'base\n');
      expect(reopened.draft.base!.revision, '1');
      server.offline = false;
      await reopened.synchronize(noConflict);
      expect(server.text, 'native offline\n');
      expect(reopened.dirty, false);
    },
  );

  test(
    'a reviewed conflict is CAS-checked again if a browser changes during resolution',
    () async {
      final server = MemoryServer();
      final session = await open(server);
      await session.synchronize(noConflict);
      session.edit('native\n');
      server.text = 'browser one\n';
      server.revision++;
      final seen = <List<String>>[];
      server.beforePut = () {
        server.beforePut = null;
        server.text = 'browser two\n';
        server.revision++;
      };
      await session.synchronize((base, local, remote) async {
        seen.add([base, local, remote]);
        return seen.length == 1 ? 'first review\n' : 'second review\n';
      });
      expect(seen, [
        ['base\n', 'native\n', 'browser one\n'],
        ['browser one\n', 'first review\n', 'browser two\n'],
      ]);
      expect(server.text, 'second review\n');
      expect(
        (await CollabDraftStore().load(endpoint))!.base!.content,
        server.text,
      );
      expect(session.dirty, false);
    },
  );

  test(
    'canceling conflict resolution preserves both the native draft and its original base',
    () async {
      final server = MemoryServer();
      final session = await open(server);
      await session.synchronize(noConflict);
      session.edit('native');
      server.text = 'browser';
      server.revision++;
      await session.synchronize((base, local, remote) async => null);
      final saved = (await CollabDraftStore().load(endpoint))!;
      expect(saved.text, 'native');
      expect(saved.base!.content, 'base\n');
      expect(server.text, 'browser');
      expect(server.puts, 0);
    },
  );

  test(
    'a lost successful PUT response can be retried without duplicating the edit',
    () async {
      final server = MemoryServer();
      final session = await open(server);
      await session.synchronize(noConflict);
      session.edit('saved despite response loss');
      server.loseResponse = true;
      await session.synchronize(noConflict);
      expect(session.dirty, true);
      final reopened = await open(server);
      await reopened.synchronize(noConflict);
      expect(reopened.dirty, false);
      expect(server.puts, 1);
      expect(reopened.draft.base!.revision, '${server.revision}');
    },
  );

  test(
    'new edits during a pull are never replaced or rebased against unseen remote text',
    () async {
      final server = MemoryServer();
      final session = await open(server);
      await session.synchronize(noConflict);
      server.getStarted = Completer();
      server.getRelease = Completer();
      final syncing = session.synchronize(noConflict);
      await server.getStarted!.future;
      session.edit('typed while fetching');
      server.text = 'new remote';
      server.revision++;
      server.getRelease!.complete();
      await syncing;
      expect(session.draft.text, 'typed while fetching');
      expect(session.draft.base!.content, 'base\n');
      await session.flush();
      expect(
        (await CollabDraftStore().load(endpoint))!.text,
        session.draft.text,
      );
    },
  );

  test(
    'new edits during PUT keep their text while advancing only the confirmed base',
    () async {
      final server = MemoryServer();
      final session = await open(server);
      await session.synchronize(noConflict);
      session.edit('uploaded');
      server.putStarted = Completer();
      server.putRelease = Completer();
      final syncing = session.synchronize(noConflict);
      await server.putStarted!.future;
      session.edit('uploaded plus later edits');
      server.putRelease!.complete();
      await syncing;
      expect(server.text, 'uploaded');
      expect(session.draft.text, 'uploaded plus later edits');
      expect(session.draft.base!.content, 'uploaded');
      expect(session.dirty, true);
      expect(
        (await CollabDraftStore().load(endpoint))!.text,
        session.draft.text,
      );
    },
  );

  test(
    'local persistence failures block network writes and a later full save recovers all edits',
    () async {
      final server = MemoryServer();
      final store = FailableStore();
      final session = await open(server, store: store);
      await session.synchronize(noConflict);
      store.fail = true;
      session.edit('must keep');
      await session.synchronize(noConflict);
      expect(server.puts, 0);
      expect(session.localError, isNotNull);
      store.fail = false;
      expect(await session.flush(), true);
      await session.synchronize(noConflict);
      expect(server.text, 'must keep');
    },
  );

  test(
    'serialized preference writes cannot roll a draft back to an older edit',
    () async {
      final store = FailableStore();
      final session = await open(MemoryServer(), store: store);
      store.hold = Completer();
      session.edit('first');
      session.edit('second');
      await Future<void>.delayed(Duration.zero);
      expect(store.started, isNot(contains('second')));
      store.hold!.complete();
      await session.flush();
      expect((await store.load(endpoint))!.text, 'second');
    },
  );

  test(
    'corrupt draft records are reported and never silently replaced',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final key = '${CollabDraftStore.prefix}${endpoint.key}';
      await prefs.setString(key, '{');
      await expectLater(
        CollabSession.open(endpoint),
        throwsA(isA<CollabException>()),
      );
      expect(prefs.getString(key), '{');
      final healthy = CollabEndpoint.parse('http://127.0.0.1:8787', 'healthy');
      final store = CollabDraftStore();
      await store.save(
        CollabDraft(
          endpoint: healthy,
          text: 'readable',
          base: null,
          updatedAt: DateTime.now(),
        ),
      );
      final listing = await store.list();
      expect(listing.unreadable, 1);
      expect(listing.drafts.single.text, 'readable');
    },
  );

  test(
    'pending causal snapshots and wrong-room replies cannot overwrite native drafts',
    () async {
      final api = CollabApi(
        endpoint,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'room': endpoint.room,
              'content': 'not complete',
              'revision': 'r',
              'pending': true,
            }),
            200,
          ),
        ),
      );
      final session = await CollabSession.open(endpoint, api: api);
      addTearDown(session.dispose);
      session.edit('native');
      await session.synchronize(noConflict);
      expect(session.draft.text, 'native');
      expect(session.draft.base, isNull);
      expect(session.message, contains('因果更新'));
      final wrong = CollabApi(
        endpoint,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'room': 'demo',
              'content': 'wrong room',
              'revision': 'r',
              'pending': false,
            }),
            200,
          ),
        ),
      );
      addTearDown(wrong.close);
      await expectLater(wrong.get(), throwsA(isA<CollabException>()));
    },
  );
}
