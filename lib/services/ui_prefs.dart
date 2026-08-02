import 'package:shared_preferences/shared_preferences.dart';

/// UI text scale for the app's chrome (menus, buttons, labels...). The
/// reader content and the editor deliberately ignore this — they follow the
/// reader font size preference instead.
enum UiScale { standard, large, xlarge }

extension UiScaleX on UiScale {
  String get label => switch (this) {
    UiScale.standard => '標準',
    UiScale.large => '大',
    UiScale.xlarge => '特大',
  };

  double get scale => switch (this) {
    UiScale.standard => 1.0,
    UiScale.large => 1.15,
    UiScale.xlarge => 1.3,
  };
}

class UiPrefs {
  static const _scaleKey = 'ui_text_scale';

  static Future<UiScale> load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_scaleKey) ?? 0;
    if (index < 0 || index >= UiScale.values.length) return UiScale.standard;
    return UiScale.values[index];
  }

  static Future<void> save(UiScale scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scaleKey, scale.index);
  }
}
