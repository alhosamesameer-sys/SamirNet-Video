import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _themeKey = 'theme_mode';
  static const _youtubeKey = 'youtube_data_api_key';

  static Future<String> loadYouTubeApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_youtubeKey) ?? '';
  }

  static Future<void> saveYouTubeApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_youtubeKey, key.trim());
  }

  static Future<ThemeMode> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> saveTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_themeKey, value);
  }
}
