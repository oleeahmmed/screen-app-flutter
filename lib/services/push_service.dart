import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'local_notification_service_mobile.dart';
import 'notification_sound.dart';

/// FCM push — WhatsApp-style alerts when app is minimized or killed.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  ApiService? _api;
  bool _initialized = false;
  String? _lastToken;

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() async {
    if (!supported || _initialized) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.android,
      );
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
      _initialized = true;

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedFromTray);

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleDataPayload(initial.data);

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (Platform.isAndroid) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _lastToken = t;
        unawaited(_registerToken(t));
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[PushService] init skipped: $e');
    }
  }

  Future<void> bindApi(ApiService api) async {
    _api = api;
    if (!_initialized) await initialize();
    await registerAfterLogin();
  }

  Future<void> registerAfterLogin() async {
    if (!supported || !_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        _lastToken = token;
        await _registerToken(token);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PushService] token: $e');
    }
  }

  Future<void> unregister() async {
    if (!supported) return;
    final token = _lastToken;
    if (token != null && _api != null) {
      await _api!.unregisterPushToken(token);
    }
    _lastToken = null;
  }

  Future<void> _registerToken(String token) async {
    final api = _api;
    if (api == null) return;
    await api.registerPushToken(token, platform: Platform.isIOS ? 'ios' : 'android');
  }

  void _onForegroundMessage(RemoteMessage message) {
    _showFromRemoteMessage(message, playSound: true);
    _handleDataPayload(message.data);
  }

  void _onOpenedFromTray(RemoteMessage message) {
    _handleDataPayload(message.data);
  }

  void _handleDataPayload(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    if (type == 'call_invite') {
      // CallService picks up via WS when app opens; tray tap opens app → main navigates to chat tab.
      AppNavigationBridge.openChatTab?.call();
    } else if (type == 'notification' || data['notification_type'] != null) {
      AppNavigationBridge.openNotifications?.call();
    }
  }

  static Future<void> _showFromRemoteMessage(RemoteMessage message, {bool playSound = false}) async {
    final n = message.notification;
    final data = message.data;
    final title = n?.title ?? data['title']?.toString() ?? 'AIMS';
    final body = n?.body ?? data['body']?.toString() ?? data['message']?.toString() ?? '';
    final type = data['type']?.toString() ?? '';
    final isCall = type == 'call_invite';

    if (playSound) await NotificationSound.playNotification();

    await LocalNotificationService.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body.isNotEmpty ? body : 'Tap to open',
      payload: isCall ? 'call' : 'alerts',
      channelId: isCall ? 'aims_calls_v1' : 'aims_alerts_v2',
    );
  }
}

/// Callbacks wired from main.dart (avoids circular imports).
abstract final class AppNavigationBridge {
  static void Function()? openChatTab;
  static void Function()? openNotifications;
}

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
  await LocalNotificationService.initialize();
  await PushService._showFromRemoteMessage(message, playSound: true);
}
