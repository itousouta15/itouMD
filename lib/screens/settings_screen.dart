import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/hackmd_account.dart';
import '../services/hackmd_api.dart';
import '../services/github_account.dart';
import '../services/github_api.dart';
import '../services/llm_client.dart';
import '../services/llm_prefs.dart';
import '../services/note_cache.dart';
import '../services/reader_prefs.dart';
import '../services/recent_docs.dart';
import '../services/sync_prefs.dart';
import '../services/theme_prefs.dart';
import '../services/ui_prefs.dart';
import '../services/update_checker.dart';
import '../theme.dart';
import '../widgets/hsv_color_picker.dart';
import '../widgets/loader_ring.dart';
import '../widgets/update_dialog.dart';
import 'hackmd_account_screen.dart';
import 'github_account_screen.dart';
import 'onboarding_screen.dart';
import 'settings/reader_prefs_section.dart';
import 'settings/settings_widgets.dart';
import 'settings/theme_colors_section.dart';
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
  String? _githubUser;
  ReaderPrefs _readerPrefs = const ReaderPrefs();
  bool _autoRefresh = true;
  ConflictResolution _conflictResolution = ConflictResolution.ask;
  String _appVersion = '';
  bool _llmUseBuiltin = true;
  String _llmBaseUrl = '';
  String _llmModel = '';
  final _llmBaseUrlController = TextEditingController();
  final _llmModelController = TextEditingController();
  final _llmKeyController = TextEditingController();
  bool _llmTesting = false;
  String? _llmTestResult;
  bool _llmTestOk = false;
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

  @override
  void dispose() {
    _llmBaseUrlController.dispose();
    _llmModelController.dispose();
    _llmKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadAccount();
    _loadGithubAccount();
    _loadLlmPrefs();
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

  Future<void> _loadGithubAccount() async {
    final token = await GithubAccount.getToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) return;
    try {
      final login = await GithubApi.getAuthenticatedUser(token);
      if (mounted) setState(() => _githubUser = login);
    } on GithubApiException {
      // Token stored but invalid — show as disconnected.
    } catch (_) {
      // Offline — don't clear the cached user state.
    }
  }

  Future<void> _openGithubAccount() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const GithubAccountScreen()));
    _loadGithubAccount();
  }

  Future<void> _loadLlmPrefs() async {
    final useBuiltin = await LlmPrefs.useBuiltin;
    final baseUrl = await LlmPrefs.baseUrl;
    final model = await LlmPrefs.model;
    final apiKey = await LlmPrefs.apiKey;
    if (!mounted) return;
    setState(() {
      _llmUseBuiltin = useBuiltin;
      _llmBaseUrl = baseUrl ?? '';
      _llmModel = model ?? '';
      _llmBaseUrlController.text = baseUrl ?? '';
      _llmModelController.text = model ?? '';
      _llmKeyController.text = apiKey ?? '';
    });
  }

  void _setLlmUseBuiltin(bool value) {
    setState(() => _llmUseBuiltin = value);
    LlmPrefs.setUseBuiltin(value);
    if (value) {
      // Back to the built-in defaults — clear the stale custom values.
      setState(() {
        _llmBaseUrl = LlmPrefs.builtinBaseUrl;
        _llmModel = LlmPrefs.builtinModel;
        _llmBaseUrlController.text = LlmPrefs.builtinBaseUrl;
        _llmModelController.text = LlmPrefs.builtinModel;
      });
    }
  }

  void _saveLlmBaseUrl(String value) {
    setState(() => _llmBaseUrl = value.trim());
    LlmPrefs.setBaseUrl(value);
  }

  void _saveLlmModel(String value) {
    setState(() => _llmModel = value.trim());
    LlmPrefs.setModel(value);
  }

  Future<void> _testLlm() async {
    final baseUrl = _llmBaseUrl.trim();
    final model = _llmModel.trim();
    final apiKey = _llmUseBuiltin ? null : _llmKeyController.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() {
        _llmTestOk = false;
        _llmTestResult = '請先填 Base URL 與 Model';
      });
      return;
    }
    if (!_llmUseBuiltin && (apiKey == null || apiKey.isEmpty)) {
      setState(() {
        _llmTestOk = false;
        _llmTestResult = '自訂模式需要 API Key';
      });
      return;
    }
    setState(() {
      _llmTesting = true;
      _llmTestResult = null;
    });
    try {
      final reply = await LlmClient.complete(
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        userPrompt: '請只回覆「OK」',
        temperature: 0,
      );
      if (mounted) {
        setState(() {
          _llmTestOk = true;
          _llmTestResult = '連線成功（回應：$reply）';
        });
        if (!_llmUseBuiltin && apiKey != null) {
          await LlmPrefs.setApiKey(apiKey);
        }
      }
    } on LlmException catch (e) {
      if (mounted) {
        setState(() {
          _llmTestOk = false;
          _llmTestResult = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _llmTestOk = false;
          _llmTestResult = '連線失敗，再試一次看看 (´;ω;`)';
        });
      }
    } finally {
      if (mounted) setState(() => _llmTesting = false);
    }
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
          Panel(
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
                        return ChoiceTile(
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
              ThemeColorsSection(
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
                    role == ThemeColorRole.accent
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
                        return ChoiceTile(
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
          Panel(
            children: [
              ReaderPrefsSection(
                prefs: _readerPrefs,
                onChanged: _updateReaderPrefs,
                onCustomColorTap: _showColorPicker,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('HackMD 同步'),
          const SizedBox(height: 8),
          Panel(
            children: [
              SettingRow(
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
              SettingRow(
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
          Panel(
            children: [
              SettingRow(
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
          const SectionLabel('GitHub 帳號'),
          const SizedBox(height: 8),
          Panel(
            children: [
              SettingRow(
                icon: _githubUser != null
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                label: _githubUser != null ? '已連結：$_githubUser' : '尚未連結',
                labelColor: _githubUser != null ? c.text : c.dim,
                trailing: Icon(Icons.chevron_right, size: 18, color: c.mute),
                onTap: _openGithubAccount,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('AI 助理'),
          const SizedBox(height: 8),
          Panel(
            children: [
              SettingRow(
                icon: Icons.auto_awesome_outlined,
                label: '使用內建免費額度',
                trailing: Switch(
                  value: _llmUseBuiltin,
                  onChanged: _setLlmUseBuiltin,
                  activeThumbColor: c.blue,
                ),
                onTap: () => _setLlmUseBuiltin(!_llmUseBuiltin),
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _llmUseBuiltin
                          ? '編輯模式使用內建 AI（DeepSeek 最便宜模型，每日配額有限）。'
                          : '用自己的 API Key 走 OpenAI 相容端點（不受配額限制）。',
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _llmBaseUrlController,
                      style: TextStyle(color: c.text, fontSize: 13),
                      enabled: !_llmUseBuiltin,
                      decoration: InputDecoration(
                        labelText: 'Base URL',
                        hintText: LlmPrefs.builtinBaseUrl,
                      ),
                      onChanged: (v) => setState(() => _llmBaseUrl = v.trim()),
                      onSubmitted: _saveLlmBaseUrl,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _llmModelController,
                      style: TextStyle(color: c.text, fontSize: 13),
                      enabled: !_llmUseBuiltin,
                      decoration: InputDecoration(
                        labelText: 'Model',
                        hintText: LlmPrefs.builtinModel,
                      ),
                      onChanged: (v) => setState(() => _llmModel = v.trim()),
                      onSubmitted: _saveLlmModel,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _llmKeyController,
                      obscureText: true,
                      style: TextStyle(color: c.text, fontSize: 13),
                      enabled: !_llmUseBuiltin,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _llmTesting ? null : _testLlm,
                            child: _llmTesting
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('測試連線'),
                          ),
                        ),
                      ],
                    ),
                    if (_llmTestResult != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _llmTestResult!,
                        style: TextStyle(
                          color: _llmTestOk ? c.blue : ItouColors.danger,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('資料管理'),
          const SizedBox(height: 8),
          Panel(
            children: [
              SettingRow(
                icon: Icons.delete_outline,
                label: '清除最近開啟紀錄',
                labelColor: ItouColors.danger,
                trailing: const SizedBox.shrink(),
                onTap: _clearRecents,
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              SettingRow(
                icon: Icons.delete_sweep_outlined,
                label: '清除離線快取',
                labelColor: ItouColors.danger,
                trailing: const SizedBox.shrink(),
                onTap: _clearNoteCache,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('更多'),
          const SizedBox(height: 8),
          Panel(
            children: [
              SettingRow(
                icon: Icons.system_update_outlined,
                label: '檢查更新',
                trailing: Icon(Icons.chevron_right, size: 18, color: c.mute),
                onTap: () => _checkForUpdate(context),
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              SettingRow(
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
          Panel(
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
                    ThanksRow(
                      logo: 'assets/logo/emfont_logo.jpg',
                      text: '感謝 emfont 提供開源字型資源',
                      c: c,
                    ),
                    const SizedBox(height: 10),
                    ThanksRow(
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
