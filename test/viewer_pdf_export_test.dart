import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:itou_md/screens/viewer_screen.dart';
import 'package:itou_md/theme.dart';

const _pickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> saves;
  late Future<String?> Function() saveResult;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    saves = [];
    saveResult = () async => '/documents/notes.pdf';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, (call) async {
          expect(call.method, 'save');
          saves.add(call);
          return saveResult();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, null);
  });

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ItouTheme.lightTheme,
        home: const ViewerScreen(
          title: 'notes.MD',
          content: '# Notes\n\n[Original](https://example.com/original)',
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byTooltip('更多操作').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
  }

  Future<void> export(WidgetTester tester) async {
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('匯出 PDF'));
    await tester.pump();
  }

  testWidgets('exports a PDF with a matching filename from the reader', (
    tester,
  ) async {
    await launch(tester);
    await export(tester);
    await _pumpUntil(tester, () => saves.isNotEmpty);
    await tester.pumpAndSettle();

    final arguments = saves.single.arguments as Map;
    expect(arguments['fileName'], 'notes.pdf');
    expect(arguments['fileType'], 'custom');
    expect(arguments['allowedExtensions'], ['pdf']);
    final bytes = arguments['bytes'] as Uint8List;
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(latin1.decode(bytes), contains('https://example.com/original'));
    expect(find.text('已匯出 PDF (｡•ᴗ•｡)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exports unsaved editor text without leaving edit mode', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    const draft = '# Draft\n\n[Unsaved](https://example.com/unsaved-draft)';
    await tester.enterText(find.byType(TextField), draft);
    await export(tester);
    await _pumpUntil(tester, () => saves.isNotEmpty);
    await tester.pumpAndSettle();

    final bytes = (saves.single.arguments as Map)['bytes'] as Uint8List;
    final pdf = latin1.decode(bytes);
    expect(pdf, contains('https://example.com/unsaved-draft'));
    expect(pdf, isNot(contains('https://example.com/original')));
    expect(find.byTooltip('完成編輯'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      draft,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disables duplicate exports and handles picker cancellation', (
    tester,
  ) async {
    final pending = Completer<String?>();
    saveResult = () => pending.future;
    await launch(tester);
    await export(tester);
    await _pumpUntil(tester, () => saves.isNotEmpty);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    final busyItem = find.widgetWithText(PopupMenuItem<String>, '正在匯出 PDF…');
    expect(tester.widget<PopupMenuItem<String>>(busyItem).enabled, isFalse);
    await tester.tap(busyItem);
    await tester.pump();
    expect(saves, hasLength(1));
    await tester.tapAt(Offset.zero);
    pending.complete(null);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    final retryItem = find.widgetWithText(PopupMenuItem<String>, '匯出 PDF');
    expect(tester.widget<PopupMenuItem<String>>(retryItem).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports a save failure and allows a successful retry', (
    tester,
  ) async {
    saveResult = () async => throw PlatformException(code: 'write_failed');
    await launch(tester);
    await export(tester);
    await _pumpUntil(tester, () => saves.isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('PDF 匯出失敗，再試一次看看 (´;ω;`)'), findsOneWidget);

    saveResult = () async => '/documents/notes.pdf';
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await export(tester);
    await _pumpUntil(tester, () => saves.length == 2);
    await tester.pumpAndSettle();
    expect(find.text('已匯出 PDF (｡•ᴗ•｡)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finishing an export after leaving the viewer is harmless', (
    tester,
  ) async {
    final pending = Completer<String?>();
    saveResult = () => pending.future;
    await launch(tester);
    await export(tester);
    await _pumpUntil(tester, () => saves.isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete('/documents/notes.pdf');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
