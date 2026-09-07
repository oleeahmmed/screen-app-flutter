import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'call_notification.dart';
import 'chat_notification.dart';
import 'notification_deep_link.dart';
import 'notification_launch_router.dart';
import 'notification_sound.dart';
import 'local_notification_service_mobile.dart';

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
    if (type == 'call_invite' || type == 'call_dismiss') {
      _handleDataPayload(message.data);
      return;
    }
    unawaited(_showFromRemoteMessage(message, playSound: true));
    _handleDataPayload(message.data);
  }

  void _onOpenedFromTray(RemoteMessage message) {
    _handleDataPayload(Map<String, dynamic>.from(message.data));
  }

  void _handleDataPayload(Map<String, dynamic> data) {
    final normalized = NotificationLaunchRouter.normalizeFcmData(data);
    final type = normalized['type']?.toString() ?? '';
    final notifType = normalized['notification_type']?.toString() ?? '';

    if (type == 'call_dismiss') {
      unawaited(_handleCallDismiss(normalized));
      return;
    }

    if (onOpenFromNotification != null) {
      onOpenFromNotification!(normalized);
      return;
    }
    NotificationLaunchRouter.queueData(normalized);
  }

  static Future<void> _showFromRemoteMessage(RemoteMessage message, {bool playSound = false}) async {
    final data = NotificationLaunchRouter.normalizeFcmData(
      Map<String, dynamic>.from(message.data),
    );
    if (data['title'] == null || '${data['title']}'.isEmpty) {
      data['title'] = message.notification?.title ?? 'Aims';
    }
    if ((data['message'] ?? data['body'] ?? '').toString().isEmpty) {
      final body = message.notification?.body ?? '';
      if (body.isNotEmpty) {
        data['message'] = body;
        data['body'] = body;
      }
    }

    final type = data['type']?.toString() ?? '';
    final notifType = data['notification_type']?.toString() ?? '';
    final isCall = type == 'call_invite';

    if (isCall) {
      final name = data['caller_name']?.toString() ??
          data['sender_name']?.toString() ??
          'Incoming call';
      final callType = data['call_type']?.toString() ?? 'audio';
      final callId = data['call_id']?.toString() ?? '';
      final callerId = int.tryParse('${data['caller_id'] ?? data['sender_id'] ?? ''}') ?? 0;
      await LocalNotificationService.showIncomingCall(
        title: callType == 'video' ? 'Incoming video call' : 'Incoming voice call',
        body: name,
        payload: CallNotification.encode(
          callId: callId,
          callerId: callerId,
          callType: callType == 'video' ? 'video' : 'audio',
          callerName: name,
        ),
        playSound: playSound,
        video: callType == 'video',
      );
      return;
    }

    final isChat = notifType == 'new_message' || notifType == 'new_group_message';
    // Display payload: client draws WhatsApp MessagingStyle. Skip only non-chat
    // FCM notification payloads (the OS already drew those).
    if (!isChat && message.notification != null) return;

    if (isChat) {
      if (data['title'] == null) data['title'] = message.notification?.title;
      if (data['message'] == null) {
        data['message'] = data['body'] ?? message.notification?.body;
      }
      final chat = ChatNotification.fromData(data);
      await LocalNotificationService.showChat(
        conversationKey: chat.isGroup
            ? 'g:${chat.groupId ?? chat.name.hashCode}'
            : 'u:${chat.peerId ?? chat.name.hashCode}',
        personName: chat.name,
        body: chat.body.isNotEmpty ? chat.body : (message.notification?.body ?? 'New message'),
        payload: ChatNotification.encode(
          name: chat.name,
          peerId: chat.peerId,
          groupId: chat.groupId,
          notificationType: notifType,
        ),
        isGroup: chat.isGroup,
        groupTitle: chat.isGroup ? chat.name : null,
        personKey: chat.peerId ?? chat.groupId,
      );
      return;
    }

    final title = data['title']?.toString() ?? message.notification?.title ?? 'Aims';
    final body = data['body']?.toString() ??
        data['message']?.toString() ??
        message.notification?.body ??
        '';

    await LocalNotificationService.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body.isNotEmpty ? body : 'Tap to open',
      payload: NotificationLaunchRouter.encodePayloadFromData(data),
    );
  }

  static Future<void> _handleCallDismiss(Map<String, dynamic> data) async {
    await LocalNotificationService.cancelIncomingCall();
    await NotificationSound.stopCallSounds();
    AppNavigationBridge.openIncomingCall?.call(data);
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
  final type = message.data['type']?.toString() ?? '';
  if (type == 'call_dismiss') {
    await PushService._handleCallDismiss(Map<String, dynamic>.from(message.data));
    return;
  }
  try {
    await PushService._showFromRemoteMessage(message, playSound: true);
  } catch (e) {
    if (kDebugMode) debugPrint('[PushService] background show failed: $e');
    final data = NotificationLaunchRouter.normalizeFcmData(
      Map<String, dynamic>.from(message.data),
    );
    final title = data['title']?.toString() ?? message.notification?.title ?? 'Aims';
    final body = (data['message'] ?? data['body'] ?? message.notification?.body ?? 'Tap to open')
        .toString();
    await LocalNotificationService.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: NotificationLaunchRouter.encodePayloadFromData(data),
    );
  }
}
