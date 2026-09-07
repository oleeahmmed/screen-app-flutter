import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'local_notification_service_mobile.dart';
import 'notification_launch_router.dart';
import 'push_alert_service.dart';

/// FCM push — WhatsApp-style alerts when app is minimized or killed.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  ApiService? _api;
  bool _initialized = false;
  String? _lastToken;

  /// Wired from [MainScreen] after login — opens the correct screen from FCM tap.
  static void Function(Map<String, dynamic> data)? onOpenFromNotification;

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
      if (initial != null) {
        _handleDataPayload(Map<String, dynamic>.from(initial.data));
      }

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
        debugPrint('[PushService] token registered (${token.length} chars)');
      } else {
        debugPrint('[PushService] no FCM token');
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
    final type = message.data['type']?.toString() ?? '';
    if (type == 'call_dismiss') {
      unawaited(PushAlertService.showFromData(message.data, playSound: false));
      return;
    }
    unawaited(PushAlertService.showFromData(message.data));
  }

  void _onOpenedFromTray(RemoteMessage message) {
    _handleDataPayload(Map<String, dynamic>.from(message.data));
  }

  void _handleDataPayload(Map<String, dynamic> data) {
    final normalized = NotificationLaunchRouter.normalizeFcmData(data);
    if (onOpenFromNotification != null) {
      onOpenFromNotification!(normalized);
      return;
    }
    NotificationLaunchRouter.queueData(normalized);
  }
}

/// Callbacks wired from main.dart (avoids circular imports).
abstract final class AppNavigationBridge {
  static void Function()? openChatTab;
  static void Function(int? userId, int? groupId)? openChatPeer;
  static void Function()? openNotifications;
  static void Function(Map<String, dynamic> data)? openDeepLink;
  static void Function(Map<String, dynamic> data)? openIncomingCall;
}

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
  await LocalNotificationService.initialize();
  try {
    await PushAlertService.showFromData(Map<String, dynamic>.from(message.data));
  } catch (e) {
    if (kDebugMode) debugPrint('[PushService] background show failed: $e');
  }
}
