import 'package:flutter/material.dart';

import '../services/custom_fonts.dart';
import '../services/reader_prefs.dart';
import '../theme.dart';

/// The reader-font choice grid, shared by the settings screen and the
/// viewer's reader-settings sheet. Includes the built-in font families plus
/// a "import font" entry backed by [CustomFonts]: tapping it while no font
/// is imported opens the file picker, registers the font, and selects it.
class ReaderFontPicker extends StatefulWidget {
  final ReaderFontFamily selected;
  final ValueChanged<ReaderFontFamily> onChanged;

  const ReaderFontPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<ReaderFontPicker> createState() => _ReaderFontPickerState();
}

class _ReaderFontPickerState extends State<ReaderFontPicker> {
  bool _importing = false;

  Future<void> _importFont() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final family = await CustomFonts.import();
      if (!mounted) return;
      if (family != null) {
        widget.onChanged(ReaderFontFamily.custom);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('字體「$family」已匯入 (｡•ᴗ•｡)')));
      }
    } on FontImportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('匯入字體失敗，再試一次看看 (´;ω;`)')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _removeFont() async {
    await CustomFonts.remove();
    if (!mounted) return;
    widget.onChanged(ReaderFontFamily.sans);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已移除匯入字體 (｡•ᴗ•｡)')));
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final builtinFonts = ReaderFontFamily.values
        .where((f) => f != ReaderFontFamily.custom)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in builtinFonts)
              SizedBox(
                width: 78,
                child: _FontTile(
                  label: f.label,
                  selected: widget.selected == f,
                  previewStyle: f.textStyle(),
                  onTap: () => widget.onChanged(f),
                ),
              ),
            // The imported font joins the grid as a regular tile once it
            // exists; while none is imported, the entry point is a full-width
            // bar below instead of a lone orphan tile.
            if (CustomFonts.isLoaded)
              SizedBox(
                width: 78,
                child: _FontTile(
                  label: CustomFonts.currentFamily!,
                  selected: widget.selected == ReaderFontFamily.custom,
                  previewStyle: ReaderFontFamily.custom.textStyle(),
                  onTap: () => widget.onChanged(ReaderFontFamily.custom),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (CustomFonts.isLoaded)
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: _removeFont,
              child: Text(
                '移除匯入字體',
                style: TextStyle(color: c.mute, fontSize: 12),
              ),
            ),
          )
        else
          _ImportBar(importing: _importing, onTap: _importFont),
      ],
    );
  }
}

/// The full-width "＋ 匯入字體" bar shown while no custom font is imported.
class _ImportBar extends StatelessWidget {
  final bool importing;
  final VoidCallback onTap;

  const _ImportBar({required this.importing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return GestureDetector(
      onTap: importing ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.inset,
          border: Border.all(color: importing ? c.border : c.border2),
        ),
        child: importing
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.dim),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 18, color: c.dim),
                  const SizedBox(width: 6),
                  Text(
                    '匯入字體（TTF／OTF）',
                    style: TextStyle(color: c.dim, fontSize: 13),
                  ),
                ],
              ),
      ),
    );
  }
}

class _FontTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final TextStyle? previewStyle;

  const _FontTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.previewStyle,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final base = previewStyle ?? const TextStyle();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.panelHover : c.inset,
          border: Border.all(color: selected ? c.blue : c.border),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: base.copyWith(
            color: selected ? c.text : c.dim,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
