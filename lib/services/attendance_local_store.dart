import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_timer_state.dart';

/// Per-user local work/break timer — survives app restart (like login prefs).
class AttendanceLocalStore {
  static String _key(String username) =>
      'attendance_local_v2_${username.trim().toLowerCase()}';

  static Future<void> save({
    required String username,
    required AttendanceTimerState timer,
    required bool uiOnBreak,
    required bool uiClockedIn,
    String? workingDate,
    DateTime? breakStartTime,
  }) async {
    if (username.trim().isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final payload = timer.toJson()
        ..['ui_on_break'] = uiOnBreak
        ..['ui_clocked_in'] = uiClockedIn
        ..['working_date'] = workingDate
        ..['break_start_time'] = breakStartTime?.toIso8601String()
        ..['saved_at'] = DateTime.now().toIso8601String();
      await p.setString(_key(username), jsonEncode(payload));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> load(String username) async {
    if (username.trim().isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(username));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clear(String username) async {
    if (username.trim().isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key(username));
    } catch (_) {}
  }
}
