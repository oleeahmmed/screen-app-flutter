// Android branch — screen capture is desktop-only; this stub keeps the API stable.

import 'api_service.dart';
import '../utils/platform_capabilities.dart';
import 'windows_app_capture.dart';

class ScreenshotService {
  static bool get isPlatformSupported => PlatformCapabilities.screenshotMonitoring;

  static String get platformLabel => 'Android';

  final ApiService apiService;

  ScreenshotService(this.apiService);

  void recordActivity() {}

  Future<void> startCapture() async {}

  Future<void> startAppFilterCapture(List<WindowsAppInfo> allowedApps) async {}

  Future<void> startAppFilterCaptureByExe(List<String> allowedExes) async {}

  Future<void> stopCapture() async {}

  bool get isRunning => false;
  bool get isAppFilterMode => false;
  bool get isUserActive => true;
  int get displayCount => 1;
}
