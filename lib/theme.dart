import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ItouColors extends ThemeExtension<ItouColors> {
  final Color bg;
  final Color panel;
  final Color panelHover;
  final Color inset;
  final Color border;
  final Color border2;
  final Color text;
  final Color dim;
  final Color mute;
  final Color blue;
  final Color purple;
  final Color shadow;

  const ItouColors({
    required this.bg,
    required this.panel,
    required this.panelHover,
    required this.inset,
    required this.border,
    required this.border2,
    required this.text,
    required this.dim,
    required this.mute,
    required this.blue,
    required this.purple,
    required this.shadow,
  });

  @override
  ItouColors copyWith() => this;

  @override
  ItouColors lerp(ThemeExtension<ItouColors>? other, double t) => this;

  static const dark = ItouColors(
    bg: Color(0xFF1B1E23),
    panel: Color(0xFF24262B),
    panelHover: Color(0xFF292C32),
    inset: Color(0xFF181B20),
    border: Color(0x12FFFFFF),
    border2: Color(0x24FFFFFF),
    text: Color(0xFFE8EBF2),
    dim: Color(0xFF9AA1AD),
    mute: Color(0xFF6A7280),
    blue: Color(0xFFB0BDF7),
    purple: Color(0xFFA1ADE0),
    shadow: Color(0x73000000),
  );

  static const light = ItouColors(
    bg: Color(0xFFBFC0C7),
    panel: Color(0xFFD5D6DD),
    panelHover: Color(0xFFCBCCD3),
    inset: Color(0xFFD2D5DB),
    border: Color(0x14060607),
    border2: Color(0x29141828),
    text: Color(0xFF22262D),
    dim: Color(0xFF494F59),
    mute: Color(0xFF6B7280),
    blue: Color(0xFF364A7C),
    purple: Color(0xFF5C7CBF),
    shadow: Color(0x293C465A),
  );
}

class ItouTheme {
  static TextTheme _textTheme(ItouColors c) {
    final base = GoogleFonts.notoSansTcTextTheme();
    return base
        .apply(bodyColor: c.text, displayColor: c.text)
        .copyWith(
          titleLarge: GoogleFonts.shipporiMincho(
            color: c.text,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: GoogleFonts.jetBrainsMono(
            color: c.mute,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        );
  }

  static ThemeData _build(ItouColors c, Brightness brightness) {
    final textTheme = _textTheme(c);
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.blue,
        onPrimary: c.bg,
        secondary: c.purple,
        onSecondary: c.bg,
        surface: c.panel,
        onSurface: c.text,
        error: const Color(0xFFE0777A),
        onError: c.bg,
      ),
      textTheme: textTheme,
      fontFamily: GoogleFonts.notoSansTc().fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        elevation: 0,
        titleTextStyle: GoogleFonts.jetBrainsMono(
          color: c.text,
          fontSize: 16,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.border, width: 1),
          borderRadius: BorderRadius.zero,
        ),
      ),
      dividerColor: c.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.inset,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.blue),
        ),
        hintStyle: TextStyle(color: c.mute),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.panel,
          foregroundColor: c.text,
          elevation: 0,
          side: BorderSide(color: c.border2),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          textStyle: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconTheme: IconThemeData(color: c.dim),
      splashFactory: NoSplash.splashFactory,
      highlightColor: c.panelHover,
      extensions: [c],
    );
  }

  static ThemeData get darkTheme => _build(ItouColors.dark, Brightness.dark);
  static ThemeData get lightTheme => _build(ItouColors.light, Brightness.light);
}

extension ItouColorsExt on ItouColors {
  static ItouColors of(BuildContext context) =>
      Theme.of(context).extension<ItouColors>()!;
}
