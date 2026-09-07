// app_filter_prefs.dart — persisted allowlist + capture mode for Windows agent

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_session.dart';
import 'windows_app_capture.dart';

abstract final class AppFilterPrefs {
  static const _allowedKey = 'app_filter_allowed_exes';
  static const _appsKey = 'app_filter_allowed_apps_v2';
  static const _activeKey = 'app_filter_capture_active'; // legacy
  static const _modeKey = 'screenshot_capture_mode';

  static Future<List<WindowsAppInfo>> loadAllowedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_appsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => WindowsAppInfo.fromJson(Map<String, dynamic>.from(e)))
              .where((a) => a.exe.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
    final exes = prefs.getStringList(_allowedKey) ?? const [];
    return exes.map((e) => WindowsAppInfo(name: e, exe: e, title: '')).toList();
  }

  static Future<List<String>> loadAllowedExes() async {
    final apps = await loadAllowedApps();
    return apps.map((a) => a.exe).toList();
  }

  static Future<void> saveAllowedApps(List<WindowsAppInfo> apps) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = apps
        .where((a) => a.exe.trim().isNotEmpty)
        .map((a) => a.toJson())
        .toList();
    await prefs.setString(_appsKey, jsonEncode(cleaned));
    await prefs.setStringList(
      _allowedKey,
      apps.map((a) => a.exe).toList(),
    );
    AppSession.setSelectedAppsCount(cleaned.length);
  }

  static Future<void> saveAllowedExes(List<String> exes) async {
    await saveAllowedApps(
      exes.map((e) => WindowsAppInfo(name: e, exe: e, title: '')).toList(),
    );
  }

  static Future<String> loadCaptureMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = (prefs.getString(_modeKey) ?? AppSession.captureModeAllScreen).trim();
    return mode == AppSession.captureModeAppWindows
        ? AppSession.captureModeAppWindows
        : AppSession.captureModeAllScreen;
  }

  static Future<void> saveCaptureMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    final next = mode == AppSession.captureModeAppWindows
        ? AppSession.captureModeAppWindows
        : AppSession.captureModeAllScreen;
    await prefs.setString(_modeKey, next);
    AppSession.setCaptureMode(next);
  }

  /// Sync server employee.screenshot_capture_mode into prefs + AppSession.
  static Future<void> applyServerCaptureMode(dynamic raw) async {
    final mode = (raw ?? AppSession.captureModeAllScreen).toString().trim();
    await saveCaptureMode(mode);
  }

  @Deprecated('Use screenshot_capture_mode from server instead')
  static Future<bool> loadActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_activeKey) ?? false;
  }

  @Deprecated('Use screenshot_capture_mode from server instead')
  static Future<void> setActive(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_activeKey, active);
  }
}
