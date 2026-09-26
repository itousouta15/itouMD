import 'package:flutter/material.dart';

import '../services/theme_prefs.dart';
import '../services/ui_prefs.dart';
import '../theme.dart';
import 'cloud_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// The three destinations stay mounted so returning to a tab preserves its
/// scroll position and in-progress input. Document screens are pushed above
/// this shell, leaving the full screen available for reading and editing.
class AppShell extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeCustomization customization;
  final ValueChanged<ThemeCustomization> onCustomizationChanged;
  final UiScale uiScale;
  final ValueChanged<UiScale> onUiScaleChanged;

  const AppShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.customization,
    required this.onCustomizationChanged,
    required this.uiScale,
    required this.onUiScaleChanged,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;
  int _recentsRevision = 0;
  int _cloudRevision = 0;
  int _settingsRevision = 0;

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _selected,
        children: [
          TickerMode(
            enabled: _selected == 0,
            child: HomeScreen(reloadRecentsToken: _recentsRevision),
          ),
          TickerMode(
            enabled: _selected == 1,
            child: CloudScreen(
              onRecentsChanged: () => setState(() => _recentsRevision++),
              refreshToken: _cloudRevision,
            ),
          ),
          TickerMode(
            enabled: _selected == 2,
            child: SettingsScreen(
              embedded: true,
              refreshToken: _settingsRevision,
              onRecentsChanged: () => setState(() => _recentsRevision++),
              themeMode: widget.themeMode,
              onThemeModeChanged: widget.onThemeModeChanged,
              customization: widget.customization,
              onCustomizationChanged: widget.onCustomizationChanged,
              uiScale: widget.uiScale,
              onUiScaleChanged: widget.onUiScaleChanged,
            ),
          ),
        ],
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: NavigationBar(
            selectedIndex: _selected,
            onDestinationSelected: (index) => setState(() {
              _selected = index;
              if (index == 1) _cloudRevision++;
              if (index == 0) _recentsRevision++;
              if (index == 2) _settingsRevision++;
            }),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '首頁',
              ),
              NavigationDestination(
                icon: Icon(Icons.cloud_outlined),
                selectedIcon: Icon(Icons.cloud_rounded),
                label: '雲端',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: '設定',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
