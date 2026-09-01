import 'package:flutter/services.dart';

/// Native Android CallStyle (green Answer / red Decline) like WhatsApp.
class AimsStyleNotify {
  AimsStyleNotify._();

  static const _methods = MethodChannel('aims_style_notify');
  static const _events = EventChannel('aims_style_notify/events');

  static Stream<Map<String, dynamic>> events() {
    return _events.receiveBroadcastStream().map((event) {
      if (event is Map) return Map<String, dynamic>.from(event);
      return <String, dynamic>{};
    });
  }

  static Future<bool> showIncomingCall({
    required String name,
    required String payload,
    bool video = false,
    bool playSound = true,
  }) async {
    try {
      await _methods.invokeMethod<void>('showIncomingCall', {
        'name': name,
        'payload': payload,
        'video': video,
        'playSound': playSound,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cancelIncomingCall() async {
    try {
      await _methods.invokeMethod<void>('cancelIncomingCall');
    } catch (_) {}
  }
}
