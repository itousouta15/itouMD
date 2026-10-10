import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:itou_md/screens/collab_cloud_tab.dart';
import 'package:itou_md/screens/conflict_screen.dart';
import 'package:itou_md/screens/viewer_screen.dart';
import 'package:itou_md/services/collab_api.dart';
import 'package:itou_md/services/collab_drafts.dart';
import 'package:itou_md/theme.dart';

import 'collab_test.dart' show MemoryServer, FailableStore;

// Markdown rendering uses compute; let its real isolate run between fake-clock frames.
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> launch(
    WidgetTester tester,
    MemoryServer server, {
    CollabDraftStore? store,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ItouTheme.lightTheme,
        home: Scaffold(
          body: CollabCloudTab(
            store: store,
            apiFactory: (endpoint) =>
                CollabApi(endpoint, client: MockClient(server.handle)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('開啟協作草稿'));
    await pumpUntil(tester, find.byTooltip('編輯'));
  }

  testWidgets(
    'Cloud opens the real editor; offline edits survive leaving/reopening and sync natively',
    (tester) async {
      final server = MemoryServer();
      await launch(tester, server);
      await tester.tap(find.text('同步 / 重試'));
      await pumpUntil(tester, find.text('已讀取伺服器版本。'));
      await tester.tap(find.byTooltip('編輯'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'base\n',
      );
      server.offline = true;
      await tester.enterText(find.byType(TextField), '# Native offline\n');
      await tester.tap(find.text('同步 / 重試'));
      await pumpUntil(tester, find.textContaining('無法連到協作伺服器'));
      await tester.pageBack();
      await pumpUntil(tester, find.text('開啟協作草稿'));
      expect(find.widgetWithText(ListTile, 'demo'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'demo'));
      await pumpUntil(tester, find.byTooltip('編輯'));
      await tester.tap(find.byTooltip('編輯'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '# Native offline\n',
      );
      server.offline = false;
      await tester.tap(find.text('同步 / 重試'));
      await pumpUntil(tester, find.text('已同步到伺服器。'));
      expect(server.text, '# Native offline\n');
      await tester.pageBack();
      await pumpUntil(tester, find.text('開啟協作草稿'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale native edits open the existing conflict screen; cancel preserves draft and retry can choose remote',
    (tester) async {
      final server = MemoryServer();
      await launch(tester, server);
      await tester.tap(find.text('同步 / 重試'));
      await pumpUntil(tester, find.text('已讀取伺服器版本。'));
      await tester.tap(find.byTooltip('編輯'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'local version\n');
      server.text = 'browser version\n';
      server.revision++;
      await tester.tap(find.text('同步 / 重試'));
      await pumpUntil(tester, find.byType(ConflictScreen));
      expect(find.text('直接用本地覆蓋'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'local version\n',
      );
      expect(server.text, 'browser version\n');
      await tester.tap(find.text('同步 / 重試'));
      await pumpUntil(tester, find.byType(ConflictScreen));
      await tester.tap(find.text('保留遠端'));
      await tester.tap(find.text('合併並同步'));
      await pumpUntil(tester, find.text('已同步到伺服器。'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'browser version\n',
      );
      await tester.pageBack();
      await pumpUntil(tester, find.text('開啟協作草稿'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed draft storage keeps the editor open until a successful retry',
    (tester) async {
      final server = MemoryServer()..offline = true;
      final store = FailableStore();
      await launch(tester, server, store: store);
      await tester.tap(find.byTooltip('編輯'));
      await tester.pumpAndSettle();
      store.fail = true;
      await tester.enterText(find.byType(TextField), 'do not lose');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ViewerScreen), findsOneWidget);
      expect(find.textContaining('本機草稿儲存失敗'), findsOneWidget);
      store.fail = false;
      await tester.tap(find.text('重試本機儲存'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await pumpUntil(tester, find.text('開啟協作草稿'));
      final saved = await store.load(
        CollabEndpoint.parse('http://127.0.0.1:8787', 'demo'),
      );
      expect(saved!.text, 'do not lose');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('done editing retains the field when its local save fails', (tester) async {
    final server = MemoryServer()..offline = true;
    final store = FailableStore();
    await launch(tester, server, store: store);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.enterText(find.byType(TextField), 'unsaved editor text');
    await tester.tap(find.byTooltip('完成編輯'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('完成編輯'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'unsaved editor text');
    store.fail = false;
    await tester.tap(find.byTooltip('完成編輯'));
    await pumpUntil(tester, find.byTooltip('編輯'));
    await tester.pageBack();
    await pumpUntil(tester, find.text('開啟協作草稿'));
  });

  testWidgets('back waits for later edits and prevents a sync during its save', (tester) async {
    final server = MemoryServer();
    final store = FailableStore();
    await launch(tester, server, store: store);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    store.hold = Completer();
    await tester.enterText(find.byType(TextField), 'first');
    await tester.pageBack();
    await tester.pump();
    expect(find.byType(ViewerScreen), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '同步 / 重試')).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'typed while leaving');
    store.fail = true;
    store.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ViewerScreen), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'typed while leaving');
    store.fail = false;
    await tester.pageBack();
    await pumpUntil(tester, find.text('開啟協作草稿'));
    final saved = await store.load(CollabEndpoint.parse('http://127.0.0.1:8787', 'demo'));
    expect(saved!.text, 'typed while leaving');
  });

  testWidgets('a pending back save does not pop a subsequently opened route', (tester) async {
    final store = FailableStore();
    await launch(tester, MemoryServer(), store: store);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    store.hold = Completer();
    await tester.enterText(find.byType(TextField), 'first');
    await tester.pageBack();
    await tester.pump();
    final navigator = Navigator.of(tester.element(find.byType(ViewerScreen)));
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('another route')),
    )));
    await tester.pumpAndSettle();
    store.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('another route'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.enterText(find.byType(TextField), 'still guarded');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ViewerScreen), findsOneWidget);
    store.fail = false;
    await tester.pageBack();
    await pumpUntil(tester, find.text('開啟協作草稿'));
  });
}
