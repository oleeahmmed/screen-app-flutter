/// In-memory session flags (synced from API + SharedPreferences).
class AppSession {
  AppSession._();

  static bool screenshotMonitoringConsent = false;
  static int screenshotIntervalSeconds = 30;

  static void setConsent(bool v) {
    screenshotMonitoringConsent = v;
  }

  static bool get mayCaptureScreenshots =>
      screenshotMonitoringConsent;
}
