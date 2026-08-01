import 'package:flutter_test/flutter_test.dart';

import 'package:itou_md/main.dart';

void main() {
  testWidgets('Home screen shows the three input methods', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ItouMdApp());
    await tester.pumpAndSettle();

    expect(find.text('貼上文字'), findsOneWidget);
    expect(find.text('選擇本機檔案'), findsOneWidget);
    expect(find.text('貼上網址'), findsOneWidget);
  });
}
