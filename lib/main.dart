import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
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
  ThemeMode _themeMode = ThemeMode.dark;
  UiScale _uiScale = UiScale.standard;
  late bool _onboardingDone = widget.onboardingDone;

  @override
  void initState() {
    super.initState();
    _loadThemePref();
    _loadUiPref();
  }

  Future<void> _loadThemePref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themePrefKey);
    if (saved == 'light') {
      setState(() => _themeMode = ThemeMode.light);
    }
  }

  Future<void> _loadUiPref() async {
    final scale = await UiPrefs.load();
    if (mounted) setState(() => _uiScale = scale);
  }

  Future<void> _toggleTheme() async {
    final next = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    setState(() => _themeMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themePrefKey,
      next == ThemeMode.light ? 'light' : 'dark',
    );
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
      theme: ItouTheme.lightTheme,
      darkTheme: ItouTheme.darkTheme,
      // MaterialApp swaps theme/darkTheme instantly; re-theme the actual
      // content under an AnimatedTheme (using the same resolved ThemeData)
      // so every Theme.of(context)-based colour — including our ItouColors
      // extension — crossfades instead of snapping.
      builder: (context, child) => MediaQuery(
        // Scales the whole app's UI text (settings, lists, buttons...). The
        // reader content and the editor opt out per-widget in the viewer.
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_uiScale.scale)),
        child: AnimatedTheme(
          data: _themeMode == ThemeMode.dark
              ? ItouTheme.darkTheme
              : ItouTheme.lightTheme,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOut,
          child: child!,
        ),
      ),
      home: _onboardingDone
          ? HomeScreen(
              themeMode: _themeMode,
              onToggleTheme: _toggleTheme,
              uiScale: _uiScale,
              onUiScaleChanged: _setUiScale,
            )
          : OnboardingScreen(onDone: _finishOnboarding),
    );
  }
}
