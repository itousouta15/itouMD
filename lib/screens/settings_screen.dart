import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/hackmd_account.dart';
import '../services/hackmd_api.dart';
import '../services/note_cache.dart';
import '../services/reader_prefs.dart';
import '../services/recent_docs.dart';
import '../services/sync_prefs.dart';
import '../services/ui_prefs.dart';
import '../theme.dart';
import '../widgets/loader_ring.dart';
import 'hackmd_account_screen.dart';
import 'sync_history_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final UiScale uiScale;
  final ValueChanged<UiScale> onUiScaleChanged;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
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
    if (!mounted) return;
    setState(() {
      _readerPrefs = reader;
      _autoRefresh = autoRefresh;
      _conflictResolution = conflict;
    });
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
    double hue = HSVColor.fromColor(_readerPrefs.customColor).hue;
    double saturation = HSVColor.fromColor(_readerPrefs.customColor).saturation;
    double brightness = HSVColor.fromColor(_readerPrefs.customColor).value;

    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final c = ItouColorsExt.of(ctx);
            final current = HSVColor.fromAHSV(
              1,
              hue,
              saturation,
              brightness,
            ).toColor();
            return AlertDialog(
              title: const Text('自訂顏色'),
              content: SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: current,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.border2, width: 2),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _HsvSlider(
                      label: '色相',
                      gradientColors: const [
                        Colors.red,
                        Colors.yellow,
                        Colors.green,
                        Colors.cyan,
                        Colors.blue,
                        Color(0xFFFF00FF),
                        Colors.red,
                      ],
                      value: hue,
                      max: 360,
                      thumbColor: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                      onChanged: (v) => setDialogState(() => hue = v),
                    ),
                    _HsvSlider(
                      label: '飽和度',
                      gradientColors: [
                        HSVColor.fromAHSV(1, hue, 0, brightness).toColor(),
                        HSVColor.fromAHSV(1, hue, 1, brightness).toColor(),
                      ],
                      value: saturation,
                      max: 1,
                      thumbColor: current,
                      onChanged: (v) => setDialogState(() => saturation = v),
                    ),
                    _HsvSlider(
                      label: '亮度',
                      gradientColors: [
                        Colors.black,
                        HSVColor.fromAHSV(1, hue, saturation, 1).toColor(),
                      ],
                      value: brightness,
                      max: 1,
                      thumbColor: current,
                      onChanged: (v) => setDialogState(() => brightness = v),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '#${current.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                      style: TextStyle(
                        color: c.mute,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(current),
                  child: const Text('確定'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || result == null) return;
    final next = _readerPrefs.copyWith(customColor: result);
    _updateReaderPrefs(next);
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
    final isDark = widget.themeMode == ThemeMode.dark;
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
              _SettingRow(
                icon: isDark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                label: '深色模式',
                trailing: Switch(
                  value: isDark,
                  onChanged: (_) => widget.onToggleTheme(),
                  activeThumbColor: c.blue,
                ),
                onTap: widget.onToggleTheme,
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
                          selected: widget.uiScale == s,
                          onTap: () => widget.onUiScaleChanged(s),
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
                    RadioGroup<ConflictResolution>(
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
                      'itouMD 1.1.0',
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ReaderFontFamily.values.map((f) {
              final selected = prefs.fontFamily == f;
              return SizedBox(
                width: 78,
                child: _ChoiceTile(
                  label: f.label,
                  selected: selected,
                  previewStyle: f.textStyle(),
                  onTap: () => onChanged(prefs.copyWith(fontFamily: f)),
                ),
              );
            }).toList(),
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
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: ReaderTextColor.values.map((tc) {
              final selected = prefs.textColor == tc;
              final swatch = tc == ReaderTextColor.custom
                  ? prefs.customColor
                  : tc.resolve(c, brightness);
              return GestureDetector(
                onTap: () {
                  if (tc == ReaderTextColor.custom) {
                    onCustomColorTap();
                  } else {
                    onChanged(prefs.copyWith(textColor: tc));
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? c.blue : c.border2,
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      child: tc == ReaderTextColor.custom
                          ? const Icon(Icons.add, size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tc.label,
                      style: TextStyle(
                        color: selected ? c.text : c.dim,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
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
  final TextStyle? previewStyle;

  const _ChoiceTile({
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

class _HsvSlider extends StatelessWidget {
  final String label;
  final List<Color> gradientColors;
  final double value;
  final double max;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  const _HsvSlider({
    required this.label,
    required this.gradientColors,
    required this.value,
    required this.max,
    required this.thumbColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final display = max <= 1 ? (value * 100).round() : value.round();
    final suffix = max <= 1 ? '%' : '°';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: c.text, fontSize: 13)),
            const Spacer(),
            Text(
              '$display$suffix',
              style: TextStyle(color: c.mute, fontSize: 12),
            ),
          ],
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(colors: gradientColors),
              ),
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 8,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: thumbColor,
              ),
              child: Slider(
                value: value,
                min: 0,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
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
