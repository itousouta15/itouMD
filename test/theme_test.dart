import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:itou_md/services/custom_fonts.dart';
import 'package:itou_md/services/reader_prefs.dart';
import 'package:itou_md/services/theme_prefs.dart';
import 'package:itou_md/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ItouColors.withAccent', () {
    test('overrides blue and derives a distinct purple', () {
      const accent = Color(0xFFE05252);
      final dark = ItouColors.dark.withAccent(accent);
      expect(dark.blue, accent);
      expect(dark.purple, isNot(accent));
      expect(dark.bg, ItouColors.dark.bg);
      expect(dark.text, ItouColors.dark.text);
    });

    test('null accent keeps the defaults', () {
      expect(
        identical(ItouColors.dark.withAccent(null), ItouColors.dark),
        isTrue,
      );
    });

    test('explicit purple is honoured', () {
      const purple = Color(0xFF112233);
      final light = ItouColors.light.withAccent(
        const Color(0xFF111111),
        purple: purple,
      );
      expect(light.blue, const Color(0xFF111111));
      expect(light.purple, purple);
    });
  });

  group('ItouColors.withBackground', () {
    test('derives distinct surfaces from the background', () {
      final light = ItouColors.light.withBackground(const Color(0xFFF5F1E8));
      expect(light.bg, const Color(0xFFF5F1E8));
      expect(light.panel, isNot(light.bg));
      expect(light.inset, isNot(light.bg));
      expect(light.panelHover, isNot(light.bg));
    });

    test('dark background switches text tokens to the light-on-dark set', () {
      final custom = ItouColors.light.withBackground(const Color(0xFF111318));
      expect(custom.bg, const Color(0xFF111318));
      expect(custom.text, ItouColors.dark.text);
      expect(custom.border, ItouColors.dark.border);
    });

    test('null background keeps the defaults', () {
      expect(
        identical(ItouColors.dark.withBackground(null), ItouColors.dark),
        isTrue,
      );
    });

    test('chains after withAccent without losing the accent', () {
      const accent = Color(0xFFE05252);
      final custom = ItouColors.dark
          .withAccent(accent)
          .withBackground(const Color(0xFF2E3138));
      expect(custom.blue, accent);
      expect(custom.bg, const Color(0xFF2E3138));
    });
  });

  group('ItouColors.autoBackground', () {
    test('keeps the accent hue and clamps to a soft tint', () {
      const accent = Color(0xFFE05252);
      final lightBg = ItouColors.autoBackground(accent, Brightness.light);
      final lightHsl = HSLColor.fromColor(lightBg);
      expect(lightHsl.hue, closeTo(HSLColor.fromColor(accent).hue, 0.001));
      expect(lightHsl.saturation, closeTo(0.15, 0.005));
      expect(lightHsl.lightness, closeTo(0.92, 0.01));

      final darkBg = ItouColors.autoBackground(accent, Brightness.dark);
      final darkHsl = HSLColor.fromColor(darkBg);
      expect(darkHsl.hue, closeTo(HSLColor.fromColor(accent).hue, 0.001));
      expect(darkHsl.saturation, closeTo(0.15, 0.005));
      expect(darkHsl.lightness, closeTo(0.12, 0.01));
    });

    test('a desaturated accent yields a near-neutral background', () {
      const gray = Color(0xFF777777);
      final bg = ItouColors.autoBackground(gray, Brightness.light);
      expect(HSLColor.fromColor(bg).saturation, lessThan(0.051));
    });
  });

  group('accent presets brightness bands', () {
    test('light-theme presets stay in the light-theme accent band', () {
      for (final color in lightAccentPresets) {
        final lightness = HSLColor.fromColor(color).lightness;
        expect(
          lightness,
          inInclusiveRange(0.2, 0.6),
          reason: '$color has lightness $lightness',
        );
      }
    });

    test('dark-theme presets stay in the dark-theme accent band', () {
      for (final color in darkAccentPresets) {
        final lightness = HSLColor.fromColor(color).lightness;
        expect(
          lightness,
          inInclusiveRange(0.5, 0.9),
          reason: '$color has lightness $lightness',
        );
      }
    });
  });

  group('ThemePrefs', () {
    test('copyWith can clear a colour back to null (default)', () {
      const custom = ThemeCustomization(
        lightAccent: Color(0xFF2E9E9E),
        darkBackground: Color(0xFF111318),
      );
      final cleared = custom.copyWith(lightAccent: null);
      expect(cleared.lightAccent, isNull);
      expect(cleared.darkBackground, const Color(0xFF111318));

      final bothCleared = cleared.copyWith(
        darkAccent: null,
        darkBackground: null,
      );
      expect(bothCleared.darkAccent, isNull);
      expect(bothCleared.darkBackground, isNull);
    });

    test('round-trips all four colours and clears to null', () async {
      SharedPreferences.setMockInitialValues({});
      await ThemePrefs.save(
        const ThemeCustomization(
          lightAccent: Color(0xFF123456),
          darkAccent: Color(0xFF654321),
          lightBackground: Color(0xFFF0EDE4),
          darkBackground: Color(0xFF0A0C10),
        ),
      );
      final loaded = await ThemePrefs.load();
      expect(loaded.lightAccent, const Color(0xFF123456));
      expect(loaded.darkAccent, const Color(0xFF654321));
      expect(loaded.lightBackground, const Color(0xFFF0EDE4));
      expect(loaded.darkBackground, const Color(0xFF0A0C10));

      await ThemePrefs.save(const ThemeCustomization());
      final cleared = await ThemePrefs.load();
      expect(cleared.lightAccent, isNull);
      expect(cleared.darkAccent, isNull);
      expect(cleared.lightBackground, isNull);
      expect(cleared.darkBackground, isNull);
    });
  });

  group('CustomFonts', () {
    test(
      'init with a missing font file clears the persisted settings',
      () async {
        SharedPreferences.setMockInitialValues({
          'custom_font_path': 'C:/nonexistent/definitely-not-there.ttf',
          'custom_font_family': 'MissingFont',
        });
        await CustomFonts.init();
        expect(CustomFonts.currentFamily, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('custom_font_path'), isNull);
        expect(prefs.getString('custom_font_family'), isNull);
      },
    );

    test('init with no persisted font is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      await CustomFonts.init();
      expect(CustomFonts.currentFamily, isNull);
    });
  });

  group('ReaderPrefs', () {
    test('falls back from custom font when none is loaded', () async {
      SharedPreferences.setMockInitialValues({
        'reader_font_family': ReaderFontFamily.custom.index,
      });
      final prefs = await ReaderPrefs.load();
      expect(prefs.fontFamily, ReaderFontFamily.sans);
    });
  });
}
