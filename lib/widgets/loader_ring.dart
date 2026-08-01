import 'package:flutter/material.dart';

import '../theme.dart';

class LoaderRing extends StatelessWidget {
  final double size;
  const LoaderRing({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(c.blue),
        backgroundColor: c.border2,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.labelSmall);
  }
}
