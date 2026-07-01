import 'package:flutter/foundation.dart';

/// No-op local notifications (desktop / web).
class LocalNotificationService {
  LocalNotificationService._();

  static bool _initialized = false;
  static void Function(String? payload)? onTap;

  static bool get supported => false;

  static Future<void> initialize() async {
    _initialized = true;
  }

  static Future<bool> requestPermissions() async => false;

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {}
}
