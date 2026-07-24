import 'dart:io';

/// Feature flags for desktop vs mobile — avoids native plugins that crash on Linux.
abstract final class PlatformCapabilities {
  static bool get isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  static bool get nativeAudio => Platform.isAndroid || Platform.isIOS;

  /// WebRTC P2P is unreliable on Linux desktop (native SDK / GStreamer issues).
  static bool get peerToPeerFileTransfer =>
      Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  /// Drag-and-drop file targets — skip on Linux (GTK drag + desktop_drop edge cases).
  static bool get fileDragDrop => Platform.isMacOS || Platform.isWindows;

  /// Desktop-only screen monitoring.
  ///
  /// The `android` git branch also strips MediaProjection native code and
  /// FOREGROUND_SERVICE_MEDIA_PROJECTION so installs never request screen capture.
  static bool get screenshotMonitoring =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
