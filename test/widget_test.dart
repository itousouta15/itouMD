import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:itou_md/main.dart';

void main() {
  testWidgets('Home screen shows the three input methods', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'itou_md_onboarding_done': true});
    await tester.pumpWidget(const ItouMdApp(onboardingDone: true));
    await tester.pumpAndSettle();

    expect(find.text('貼上文字'), findsOneWidget);
    expect(find.text('選擇本機檔案'), findsOneWidget);
    expect(find.text('貼上網址'), findsOneWidget);
  });

  testWidgets('First launch shows the onboarding wizard', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ItouMdApp(onboardingDone: false));
    await tester.pumpAndSettle();

    expect(find.text('手機也能好好用 MD'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);

    // Step through to the last page, then start.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }
    expect(find.text('開始使用'), findsOneWidget);
    await tester.tap(find.text('開始使用'));
    await tester.pumpAndSettle();

    expect(find.text('貼上文字'), findsOneWidget);
  });

  testWidgets('Onboarding can be skipped straight to home', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ItouMdApp(onboardingDone: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('跳過'));
    await tester.pumpAndSettle();

    expect(find.text('貼上文字'), findsOneWidget);
  });
}
