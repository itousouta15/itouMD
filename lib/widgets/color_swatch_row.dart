import 'package:flutter/material.dart';

import '../services/reader_prefs.dart';
import '../theme.dart';

/// A horizontally scrollable row of large circular colour buttons with a
/// trailing "+" custom button — the shared pattern for every colour choice
/// in settings so they all look and behave the same. [selectedIndex] is the
/// index of the selected swatch, or -1 when the custom colour is selected.
class ColorSwatchRow extends StatelessWidget {
  final List<Color> swatches;
  final int selectedIndex;
  final Color? customColor;
  final ValueChanged<int> onSwatchTap;
  final VoidCallback onCustomTap;

  const ColorSwatchRow({
    super.key,
    required this.swatches,
    required this.selectedIndex,
    required this.onSwatchTap,
    required this.onCustomTap,
    this.customColor,
  });

  static const double swatchSize = 40;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < swatches.length; i++) ...[
            _CircleButton(
              color: swatches[i],
              selected: selectedIndex == i,
              onTap: () => onSwatchTap(i),
            ),
            const SizedBox(width: 10),
          ],
          _CircleButton(
            color: customColor,
            selected: selectedIndex == -1,
            showPlus: true,
            onTap: onCustomTap,
          ),
        ],
      ),
    );
  }
}

/// The reader text-colour picker: the preset colours as big swatches plus a
/// trailing "+" custom button (the shared [ColorSwatchRow] pattern).
class ReaderColorRow extends StatelessWidget {
  final ReaderTextColor selected;
  final Color customColor;
  final Brightness brightness;
  final ValueChanged<ReaderTextColor> onSwatch;
  final VoidCallback onCustom;

  const ReaderColorRow({
    super.key,
    required this.selected,
    required this.customColor,
    required this.brightness,
    required this.onSwatch,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final options = ReaderTextColor.values
        .where((tc) => tc != ReaderTextColor.custom)
        .toList();
    return ColorSwatchRow(
      swatches: options.map((tc) => tc.resolve(c, brightness)).toList(),
      selectedIndex: selected == ReaderTextColor.custom
          ? -1
          : options.indexOf(selected),
      customColor: selected == ReaderTextColor.custom ? customColor : null,
      onSwatchTap: (i) => onSwatch(options[i]),
      onCustomTap: onCustom,
    );
  }
}

class _CircleButton extends StatelessWidget {
  final Color? color;
  final bool selected;
  final bool showPlus;
  final VoidCallback onTap;

  const _CircleButton({
    required this.color,
    required this.selected,
    required this.onTap,
    this.showPlus = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: ColorSwatchRow.swatchSize,
        height: ColorSwatchRow.swatchSize,
        decoration: BoxDecoration(
          color: color ?? Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? c.text : c.border2,
            width: selected ? 3 : 1.5,
          ),
        ),
        child: !showPlus
            ? null
            : color == null
            ? Icon(Icons.add, size: 22, color: c.dim)
            // The "+" stays visible over any picked colour via a dark
            // translucent backing disc.
            : Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const Icon(Icons.add, size: 16, color: Colors.white),
                ],
              ),
      ),
    );
  }
}
