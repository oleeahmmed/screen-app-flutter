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

  /// 1:1 audio/video calls — same platforms as P2P (WebRTC).
  static bool get voiceVideoCall =>
      Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  /// Drag-and-drop file targets — skip on Linux (GTK drag + desktop_drop edge cases).
  static bool get fileDragDrop => Platform.isMacOS || Platform.isWindows;

  /// Kanban task drag between stages — all platforms.
  /// Mobile uses long-press drag so horizontal board scroll still works.
  static bool get kanbanTaskDragDrop =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS;

  /// Long-press before drag on touch devices (avoids accidental drags while scrolling).
  static bool get kanbanLongPressDrag => Platform.isAndroid || Platform.isIOS;

  /// Desktop-only screen monitoring.
  ///
  /// The `android` git branch also strips MediaProjection native code and
  /// FOREGROUND_SERVICE_MEDIA_PROJECTION so installs never request screen capture.
  static bool get screenshotMonitoring =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Full-screen WhatsApp-style chat — hide AIMS top bar + bottom nav.
  /// Back stays inside chat (list / thread), same as the Android app.
  static bool get immersiveChatChrome =>
      Platform.isAndroid || Platform.isIOS || Platform.isLinux || Platform.isWindows;
}
