import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'local_notification_service.dart';

/// Registers this phone with FCM so the backend can alert when Aims is closed.
class FcmPushService {
  static bool _ready = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> initialize() async {
    if (!supported || _ready) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      _ready = true;
    } catch (e, st) {
      debugPrint('[FCM] init failed: $e\n$st');
    }
  }

  static Future<void> register(ApiService api) async {
    if (!supported) return;
    await initialize();
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await api.registerPushDevice(token);
        debugPrint('[FCM] token registered');
      }
      FirebaseMessaging.instance.onTokenRefresh.listen(api.registerPushDevice);
    } catch (e) {
      debugPrint('[FCM] register failed: $e');
    }
  }

  static Future<void> unregister(ApiService api) async {
    if (!supported || !_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      await api.unregisterPushDevice(token: token);
    } catch (e) {
      debugPrint('[FCM] unregister failed: $e');
    }
  }
}

/// Runs when Android delivers a data-only FCM while the UI isolate is dead.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
  if (message.notification != null) return;
  await LocalNotificationService.initialize();
  await _showFromMessage(message);
}

void _onForegroundMessage(RemoteMessage message) {
  // Chat WebSocket already shows in-app banners while Aims is open.
  if (message.notification != null) return;
  unawaited(_showFromMessage(message));
}

Future<void> _showFromMessage(RemoteMessage message) async {
  final data = message.data;
  final type = data['type']?.toString() ?? '';
  final title = message.notification?.title ??
      (type == 'call_invite' ? 'Incoming call' : 'Aims');
  final body = message.notification?.body ??
      data['caller_name']?.toString() ??
      data['body']?.toString() ??
      'Tap to open';

  if (type == 'call_invite') {
    await LocalNotificationService.showCall(
      id: (data['call_id'] ?? title).hashCode & 0x7fffffff,
      title: title,
      body: body,
      payload: 'call:${data['call_id'] ?? ''}',
    );
    return;
  }

  await LocalNotificationService.show(
    id: (message.messageId ?? title).hashCode & 0x7fffffff,
    title: title,
    body: body,
    payload: 'alerts',
  );
}
