import 'package:flutter/material.dart';

import '../../services/reader_prefs.dart';
import '../../theme.dart';
import '../../widgets/color_swatch_row.dart';
import '../../widgets/hsv_color_picker.dart';
import '../../widgets/loader_ring.dart';
import '../../widgets/reader_font_picker.dart';

class ReaderSettingsSheet extends StatefulWidget {
  final ReaderPrefs prefs;
  final ValueChanged<ReaderPrefs> onChanged;

  const ReaderSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
  });

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderPrefs _prefs = widget.prefs;

  void _update(ReaderPrefs next) {
    setState(() => _prefs = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final brightness = Theme.of(context).brightness;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.panel,
          border: Border.all(color: c.border2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel('字體'),
              const SizedBox(height: 10),
              ReaderFontPicker(
                selected: _prefs.fontFamily,
                onChanged: (f) => _update(_prefs.copyWith(fontFamily: f)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  SectionLabel('字級'),
                  const Spacer(),
                  Text(
                    _prefs.fontSize.toStringAsFixed(0),
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
                  value: _prefs.fontSize,
                  min: ReaderPrefs.minFontSize,
                  max: ReaderPrefs.maxFontSize,
                  divisions:
                      ((ReaderPrefs.maxFontSize - ReaderPrefs.minFontSize) /
                              0.5)
                          .round(),
                  onChanged: (v) => _update(_prefs.copyWith(fontSize: v)),
                ),
              ),
              const SizedBox(height: 10),
              SectionLabel('文字顏色'),
              const SizedBox(height: 12),
              ReaderColorRow(
                selected: _prefs.textColor,
                customColor: _prefs.customColor,
                brightness: brightness,
                onSwatch: (tc) => _update(_prefs.copyWith(textColor: tc)),
                onCustom: _pickReaderColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the shared HSV picker for the reader's custom text colour.
  Future<void> _pickReaderColor() async {
    final result = await showHsvColorPicker(
      context,
      initial: _prefs.customColor,
    );
    if (!mounted || result == null) return;
    _update(
      _prefs.copyWith(textColor: ReaderTextColor.custom, customColor: result),
    );
  }
}
