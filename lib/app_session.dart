import 'utils/platform_capabilities.dart';

/// In-memory session flags (synced from API + SharedPreferences).
class AppSession {
  AppSession._();

  static bool screenshotMonitoringConsent = false;
  static int screenshotIntervalSeconds = 30;
  static bool onBreak = false;

  static void setConsent(bool v) {
    screenshotMonitoringConsent = v;
  }

  static void setOnBreak(bool v) {
    onBreak = v;
  }

  static bool get mayCaptureScreenshots =>
      PlatformCapabilities.screenshotMonitoring && screenshotMonitoringConsent && !onBreak;
}
