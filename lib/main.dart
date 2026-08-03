import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/custom_fonts.dart';
import 'services/theme_prefs.dart';
import 'services/ui_prefs.dart';
import 'theme.dart';

const _themePrefKey = 'itou_md_theme_mode';
const _onboardingDoneKey = 'itou_md_onboarding_done';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Crash reporting via Sentry. The DSN is injected at build/run time with
  // `--dart-define=SENTRY_DSN=...` and never lives in the repo; without it
  // (plain dev runs) the SDK is skipped entirely.
  const dsn = String.fromEnvironment('SENTRY_DSN');
  if (dsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) => options
        ..dsn = dsn
        ..tracesSampleRate = 1.0
        ..environment = const String.fromEnvironment('SENTRY_ENV'),
    );
  }

  // Re-register an imported reader font before the first frame, so a font
  // selected in a previous session renders correctly right away.
  await CustomFonts.init();

  // Resolve the first-launch flag before runApp so the correct root screen
  // is chosen up front — no flash of the home screen before the wizard.
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool(_onboardingDoneKey) ?? false;

  runApp(ItouMdApp(onboardingDone: onboardingDone));
}

class ItouMdApp extends StatefulWidget {
  final bool onboardingDone;

  const ItouMdApp({super.key, required this.onboardingDone});

  @override
  State<ItouMdApp> createState() => _ItouMdAppState();
}

class _ItouMdAppState extends State<ItouMdApp> {
  ThemeMode _themeMode = ThemeMode.system;
  ThemeCustomization _custom = const ThemeCustomization();
  UiScale _uiScale = UiScale.standard;
  late bool _onboardingDone = widget.onboardingDone;

  @override
  void initState() {
    super.initState();
    _loadThemePref();
    _loadCustomPref();
    _loadUiPref();
  }

  /// Backgrounds in "自動" mode follow the chosen accent: an accent-derived
  /// soft tint (see [ItouColors.autoBackground]), or the theme default when
  /// no accent is set. A custom background always wins.
  ItouColors get _lightColors {
    final custom = _custom;
    return ItouColors.light
        .withAccent(custom.lightAccent)
        .withBackground(
          custom.lightBackground ??
              (custom.lightAccent != null
                  ? ItouColors.autoBackground(
                      custom.lightAccent!,
                      Brightness.light,
                    )
                  : null),
        );
  }

  ItouColors get _darkColors {
    final custom = _custom;
    return ItouColors.dark
        .withAccent(custom.darkAccent)
        .withBackground(
          custom.darkBackground ??
              (custom.darkAccent != null
                  ? ItouColors.autoBackground(
                      custom.darkAccent!,
                      Brightness.dark,
                    )
                  : null),
        );
  }

  ThemeData get _lightTheme => ItouTheme.build(_lightColors, Brightness.light);
  ThemeData get _darkTheme => ItouTheme.build(_darkColors, Brightness.dark);

  Future<void> _loadThemePref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themePrefKey);
    final mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (mounted && mode != _themeMode) setState(() => _themeMode = mode);
  }

  Future<void> _loadCustomPref() async {
    final custom = await ThemePrefs.load();
    if (mounted) setState(() => _custom = custom);
  }

  Future<void> _loadUiPref() async {
    final scale = await UiPrefs.load();
    if (mounted) setState(() => _uiScale = scale);
  }

  void _setThemeMode(ThemeMode next) {
    setState(() => _themeMode = next);
    SharedPreferences.getInstance().then((prefs) {
      final value = switch (next) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      prefs.setString(_themePrefKey, value);
    });
  }

  void _setCustom(ThemeCustomization next) {
    setState(() => _custom = next);
    ThemePrefs.save(next);
  }

  void _setUiScale(UiScale next) {
    setState(() => _uiScale = next);
    UiPrefs.save(next);
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingDoneKey, true);
    if (!mounted) return;
    setState(() => _onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'itouMD',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      // MaterialApp swaps theme/darkTheme instantly; re-theme the actual
      // content under an AnimatedTheme (using the same resolved ThemeData)
      // so every Theme.of(context)-based colour — including our ItouColors
      // extension — crossfades instead of snapping.
      builder: (context, child) {
        // In "follow system" mode the effective brightness is the
        // platform's, not a stored choice.
        final effectiveDark =
            _themeMode == ThemeMode.dark ||
            (_themeMode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        return MediaQuery(
          // Scales the whole app's UI text (settings, lists, buttons...). The
          // reader content and the editor opt out per-widget in the viewer.
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(_uiScale.scale)),
          child: AnimatedTheme(
            data: effectiveDark ? _darkTheme : _lightTheme,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOut,
            child: child!,
          ),
        );
      },
      home: _onboardingDone
          ? HomeScreen(
              themeMode: _themeMode,
              onThemeModeChanged: _setThemeMode,
              customization: _custom,
              onCustomizationChanged: _setCustom,
              uiScale: _uiScale,
              onUiScaleChanged: _setUiScale,
            )
          : OnboardingScreen(onDone: _finishOnboarding),
    );
  }
}
