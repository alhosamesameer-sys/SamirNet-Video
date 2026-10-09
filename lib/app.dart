import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/app_shell.dart';
import 'services/settings_service.dart';

class SamirNetApp extends StatefulWidget {
  const SamirNetApp({super.key});
  @override
  State<SamirNetApp> createState() => _SamirNetAppState();
}

class _SamirNetAppState extends State<SamirNetApp> {
  ThemeMode _mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    SettingsService.loadTheme().then((value) {
      if (mounted) setState(() => _mode = value);
    });
  }

  void changeTheme(ThemeMode mode) {
    setState(() => _mode = mode);
    SettingsService.saveTheme(mode);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SamirNet Videos',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _mode,
        home: AppShell(themeMode: _mode, onThemeChanged: changeTheme),
      );
}
