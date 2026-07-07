import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Last successful `/attendance/current/` snapshot for offline / loading fallback.
class AttendanceCache {
  static const _key = 'attendance_day_snapshot_v1';

  static Future<void> save(Map<String, dynamic> data) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(data));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}

/// Parse duration payloads from attendance API (`total_seconds` or hours/minutes).
int parseDurationSeconds(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is Map) {
    final secs = value['total_seconds'];
    if (secs is int) return secs;
    if (secs is num) return secs.round();
    if (secs != null) return int.tryParse('$secs') ?? 0;
    final hours = value['hours'];
    final minutes = value['minutes'];
    final h = hours is int ? hours : int.tryParse('$hours') ?? 0;
    final m = minutes is int ? minutes : int.tryParse('$minutes') ?? 0;
    return h * 3600 + m * 60;
  }
  return int.tryParse('$value') ?? 0;
}
