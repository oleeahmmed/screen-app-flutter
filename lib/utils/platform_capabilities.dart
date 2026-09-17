import 'package:flutter/foundation.dart';

/// Feature flags for desktop vs mobile — avoids native plugins that crash on Linux/web.
abstract final class PlatformCapabilities {
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get _isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isDesktop => _isLinux || _isWindows || _isMacOS;

  /// Asset chime via audioplayers — Windows needs this (SystemSound alone is often silent).
  /// Linux kept off: some GTK builds crash on native audio plugin init.
  static bool get nativeAudio => _isAndroid || _isIOS || _isWindows || _isMacOS;

  /// WebRTC P2P is unreliable on Linux desktop (native SDK / GStreamer issues).
  static bool get peerToPeerFileTransfer => _isAndroid || _isIOS || _isWindows;

  /// 1:1 audio/video calls — same platforms as P2P (WebRTC).
  static bool get voiceVideoCall => _isAndroid || _isIOS || _isWindows;

  /// Drag-and-drop file targets — skip on Linux (GTK drag + desktop_drop edge cases).
  static bool get fileDragDrop => _isMacOS || _isWindows;

  /// Kanban task drag between stages — all platforms.
  /// Mobile uses long-press drag so horizontal board scroll still works.
  static bool get kanbanTaskDragDrop =>
      _isAndroid || _isIOS || _isWindows || _isLinux || _isMacOS || kIsWeb;

  /// Long-press before drag on touch devices (avoids accidental drags while scrolling).
  static bool get kanbanLongPressDrag => _isAndroid || _isIOS;

  /// Desktop-only screen monitoring.
  ///
  /// The `android` git branch also strips MediaProjection native code and
  /// FOREGROUND_SERVICE_MEDIA_PROJECTION so installs never request screen capture.
  static bool get screenshotMonitoring => _isWindows || _isLinux || _isMacOS;

  /// Full-screen WhatsApp-style chat — hide AIMS top bar + bottom nav.
  /// Back stays inside chat (list / thread), same as the Android app.
  static bool get immersiveChatChrome =>
      _isAndroid || _isIOS || _isLinux || _isWindows;
}
