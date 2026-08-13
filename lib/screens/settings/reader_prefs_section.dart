import 'package:flutter/material.dart';

import '../../services/reader_prefs.dart';
import '../../theme.dart';
import '../../widgets/color_swatch_row.dart';
import '../../widgets/reader_font_picker.dart';

class ReaderPrefsSection extends StatelessWidget {
  final ReaderPrefs prefs;
  final ValueChanged<ReaderPrefs> onChanged;
  final VoidCallback onCustomColorTap;

  const ReaderPrefsSection({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.onCustomColorTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '字體',
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ReaderFontPicker(
            selected: prefs.fontFamily,
            onChanged: (f) => onChanged(prefs.copyWith(fontFamily: f)),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.inset,
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('預覽', style: TextStyle(color: c.mute, fontSize: 11)),
                const SizedBox(height: 8),
                Text(
                  '中文閱讀體驗、The quick brown fox と日本語。',
                  style: prefs.fontFamily.textStyle().copyWith(
                    fontSize: prefs.fontSize,
                    color: prefs.textColor.resolve(
                      c,
                      brightness,
                      prefs.customColor,
                    ),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '## Heading  *italic*  **bold**  `code`',
                  style: prefs.fontFamily.textStyle().copyWith(
                    fontSize: prefs.fontSize - 2,
                    color: prefs.textColor
                        .resolve(c, brightness, prefs.customColor)
                        .withValues(alpha: 0.7),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '字級',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                prefs.fontSize.toStringAsFixed(0),
                style: TextStyle(color: c.dim, fontSize: 12),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: c.blue,
              inactiveTrackColor: c.border2,
              thumbColor: c.blue,
              overlayColor: c.blue.withValues(alpha: 0.15),
              trackHeight: 2,
            ),
            child: Slider(
              value: prefs.fontSize,
              min: ReaderPrefs.minFontSize,
              max: ReaderPrefs.maxFontSize,
              divisions:
                  ((ReaderPrefs.maxFontSize - ReaderPrefs.minFontSize) / 0.5)
                      .round(),
              onChanged: (v) => onChanged(prefs.copyWith(fontSize: v)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '文字顏色',
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ReaderColorRow(
            selected: prefs.textColor,
            customColor: prefs.customColor,
            brightness: brightness,
            onSwatch: (tc) => onChanged(prefs.copyWith(textColor: tc)),
            onCustom: onCustomColorTap,
          ),
        ],
      ),
    );
  }
}
