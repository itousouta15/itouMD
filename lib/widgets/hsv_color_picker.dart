import 'package:flutter/material.dart';

import '../theme.dart';

/// Shows a hue/saturation/brightness colour picker dialog. Returns the
/// picked colour, or null when cancelled. [minBrightness]/[maxBrightness]
/// constrain the 亮度 slider so e.g. a light theme can't pick near-black
/// backgrounds — the initial colour is clamped into the range as well.
Future<Color?> showHsvColorPicker(
  BuildContext context, {
  required Color initial,
  double minBrightness = 0,
  double maxBrightness = 1,
}) async {
  double hue = HSVColor.fromColor(initial).hue;
  double saturation = HSVColor.fromColor(initial).saturation;
  double brightness = HSVColor.fromColor(
    initial,
  ).value.clamp(minBrightness, maxBrightness);

  final result = await showDialog<Color>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final c = ItouColorsExt.of(ctx);
          final current = HSVColor.fromAHSV(
            1,
            hue,
            saturation,
            brightness,
          ).toColor();
          return AlertDialog(
            title: const Text('自訂顏色'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: current,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border2, width: 2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _HsvSlider(
                    label: '色相',
                    gradientColors: const [
                      Colors.red,
                      Colors.yellow,
                      Colors.green,
                      Colors.cyan,
                      Colors.blue,
                      Color(0xFFFF00FF),
                      Colors.red,
                    ],
                    value: hue,
                    max: 360,
                    thumbColor: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                    onChanged: (v) => setDialogState(() => hue = v),
                  ),
                  _HsvSlider(
                    label: '飽和度',
                    gradientColors: [
                      HSVColor.fromAHSV(1, hue, 0, brightness).toColor(),
                      HSVColor.fromAHSV(1, hue, 1, brightness).toColor(),
                    ],
                    value: saturation,
                    max: 1,
                    thumbColor: current,
                    onChanged: (v) => setDialogState(() => saturation = v),
                  ),
                  _HsvSlider(
                    label: '亮度',
                    gradientColors: [
                      HSVColor.fromAHSV(
                        1,
                        hue,
                        saturation,
                        minBrightness,
                      ).toColor(),
                      HSVColor.fromAHSV(
                        1,
                        hue,
                        saturation,
                        maxBrightness,
                      ).toColor(),
                    ],
                    value: brightness,
                    min: minBrightness,
                    max: maxBrightness,
                    thumbColor: current,
                    onChanged: (v) => setDialogState(() => brightness = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '#${current.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: TextStyle(
                      color: c.mute,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(current),
                child: const Text('確定'),
              ),
            ],
          );
        },
      );
    },
  );
  return result;
}

class _HsvSlider extends StatelessWidget {
  final String label;
  final List<Color> gradientColors;
  final double value;
  final double min;
  final double max;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  const _HsvSlider({
    required this.label,
    required this.gradientColors,
    required this.value,
    this.min = 0,
    required this.max,
    required this.thumbColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final display = max <= 1 ? (value * 100).round() : value.round();
    final suffix = max <= 1 ? '%' : '°';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: c.text, fontSize: 13)),
            const Spacer(),
            Text(
              '$display$suffix',
              style: TextStyle(color: c.mute, fontSize: 12),
            ),
          ],
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(colors: gradientColors),
              ),
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 8,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: thumbColor,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
