import 'dart:io';

import 'package:flutter/foundation.dart';

import 'utils/platform_capabilities.dart';

/// In-memory session flags (synced from API + SharedPreferences).
class AppSession {
  AppSession._();

  static const captureModeAllScreen = 'all_screen';
  static const captureModeAppWindows = 'app_windows';

  static bool screenshotMonitoringConsent = false;
  static int screenshotIntervalSeconds = 30;
  static bool onBreak = false;

  /// Server policy: full monitors vs selected app windows (Windows agent).
  static String screenshotCaptureMode = captureModeAllScreen;

  /// Local allowlist size for top-bar badge.
  static int selectedAppsCount = 0;

  /// Dashboard registers this so the top bar can open the app picker.
  static VoidCallback? openSelectApps;

  /// Bumps when capture mode / app count / picker callback changes.
  static final ValueNotifier<int> captureUiRevision = ValueNotifier(0);

  static void setConsent(bool v) {
    screenshotMonitoringConsent = v;
  }

  static void setOnBreak(bool v) {
    onBreak = v;
  }

  static void setCaptureMode(String? mode) {
    final next = (mode == captureModeAppWindows)
        ? captureModeAppWindows
        : captureModeAllScreen;
    if (screenshotCaptureMode == next) return;
    screenshotCaptureMode = next;
    notifyCaptureUi();
  }

  static void setSelectedAppsCount(int count) {
    if (selectedAppsCount == count) return;
    selectedAppsCount = count < 0 ? 0 : count;
    notifyCaptureUi();
  }

  static void setOpenSelectApps(VoidCallback? cb) {
    openSelectApps = cb;
    notifyCaptureUi();
  }

  static void notifyCaptureUi() {
    captureUiRevision.value++;
  }

  static bool get mayCaptureScreenshots =>
      PlatformCapabilities.screenshotMonitoring && screenshotMonitoringConsent && !onBreak;

  /// True when this device should capture selected app windows only.
  static bool get usesAppWindowCapture =>
      Platform.isWindows &&
      PlatformCapabilities.screenshotMonitoring &&
      screenshotCaptureMode == captureModeAppWindows;

  static bool get showSelectAppsInTopBar =>
      usesAppWindowCapture && openSelectApps != null;
}
