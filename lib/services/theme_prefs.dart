import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accent presets offered for the light theme — darker shades (lightness
/// 0.4–0.6) that keep contrast against light backgrounds.
const lightAccentPresets = <Color>[
  Color(0xFF2E9E9E),
  Color(0xFF6BAE5E),
  Color(0xFFC77B4A),
  Color(0xFF8B6FC0),
];

/// Accent presets offered for the dark theme — brighter shades (lightness
/// 0.5–0.9) that stay visible against dark backgrounds.
const darkAccentPresets = <Color>[
  Color(0xFF4FC3C3),
  Color(0xFF9CCC9C),
  Color(0xFFE8B08A),
  Color(0xFFB39DDB),
];

/// The user-chosen theme colours, persisted per brightness so light and
/// dark themes can carry their own accent and background. `null` means
/// "use the theme default".
class ThemeCustomization {
  final Color? lightAccent;
  final Color? darkAccent;
  final Color? lightBackground;
  final Color? darkBackground;

  const ThemeCustomization({
    this.lightAccent,
    this.darkAccent,
    this.lightBackground,
    this.darkBackground,
  });

  static const _unset = Object();

  /// `null` here is meaningful — it means "clear this colour back to the
  /// theme default" — so omitted parameters keep the current value instead
  /// of using the null-coalescing trick (which would make clearing
  /// impossible).
  ThemeCustomization copyWith({
    Object? lightAccent = _unset,
    Object? darkAccent = _unset,
    Object? lightBackground = _unset,
    Object? darkBackground = _unset,
  }) => ThemeCustomization(
    lightAccent: lightAccent == _unset
        ? this.lightAccent
        : lightAccent as Color?,
    darkAccent: darkAccent == _unset ? this.darkAccent : darkAccent as Color?,
    lightBackground: lightBackground == _unset
        ? this.lightBackground
        : lightBackground as Color?,
    darkBackground: darkBackground == _unset
        ? this.darkBackground
        : darkBackground as Color?,
  );

  Color? accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAccent : lightAccent;

  Color? backgroundFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkBackground : lightBackground;
}

class ThemePrefs {
  static const _lightAccentKey = 'theme_accent_light';
  static const _darkAccentKey = 'theme_accent_dark';
  static const _lightBgKey = 'theme_bg_light';
  static const _darkBgKey = 'theme_bg_dark';

  static Future<ThemeCustomization> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ThemeCustomization(
      lightAccent: _readColor(prefs, _lightAccentKey),
      darkAccent: _readColor(prefs, _darkAccentKey),
      lightBackground: _readColor(prefs, _lightBgKey),
      darkBackground: _readColor(prefs, _darkBgKey),
    );
  }

  static Future<void> save(ThemeCustomization custom) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeColor(prefs, _lightAccentKey, custom.lightAccent);
    await _writeColor(prefs, _darkAccentKey, custom.darkAccent);
    await _writeColor(prefs, _lightBgKey, custom.lightBackground);
    await _writeColor(prefs, _darkBgKey, custom.darkBackground);
  }

  static Color? _readColor(SharedPreferences prefs, String key) {
    final value = prefs.getInt(key);
    return value != null ? Color(value) : null;
  }

  static Future<void> _writeColor(
    SharedPreferences prefs,
    String key,
    Color? color,
  ) async {
    if (color == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, color.toARGB32());
    }
  }
}
