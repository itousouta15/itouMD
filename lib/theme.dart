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
  ItouColors copyWith({
    Color? bg,
    Color? panel,
    Color? panelHover,
    Color? inset,
    Color? border,
    Color? border2,
    Color? text,
    Color? dim,
    Color? mute,
    Color? blue,
    Color? purple,
    Color? shadow,
  }) {
    return ItouColors(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      panelHover: panelHover ?? this.panelHover,
      inset: inset ?? this.inset,
      border: border ?? this.border,
      border2: border2 ?? this.border2,
      text: text ?? this.text,
      dim: dim ?? this.dim,
      mute: mute ?? this.mute,
      blue: blue ?? this.blue,
      purple: purple ?? this.purple,
      shadow: shadow ?? this.shadow,
    );
  }

  /// A copy with the accent colour (`blue`) replaced by [blue]. The
  /// secondary accent (`purple`) is derived from the chosen accent — hue
  /// rotated and slightly desaturated so the two stay visually distinct —
  /// unless an explicit [purple] is given. `null` keeps the defaults.
  ItouColors withAccent(Color? blue, {Color? purple}) {
    if (blue == null) return purple == null ? this : copyWith(purple: purple);
    final hsl = HSLColor.fromColor(blue);
    return copyWith(
      blue: blue,
      purple:
          purple ??
          hsl
              .withHue((hsl.hue + 35) % 360)
              .withSaturation(
                (hsl.saturation * 0.45).clamp(0.0, 1.0).toDouble(),
              )
              .toColor(),
    );
  }

  /// A copy with the app background replaced by [bg] (`null` keeps the
  /// default). The surfaces that sit on top of it — panel, panelHover,
  /// inset — are derived from the chosen colour with small lightness
  /// offsets mirroring the built-in palettes' direction (dark theme: panels
  /// float lighter, insets sink darker; light theme: everything floats
  /// lighter). The text/border tokens follow the background's luminance so
  /// readability holds for any picked shade. The accent (`blue`/`purple`)
  /// is untouched, so this chains after [withAccent].
  ItouColors withBackground(Color? bg) {
    if (bg == null) return this;
    final isDarkish = bg.computeLuminance() < 0.5;
    // Whichever default palette matches the background's luminance supplies
    // the text/border tokens, so custom backgrounds can't break contrast.
    final base = isDarkish ? ItouColors.dark : ItouColors.light;
    final hsl = HSLColor.fromColor(bg);
    double shift(double delta) => (hsl.lightness + delta).clamp(0.0, 1.0);
    return ItouColors(
      bg: bg,
      panel: hsl.withLightness(shift(isDarkish ? 0.05 : 0.07)).toColor(),
      panelHover: hsl.withLightness(shift(isDarkish ? 0.08 : 0.03)).toColor(),
      inset: hsl.withLightness(shift(isDarkish ? -0.03 : 0.06)).toColor(),
      border: base.border,
      border2: base.border2,
      text: base.text,
      dim: base.dim,
      mute: base.mute,
      blue: blue,
      purple: purple,
      shadow: base.shadow,
    );
  }

  @override
  ItouColors lerp(ThemeExtension<ItouColors>? other, double t) {
    if (other is! ItouColors) return this;
    return ItouColors(
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelHover: Color.lerp(panelHover, other.panelHover, t)!,
      inset: Color.lerp(inset, other.inset, t)!,
      border: Color.lerp(border, other.border, t)!,
      border2: Color.lerp(border2, other.border2, t)!,
      text: Color.lerp(text, other.text, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      mute: Color.lerp(mute, other.mute, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }

  static const dark = ItouColors(
    bg: Color(0xFF1C1D20),
    panel: Color(0xFF26272B),
    panelHover: Color(0xFF303238),
    inset: Color(0xFF202126),
    border: Color(0xFF3B3D44),
    border2: Color(0xFF50525C),
    text: Color(0xFFECECEF),
    dim: Color(0xFFB3B4BA),
    mute: Color(0xFF92949C),
    blue: Color(0xFFAAB2C2),
    purple: Color(0xFFB4ACB9),
    shadow: Color(0x73000000),
  );

  static const light = ItouColors(
    bg: Color(0xFFF3F3F2),
    panel: Color(0xFFFAFAF9),
    panelHover: Color(0xFFEBECEE),
    inset: Color(0xFFF0F0EF),
    border: Color(0xFFE1E2E3),
    border2: Color(0xFFC8CBD0),
    text: Color(0xFF25272A),
    dim: Color(0xFF62666E),
    mute: Color(0xFF71757E),
    blue: Color(0xFF5A6780),
    purple: Color(0xFF746D7F),
    shadow: Color(0x18333435),
  );

  /// A background derived from [accent] — the accent's hue, desaturated to
  /// a soft tint and pinned to a fixed lightness — used by the "自動"
  /// background option so the app picks a background that harmonizes with
  /// the chosen accent (light theme: pale paper; dark theme: deep shade).
  /// A desaturated (grayish) accent yields a near-neutral background.
  static Color autoBackground(Color accent, Brightness brightness) {
    final hsl = HSLColor.fromColor(accent);
    final saturation = hsl.saturation.clamp(0.0, 0.08).toDouble();
    final lightness = brightness == Brightness.dark ? 0.13 : 0.94;
    return hsl.withSaturation(saturation).withLightness(lightness).toColor();
  }

  /// Fixed semantic status colors — shared across both light and dark theme
  /// (unlike the palette above, these don't shift with the chosen accent).
  static const success = Color(0xFF7FAE83);
  static const warning = Color(0xFFAD8B5C);
  static const danger = Color(0xFFE0777A);

  /// Formats [c] as a `#rrggbb` CSS color literal.
  static String hex6(Color c) {
    int ch(double v) => (v * 255.0).round().clamp(0, 255);
    String byte(double v) => ch(v).toRadixString(16).padLeft(2, '0');
    return '#${byte(c.r)}${byte(c.g)}${byte(c.b)}';
  }
}

class ItouTheme {
  static TextTheme _textTheme(ItouColors c) {
    final base = GoogleFonts.notoSansTcTextTheme();
    return base
        .apply(bodyColor: c.text, displayColor: c.text)
        .copyWith(
          headlineSmall: GoogleFonts.notoSansTc(
            color: c.text,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: GoogleFonts.notoSansTc(
            color: c.text,
            fontWeight: FontWeight.w700,
          ),
          labelSmall: GoogleFonts.jetBrainsMono(color: c.mute, fontSize: 12),
        );
  }

  static ThemeData _build(ItouColors c, Brightness brightness) {
    final textTheme = _textTheme(c);
    final onAccent = c.blue.computeLuminance() > 0.42
        ? const Color(0xFF1C1D20)
        : Colors.white;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.blue,
        onPrimary: onAccent,
        secondary: c.purple,
        onSecondary: c.text,
        surface: c.panel,
        onSurface: c.text,
        error: ItouColors.danger,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      fontFamily: GoogleFonts.notoSansTc().fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.notoSansTc(
          color: c.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.panel,
        indicatorColor: c.blue.withValues(alpha: 0.13),
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: c.text, fontWeight: FontWeight.w600),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.blue,
        unselectedLabelColor: c.dim,
        indicatorColor: c.blue,
        dividerColor: c.border,
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
          borderSide: BorderSide(color: c.blue, width: 1.5),
        ),
        hintStyle: TextStyle(color: c.mute),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.blue,
          foregroundColor: onAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          textStyle: GoogleFonts.notoSansTc(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.border2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      snackBarTheme: const SnackBarThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      iconTheme: IconThemeData(color: c.dim),
      highlightColor: c.panelHover,
      extensions: [c],
    );
  }

  static ThemeData build(ItouColors c, Brightness brightness) =>
      _build(c, brightness);
  static ThemeData get darkTheme => _build(ItouColors.dark, Brightness.dark);
  static ThemeData get lightTheme => _build(ItouColors.light, Brightness.light);
}

extension ItouColorsExt on ItouColors {
  static ItouColors of(BuildContext context) =>
      Theme.of(context).extension<ItouColors>()!;
}
