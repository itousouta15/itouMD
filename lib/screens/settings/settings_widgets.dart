import 'package:flutter/material.dart';

import '../../theme.dart';

/// A surface grouping related setting rows — the standard section
/// container used throughout the settings screen.
class Panel extends StatelessWidget {
  final List<Widget> children;

  const Panel({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// A single tappable row inside a [Panel]: icon, label, and trailing widget.
class SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? labelColor;
  final Widget trailing;
  final VoidCallback onTap;

  const SettingRow({
    super.key,
    required this.icon,
    required this.label,
    this.labelColor,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: labelColor ?? c.dim),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: labelColor ?? c.text, fontSize: 14),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// A single choice in a small horizontal picker (e.g. theme mode).
class ChoiceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Material(
      color: selected ? c.blue.withValues(alpha: 0.12) : c.inset,
      borderRadius: BorderRadius.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? c.blue : c.border),
            borderRadius: BorderRadius.zero,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? c.blue : c.dim,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the "致謝" (acknowledgements) list: a small logo plus a line
/// of credit text.
class ThanksRow extends StatelessWidget {
  final String logo;
  final String text;
  final ItouColors c;

  const ThanksRow({
    super.key,
    required this.logo,
    required this.text,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: c.inset,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.zero,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: Image.asset(logo, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: c.dim, fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}
