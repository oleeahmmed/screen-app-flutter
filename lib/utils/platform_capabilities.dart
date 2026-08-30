import 'dart:io';

/// Feature flags for desktop vs mobile — avoids native plugins that crash on Linux.
abstract final class PlatformCapabilities {
  static bool get isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// Asset chime via audioplayers — Windows needs this (SystemSound alone is often silent).
  /// Linux kept off: some GTK builds crash on native audio plugin init.
  static bool get nativeAudio =>
      Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isMacOS;

  /// WebRTC P2P is unreliable on Linux desktop (native SDK / GStreamer issues).
  static bool get peerToPeerFileTransfer =>
      Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  /// Drag-and-drop file targets — skip on Linux (GTK drag + desktop_drop edge cases).
  static bool get fileDragDrop => Platform.isMacOS || Platform.isWindows;

  /// Kanban task drag between stages — desktop only.
  /// On Android/iOS, long-press drag fights scrolling and causes misfires.
  static bool get kanbanTaskDragDrop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Desktop-only screen monitoring.
  ///
  /// The `android` git branch also strips MediaProjection native code and
  /// FOREGROUND_SERVICE_MEDIA_PROJECTION so installs never request screen capture.
  static bool get screenshotMonitoring =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Full-screen chat on phone — hide app top bar + bottom nav (back stays in chat UI).
  static bool get immersiveChatChrome =>
      Platform.isAndroid || Platform.isIOS;
}
