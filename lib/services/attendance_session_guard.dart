import 'package:shared_preferences/shared_preferences.dart';

/// Distinguishes a live app process (tray/minimize) from a cold start (quit/reboot).
///
/// Clock-in is tied to the current process. After full exit or reboot the user must
/// clock in again even if the server still has an open attendance row.
abstract final class AttendanceSessionGuard {
  static const _warmLaunchKey = 'attendance_warm_launch_id_v1';

  /// Unique per process — resets on full app exit or OS reboot.
  static final String launchId =
      '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(Object())}';

  static Future<void> markWarm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_warmLaunchKey, launchId);
    } catch (_) {}
  }

  static Future<void> clearWarm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_warmLaunchKey);
    } catch (_) {}
  }

  static Future<bool> isWarmContinuation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_warmLaunchKey) == launchId;
    } catch (_) {
      return false;
    }
  }
}
