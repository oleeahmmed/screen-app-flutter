// app_filter_prefs.dart — persisted allowlist for app-window capture (Windows)

import 'package:shared_preferences/shared_preferences.dart';

abstract final class AppFilterPrefs {
  static const _allowedKey = 'app_filter_allowed_exes';
  static const _activeKey = 'app_filter_capture_active';

  static Future<List<String>> loadAllowedExes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_allowedKey) ?? const [];
  }

  static Future<void> saveAllowedExes(List<String> exes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_allowedKey, exes);
  }

  static Future<bool> loadActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_activeKey) ?? false;
  }

  static Future<void> setActive(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_activeKey, active);
  }
}
