import 'package:flutter/material.dart';

import '../../services/theme_prefs.dart';
import '../../theme.dart';
import '../../widgets/color_swatch_row.dart';

/// Which colour a custom picker edits within a theme.
enum ThemeColorRole { accent, background }

/// The theme colour section ("主題顏色"): one block per light/dark theme,
/// each with an accent row (default + per-theme presets + custom) and an
/// auto/custom background row, all using the shared big-circle swatch row.
class ThemeColorsSection extends StatelessWidget {
  final ThemeCustomization custom;
  final void Function(Brightness brightness, Color? accent) onSelectAccent;
  final void Function(Brightness brightness, Color? background)
  onSelectBackground;
  final void Function(Brightness brightness, ThemeColorRole role) onPickCustom;
  final void Function(Brightness brightness) onReset;

  const ThemeColorsSection({
    super.key,
    required this.custom,
    required this.onSelectAccent,
    required this.onSelectBackground,
    required this.onPickCustom,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);

    Widget themeBlock({
      required String label,
      required Color? accent,
      required Color? background,
      required Brightness brightness,
    }) {
      final isDark = brightness == Brightness.dark;
      final presets = isDark ? darkAccentPresets : lightAccentPresets;
      final defaultAccent = isDark
          ? ItouColors.dark.blue
          : ItouColors.light.blue;
      final defaultBg = isDark ? ItouColors.dark.bg : ItouColors.light.bg;
      final presetIndex = accent == null ? -1 : presets.indexOf(accent);
      // Index 0 = 預設 (theme's built-in colour); -1 = custom selected.
      final accentIndex = accent == null
          ? 0
          : presetIndex >= 0
          ? presetIndex + 1
          : -1;
      // The "自動" circle previews the background that will actually apply:
      // an accent-derived tint once an accent is set, the theme default
      // otherwise.
      final autoBg = accent != null
          ? ItouColors.autoBackground(accent, brightness)
          : defaultBg;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => onReset(brightness),
                child: Text(
                  '重設',
                  style: TextStyle(color: c.mute, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('主色', style: TextStyle(color: c.dim, fontSize: 11)),
          const SizedBox(height: 6),
          ColorSwatchRow(
            swatches: [defaultAccent, ...presets],
            selectedIndex: accentIndex,
            customColor: accent,
            onSwatchTap: (i) =>
                onSelectAccent(brightness, i == 0 ? null : presets[i - 1]),
            onCustomTap: () => onPickCustom(brightness, ThemeColorRole.accent),
          ),
          const SizedBox(height: 14),
          Text('背景', style: TextStyle(color: c.dim, fontSize: 11)),
          const SizedBox(height: 6),
          ColorSwatchRow(
            swatches: [autoBg],
            selectedIndex: background == null ? 0 : -1,
            customColor: background,
            onSwatchTap: (_) => onSelectBackground(brightness, null),
            onCustomTap: () =>
                onPickCustom(brightness, ThemeColorRole.background),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('主題顏色', style: TextStyle(color: c.text, fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            '主色用於按鈕與連結等強調色；背景「自動」會跟隨主色衍生，'
            '淺色與深色主題可分別設定。',
            style: TextStyle(color: c.dim, fontSize: 12),
          ),
          const SizedBox(height: 14),
          themeBlock(
            label: '淺色主題',
            accent: custom.lightAccent,
            background: custom.lightBackground,
            brightness: Brightness.light,
          ),
          const SizedBox(height: 14),
          themeBlock(
            label: '深色主題',
            accent: custom.darkAccent,
            background: custom.darkBackground,
            brightness: Brightness.dark,
          ),
        ],
      ),
    );
  }
}
