import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

enum ReaderFontFamily {
  sans,
  serif,
  mono,
  mplus,
  openHuninn,
  mantou,
  iansui,
  sourceHanSerif,
}

extension ReaderFontFamilyX on ReaderFontFamily {
  String get label => switch (this) {
    ReaderFontFamily.sans => '內文',
    ReaderFontFamily.serif => '襯線',
    ReaderFontFamily.mono => '等寬',
    ReaderFontFamily.mplus => 'M+',
    ReaderFontFamily.openHuninn => '粉圓',
    ReaderFontFamily.mantou => '饅頭',
    ReaderFontFamily.iansui => '芫荽',
    ReaderFontFamily.sourceHanSerif => '思源宋',
  };

  TextStyle textStyle() => switch (this) {
    ReaderFontFamily.sans => GoogleFonts.notoSansTc(),
    ReaderFontFamily.serif => GoogleFonts.shipporiMincho(),
    ReaderFontFamily.mono => GoogleFonts.jetBrainsMono(),
    ReaderFontFamily.mplus => GoogleFonts.mPlusRounded1c(),
    ReaderFontFamily.openHuninn => GoogleFonts.huninn(),
    ReaderFontFamily.mantou => const TextStyle(fontFamily: 'MantouSans'),
    ReaderFontFamily.iansui => GoogleFonts.iansui(),
    ReaderFontFamily.sourceHanSerif => GoogleFonts.notoSerifTc(),
  };
}

enum ReaderTextColor { theme, sepia, blue, contrast }

extension ReaderTextColorX on ReaderTextColor {
  String get label => switch (this) {
    ReaderTextColor.theme => '預設',
    ReaderTextColor.sepia => '暖色',
    ReaderTextColor.blue => '藍調',
    ReaderTextColor.contrast => '高對比',
  };

  Color resolve(ItouColors c, Brightness brightness) => switch (this) {
    ReaderTextColor.theme => c.text,
    ReaderTextColor.sepia => const Color(0xFFAD8B5C),
    ReaderTextColor.blue => c.blue,
    ReaderTextColor.contrast =>
      brightness == Brightness.dark ? Colors.white : Colors.black,
  };
}

class ReaderPrefs {
  static const _fontKey = 'reader_font_family';
  static const _sizeKey = 'reader_font_size';
  static const _colorKey = 'reader_text_color';

  static const double defaultFontSize = 15.5;
  static const double minFontSize = 13;
  static const double maxFontSize = 22;

  final ReaderFontFamily fontFamily;
  final double fontSize;
  final ReaderTextColor textColor;

  const ReaderPrefs({
    this.fontFamily = ReaderFontFamily.sans,
    this.fontSize = defaultFontSize,
    this.textColor = ReaderTextColor.theme,
  });

  ReaderPrefs copyWith({
    ReaderFontFamily? fontFamily,
    double? fontSize,
    ReaderTextColor? textColor,
  }) {
    return ReaderPrefs(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
    );
  }

  static Future<ReaderPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fontIndex = prefs.getInt(_fontKey);
    final colorIndex = prefs.getInt(_colorKey);
    return ReaderPrefs(
      fontFamily:
          (fontIndex != null && fontIndex < ReaderFontFamily.values.length)
          ? ReaderFontFamily.values[fontIndex]
          : ReaderFontFamily.sans,
      fontSize: prefs.getDouble(_sizeKey) ?? defaultFontSize,
      textColor:
          (colorIndex != null && colorIndex < ReaderTextColor.values.length)
          ? ReaderTextColor.values[colorIndex]
          : ReaderTextColor.theme,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fontKey, fontFamily.index);
    await prefs.setDouble(_sizeKey, fontSize);
    await prefs.setInt(_colorKey, textColor.index);
  }
}
