import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

const _themePrefKey = 'itou_md_theme_mode';

void main() {
  runApp(const ItouMdApp());
}

class ItouMdApp extends StatefulWidget {
  const ItouMdApp({super.key});

  @override
  State<ItouMdApp> createState() => _ItouMdAppState();
}

class _ItouMdAppState extends State<ItouMdApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadThemePref();
  }

  Future<void> _loadThemePref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themePrefKey);
    if (saved == 'light') {
      setState(() => _themeMode = ThemeMode.light);
    }
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
      builder: (context, child) => AnimatedTheme(
        data: _themeMode == ThemeMode.dark
            ? ItouTheme.darkTheme
            : ItouTheme.lightTheme,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
        child: child!,
      ),
      home: HomeScreen(themeMode: _themeMode, onToggleTheme: _toggleTheme),
    );
  }
}
