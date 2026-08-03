import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/hackmd_account.dart';
import '../services/hackmd_api.dart';
import '../services/note_cache.dart';
import '../services/reader_prefs.dart';
import '../services/recent_docs.dart';
import '../services/sync_prefs.dart';
import '../services/theme_prefs.dart';
import '../services/ui_prefs.dart';
import '../services/update_checker.dart';
import '../theme.dart';
import '../widgets/color_swatch_row.dart';
import '../widgets/hsv_color_picker.dart';
import '../widgets/loader_ring.dart';
import '../widgets/reader_font_picker.dart';
import '../widgets/update_dialog.dart';
import 'hackmd_account_screen.dart';
import 'onboarding_screen.dart';
import 'sync_history_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeCustomization customization;
  final ValueChanged<ThemeCustomization> onCustomizationChanged;
  final UiScale uiScale;
  final ValueChanged<UiScale> onUiScaleChanged;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.customization,
    required this.onCustomizationChanged,
    required this.uiScale,
    required this.onUiScaleChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  HackmdUser? _user;
  ReaderPrefs _readerPrefs = const ReaderPrefs();
  bool _autoRefresh = true;
  ConflictResolution _conflictResolution = ConflictResolution.ask;
  String _appVersion = '';
  // Live mirrors of the app-level state. The settings screen is a pushed
  // route, so its `widget` is frozen at push time — if we read the
  // customization/theme/ui-scale straight off `widget`, tapping a swatch
  // would update the app but never re-highlight the choice here. Mirror
  // locally (like `_readerPrefs`) and forward to the callbacks.
  late ThemeCustomization _custom = widget.customization;
  late ThemeMode _themeMode = widget.themeMode;
  late UiScale _uiScale = widget.uiScale;

  void _setCustom(ThemeCustomization next) {
    setState(() => _custom = next);
    widget.onCustomizationChanged(next);
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  void _setUiScale(UiScale next) {
    setState(() => _uiScale = next);
    widget.onUiScaleChanged(next);
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    _loadAccount();
    final reader = await ReaderPrefs.load();
    final autoRefresh = await SyncPrefs.autoRefreshOnOpen;
    final conflict = await SyncPrefs.conflictResolution;
    String version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      // Package info unavailable on exotic platforms — fall back to blank.
    }
    if (!mounted) return;
    setState(() {
      _readerPrefs = reader;
      _autoRefresh = autoRefresh;
      _conflictResolution = conflict;
      _appVersion = version;
    });
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    final info = await UpdateChecker.checkForUpdate();
    if (!context.mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已是最新版本 (｡•ᴗ•｡)')));
      return;
    }
    await showUpdateAvailableDialog(context, info, currentVersion: _appVersion);
  }

  Future<void> _loadAccount() async {
    final token = await HackmdAccount.getToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) return;
    try {
      final user = await HackmdApi.getMe(token);
      if (mounted) setState(() => _user = user);
    } on HackmdApiException {
      // Token stored but invalid — show as disconnected.
    } catch (_) {
      // Offline — don't clear the cached user state.
    }
  }

  Future<void> _openAccount() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HackmdAccountScreen()));
    _loadAccount();
  }

  void _updateReaderPrefs(ReaderPrefs next) {
    setState(() => _readerPrefs = next);
    next.save();
  }

  Future<void> _showColorPicker() async {
    final result = await showHsvColorPicker(
      context,
      initial: _readerPrefs.customColor,
    );
    if (!mounted || result == null) return;
    final next = _readerPrefs.copyWith(customColor: result);
    _updateReaderPrefs(next);
  }

  Future<void> _pickAccent(Brightness brightness) async {
    final custom = _custom;
    final current =
        custom.accentFor(brightness) ??
        (brightness == Brightness.dark
            ? ItouColors.dark.blue
            : ItouColors.light.blue);
    // Keep accents within the brightness band that holds contrast on that
    // theme: light theme wants darker shades, dark theme brighter ones.
    final result = await showHsvColorPicker(
      context,
      initial: current,
      minBrightness: brightness == Brightness.dark ? 0.5 : 0.2,
      maxBrightness: brightness == Brightness.dark ? 0.9 : 0.6,
    );
    if (!mounted || result == null) return;
    _setCustom(
      brightness == Brightness.dark
          ? custom.copyWith(darkAccent: result)
          : custom.copyWith(lightAccent: result),
    );
  }

  Future<void> _pickBackground(Brightness brightness) async {
    final custom = _custom;
    final current =
        custom.backgroundFor(brightness) ??
        (brightness == Brightness.dark
            ? ItouColors.dark.bg
            : ItouColors.light.bg);
    // Light theme backgrounds must stay light, dark theme backgrounds dark.
    final result = await showHsvColorPicker(
      context,
      initial: current,
      minBrightness: brightness == Brightness.dark ? 0.0 : 0.45,
      maxBrightness: brightness == Brightness.dark ? 0.55 : 1.0,
    );
    if (!mounted || result == null) return;
    _setCustom(
      brightness == Brightness.dark
          ? custom.copyWith(darkBackground: result)
          : custom.copyWith(lightBackground: result),
    );
  }

  Future<void> _clearRecents() async {
    await RecentDocs.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除最近開啟紀錄 (｡•ᴗ•｡)')));
  }

  Future<void> _clearNoteCache() async {
    await NoteCache.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除離線快取 (｡•ᴗ•｡)')));
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const SectionLabel('外觀'),
          const SizedBox(height: 8),
          _Panel(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isDark
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined,
                          size: 20,
                          color: c.dim,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '主題',
                          style: TextStyle(color: c.text, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ThemeMode.values.map((mode) {
                        return _ChoiceTile(
                          label: _themeModeLabel(mode),
                          selected: _themeMode == mode,
                          onTap: () => _setThemeMode(mode),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '「跟隨系統」會自動跟著裝置的深淺色設定切換。',
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              _ThemeColorsSection(
                custom: _custom,
                onSelectAccent: (brightness, accent) => _setCustom(
                  brightness == Brightness.dark
                      ? _custom.copyWith(darkAccent: accent)
                      : _custom.copyWith(lightAccent: accent),
                ),
                onSelectBackground: (brightness, background) => _setCustom(
                  brightness == Brightness.dark
                      ? _custom.copyWith(darkBackground: background)
                      : _custom.copyWith(lightBackground: background),
                ),
                onPickCustom: (brightness, role) =>
                    role == _ThemeColorRole.accent
                    ? _pickAccent(brightness)
                    : _pickBackground(brightness),
                onReset: (brightness) => _setCustom(
                  brightness == Brightness.dark
                      ? _custom.copyWith(darkAccent: null, darkBackground: null)
                      : _custom.copyWith(
                          lightAccent: null,
                          lightBackground: null,
                        ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('介面字級', style: TextStyle(color: c.text, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      '調整 App 介面文字大小；閱讀內容的字級在「閱讀偏好」設定。',
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: UiScale.values.map((s) {
                        return _ChoiceTile(
                          label: s.label,
                          selected: _uiScale == s,
                          onTap: () => _setUiScale(s),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('閱讀偏好'),
          const SizedBox(height: 8),
          _Panel(
            children: [
              _ReaderPrefsSection(
                prefs: _readerPrefs,
                onChanged: _updateReaderPrefs,
                onCustomColorTap: _showColorPicker,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('HackMD 同步'),
          const SizedBox(height: 8),
          _Panel(
            children: [
              _SettingRow(
                icon: Icons.sync_outlined,
                label: '開啟時自動更新',
                trailing: Switch(
                  value: _autoRefresh,
                  onChanged: (v) {
                    setState(() => _autoRefresh = v);
                    SyncPrefs.setAutoRefreshOnOpen(v);
                  },
                  activeThumbColor: c.blue,
                ),
                onTap: () {
                  final next = !_autoRefresh;
                  setState(() => _autoRefresh = next);
                  SyncPrefs.setAutoRefreshOnOpen(next);
                },
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('衝突處理', style: TextStyle(color: c.text, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text(
                      '同步時偵測到雲端版本被改過，要怎麼處理？',
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    // A transparent Material between the panel's DecoratedBox
                    // and the tiles, so ListTile ink/ripples stay visible.
                    Material(
                      type: MaterialType.transparency,
                      child: RadioGroup<ConflictResolution>(
                        groupValue: _conflictResolution,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _conflictResolution = v);
                          SyncPrefs.setConflictResolution(v);
                        },
                        child: Column(
                          children: [
                            for (final option in ConflictResolution.values)
                              RadioListTile<ConflictResolution>(
                                title: Text(
                                  _conflictLabel(option),
                                  style: TextStyle(color: c.text, fontSize: 13),
                                ),
                                value: option,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                activeColor: c.blue,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              _SettingRow(
                icon: Icons.history,
                label: '同步紀錄',
                trailing: Icon(Icons.chevron_right, size: 18, color: c.mute),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SyncHistoryScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('HackMD 帳號'),
          const SizedBox(height: 8),
          _Panel(
            children: [
              _SettingRow(
                icon: _user != null
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                label: _user != null
                    ? _user!.name ?? _user!.email ?? '已連結'
                    : '尚未連結',
                labelColor: _user != null ? c.text : c.dim,
                trailing: Icon(Icons.chevron_right, size: 18, color: c.mute),
                onTap: _openAccount,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('資料管理'),
          const SizedBox(height: 8),
          _Panel(
            children: [
              _SettingRow(
                icon: Icons.delete_outline,
                label: '清除最近開啟紀錄',
                labelColor: const Color(0xFFE0777A),
                trailing: const SizedBox.shrink(),
                onTap: _clearRecents,
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              _SettingRow(
                icon: Icons.delete_sweep_outlined,
                label: '清除離線快取',
                labelColor: const Color(0xFFE0777A),
                trailing: const SizedBox.shrink(),
                onTap: _clearNoteCache,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('更多'),
          const SizedBox(height: 8),
          _Panel(
            children: [
              _SettingRow(
                icon: Icons.system_update_outlined,
                label: '檢查更新',
                trailing: Icon(Icons.chevron_right, size: 18, color: c.mute),
                onTap: () => _checkForUpdate(context),
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              _SettingRow(
                icon: Icons.touch_app_outlined,
                label: '重新查看介紹',
                trailing: Icon(Icons.chevron_right, size: 18, color: c.mute),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OnboardingScreen(
                      onDone: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('關於'),
          const SizedBox(height: 8),
          _Panel(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'itouMD $_appVersion',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse('https://github.com/itousouta15/itouMD'),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.code, size: 15, color: c.blue),
                          const SizedBox(width: 8),
                          Text(
                            'GitHub',
                            style: TextStyle(color: c.blue, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Made with ♥ by itouSouta',
                      style: TextStyle(color: c.dim, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Licensed under MIT',
                      style: TextStyle(color: c.mute, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, thickness: 1, color: c.border),
                    const SizedBox(height: 12),
                    Text(
                      '感謝',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ThanksRow(
                      logo: 'assets/logo/emfont_logo.jpg',
                      text: '感謝 emfont 提供開源字型資源',
                      c: c,
                    ),
                    const SizedBox(height: 10),
                    _ThanksRow(
                      logo: 'assets/logo/hackmd_logo.png',
                      text: '感謝 HackMD 的容器語法與協作設計',
                      c: c,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _conflictLabel(ConflictResolution option) => switch (option) {
  ConflictResolution.ask => '每次詢問',
  ConflictResolution.overwrite => '直接蓋過去',
  ConflictResolution.cancel => '取消同步',
};

String _themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => '淺色',
  ThemeMode.dark => '深色',
  ThemeMode.system => '跟隨系統',
};

/// Which colour a custom picker edits within a theme.
enum _ThemeColorRole { accent, background }

/// The theme colour section ("主題顏色"): one block per light/dark theme,
/// each with an accent row (default + per-theme presets + custom) and an
/// auto/custom background row, all using the shared big-circle swatch row.
class _ThemeColorsSection extends StatelessWidget {
  final ThemeCustomization custom;
  final void Function(Brightness brightness, Color? accent) onSelectAccent;
  final void Function(Brightness brightness, Color? background)
  onSelectBackground;
  final void Function(Brightness brightness, _ThemeColorRole role) onPickCustom;
  final void Function(Brightness brightness) onReset;

  const _ThemeColorsSection({
    required this.custom,
    required this.onSelectAccent,
    required this.onSelectBackground,
    required this.onPickCustom,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);

    Widget themeBlock({
      required String label,
      required Color? accent,
      required Color? background,
      required Brightness brightness,
    }) {
      final isDark = brightness == Brightness.dark;
      final presets = isDark ? darkAccentPresets : lightAccentPresets;
      final defaultAccent = isDark
          ? ItouColors.dark.blue
          : ItouColors.light.blue;
      final defaultBg = isDark ? ItouColors.dark.bg : ItouColors.light.bg;
      final presetIndex = accent == null ? -1 : presets.indexOf(accent);
      // Index 0 = 預設 (theme's built-in colour); -1 = custom selected.
      final accentIndex = accent == null
          ? 0
          : presetIndex >= 0
          ? presetIndex + 1
          : -1;
      // The "自動" circle previews the background that will actually apply:
      // an accent-derived tint once an accent is set, the theme default
      // otherwise.
      final autoBg = accent != null
          ? ItouColors.autoBackground(accent, brightness)
          : defaultBg;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => onReset(brightness),
                child: Text(
                  '重設',
                  style: TextStyle(color: c.mute, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('主色', style: TextStyle(color: c.dim, fontSize: 11)),
          const SizedBox(height: 6),
          ColorSwatchRow(
            swatches: [defaultAccent, ...presets],
            selectedIndex: accentIndex,
            customColor: accent,
            onSwatchTap: (i) =>
                onSelectAccent(brightness, i == 0 ? null : presets[i - 1]),
            onCustomTap: () => onPickCustom(brightness, _ThemeColorRole.accent),
          ),
          const SizedBox(height: 14),
          Text('背景', style: TextStyle(color: c.dim, fontSize: 11)),
          const SizedBox(height: 6),
          ColorSwatchRow(
            swatches: [autoBg],
            selectedIndex: background == null ? 0 : -1,
            customColor: background,
            onSwatchTap: (_) => onSelectBackground(brightness, null),
            onCustomTap: () =>
                onPickCustom(brightness, _ThemeColorRole.background),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('主題顏色', style: TextStyle(color: c.text, fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            '主色用於按鈕與連結等強調色；背景「自動」會跟隨主色衍生，'
            '淺色與深色主題可分別設定。',
            style: TextStyle(color: c.dim, fontSize: 12),
          ),
          const SizedBox(height: 14),
          themeBlock(
            label: '淺色主題',
            accent: custom.lightAccent,
            background: custom.lightBackground,
            brightness: Brightness.light,
          ),
          const SizedBox(height: 14),
          themeBlock(
            label: '深色主題',
            accent: custom.darkAccent,
            background: custom.darkBackground,
            brightness: Brightness.dark,
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final List<Widget> children;

  const _Panel({required this.children});

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? labelColor;
  final Widget trailing;
  final VoidCallback onTap;

  const _SettingRow({
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

class _ReaderPrefsSection extends StatelessWidget {
  final ReaderPrefs prefs;
  final ValueChanged<ReaderPrefs> onChanged;
  final VoidCallback onCustomColorTap;

  const _ReaderPrefsSection({
    required this.prefs,
    required this.onChanged,
    required this.onCustomColorTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '字體',
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ReaderFontPicker(
            selected: prefs.fontFamily,
            onChanged: (f) => onChanged(prefs.copyWith(fontFamily: f)),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.inset,
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('預覽', style: TextStyle(color: c.mute, fontSize: 11)),
                const SizedBox(height: 8),
                Text(
                  '中文閱讀體驗、The quick brown fox と日本語。',
                  style: prefs.fontFamily.textStyle().copyWith(
                    fontSize: prefs.fontSize,
                    color: prefs.textColor.resolve(
                      c,
                      brightness,
                      prefs.customColor,
                    ),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '## Heading  *italic*  **bold**  `code`',
                  style: prefs.fontFamily.textStyle().copyWith(
                    fontSize: prefs.fontSize - 2,
                    color: prefs.textColor
                        .resolve(c, brightness, prefs.customColor)
                        .withValues(alpha: 0.7),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '字級',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                prefs.fontSize.toStringAsFixed(0),
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
              value: prefs.fontSize,
              min: ReaderPrefs.minFontSize,
              max: ReaderPrefs.maxFontSize,
              divisions:
                  ((ReaderPrefs.maxFontSize - ReaderPrefs.minFontSize) / 0.5)
                      .round(),
              onChanged: (v) => onChanged(prefs.copyWith(fontSize: v)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '文字顏色',
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ReaderColorRow(
            selected: prefs.textColor,
            customColor: prefs.customColor,
            brightness: brightness,
            onSwatch: (tc) => onChanged(prefs.copyWith(textColor: tc)),
            onCustom: onCustomColorTap,
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
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
          style: TextStyle(
            color: selected ? c.text : c.dim,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ThanksRow extends StatelessWidget {
  final String logo;
  final String text;
  final ItouColors c;

  const _ThanksRow({required this.logo, required this.text, required this.c});

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
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
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
