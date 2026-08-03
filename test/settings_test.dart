import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:itou_md/screens/settings_screen.dart';
import 'package:itou_md/services/theme_prefs.dart';
import 'package:itou_md/services/ui_prefs.dart';
import 'package:itou_md/theme.dart';
import 'package:itou_md/widgets/color_swatch_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping the first (default) accent swatch clears the accent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    ThemeCustomization? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: ItouTheme.lightTheme,
        home: SettingsScreen(
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) {},
          customization: const ThemeCustomization(
            lightAccent: Color(0xFF2E9E9E),
          ),
          onCustomizationChanged: (c) => received = c,
          uiScale: UiScale.standard,
          onUiScaleChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The first ColorSwatchRow in the tree is the light theme's accent
    // row; its first circle is the 預設 (default) swatch.
    final accentRow = find.byType(ColorSwatchRow).first;
    await tester.ensureVisible(accentRow);
    await tester.pumpAndSettle();

    final rect = tester.getRect(accentRow);
    await tester.tapAt(rect.topLeft + const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.lightAccent, isNull);
  });

  testWidgets(
    'tapping the first (auto) background swatch clears the background',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      ThemeCustomization? received;
      await tester.pumpWidget(
        MaterialApp(
          theme: ItouTheme.lightTheme,
          home: SettingsScreen(
            themeMode: ThemeMode.light,
            onThemeModeChanged: (_) {},
            customization: const ThemeCustomization(
              lightBackground: Color(0xFF123456),
            ),
            onCustomizationChanged: (c) => received = c,
            uiScale: UiScale.standard,
            onUiScaleChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rows = find.byType(ColorSwatchRow);
      // Light accent, light background, dark accent, dark background...
      final backgroundRow = rows.at(1);
      await tester.ensureVisible(backgroundRow);
      await tester.pumpAndSettle();

      await tester.tapAt(
        tester.getTopLeft(backgroundRow) + const Offset(20, 20),
      );
      await tester.pumpAndSettle();

      expect(received, isNotNull);
      expect(received!.lightBackground, isNull);
    },
  );
}
