import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'call_notification.dart';

/// System tray notifications on Android / iOS.
class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static void Function(String? payload)? onTap;
  static void Function(String? actionId, String? payload)? onAction;

  static String? pendingActionId;
  static String? pendingPayload;

  static const messageChannelId = 'aims_messages_v3';
  static const callChannelId = 'aims_calls_v3';
  static const keepaliveChannelId = 'aims_keepalive';

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> initialize() async {
    if (_initialized || !supported) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: localNotificationBackground,
    );

    if (Platform.isAndroid) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          messageChannelId,
          'Messages',
          description: 'Chat and app alerts',
          importance: Importance.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('msg_pop'),
          enableVibration: true,
          vibrationPattern: Int64List.fromList(<int>[0, 40, 80, 50]),
          showBadge: true,
          audioAttributesUsage: AudioAttributesUsage.notification,
        ),
      );
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          callChannelId,
          'Incoming calls',
          description: 'Voice and video calls',
          importance: Importance.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('call_ringtone'),
          enableVibration: true,
          vibrationPattern: Int64List.fromList(<int>[0, 1000, 1000, 1000, 1000]),
          showBadge: true,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        ),
      );
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          keepaliveChannelId,
          'Aims connection',
          description: 'Keeps Aims connected for calls and alerts',
          importance: Importance.low,
        ),
      );
    }

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final resp = launch!.notificationResponse;
      pendingActionId = resp?.actionId;
      pendingPayload = resp?.payload;
    }

    _initialized = true;
  }

  static void _onResponse(NotificationResponse details) {
    if (onAction != null) {
      onAction!(details.actionId, details.payload);
      return;
    }
    if (onTap != null) {
      onTap!(details.payload);
      return;
    }
    pendingActionId = details.actionId;
    pendingPayload = details.payload;
  }

  static ({String? actionId, String? payload})? takePending() {
    if (pendingActionId == null && pendingPayload == null) return null;
    final out = (actionId: pendingActionId, payload: pendingPayload);
    pendingActionId = null;
    pendingPayload = null;
    return out;
  }

  static Future<bool> requestPermissions() async {
    if (!supported) return false;
    await initialize();

    if (Platform.isAndroid) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestFullScreenIntentPermission();
      return await androidImpl?.requestNotificationsPermission() ?? false;
    }

    if (Platform.isIOS) {
      final iosImpl =
          _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await iosImpl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return false;
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = messageChannelId,
  }) async {
    if (!supported) return;
    await initialize();

    final isCall = channelId == callChannelId || channelId == 'aims_calls_v1';
    if (isCall) {
      await showIncomingCall(
        title: title,
        body: body,
        payload: payload,
      );
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      messageChannelId,
      'Messages',
      channelDescription: 'Chat and app alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('msg_pop'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList(<int>[0, 40, 80, 50]),
      category: AndroidNotificationCategory.message,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF25D366),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'msg_pop.wav',
      interruptionLevel: InterruptionLevel.active,
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  /// WhatsApp-style incoming call: looping ringtone, Answer / Decline, lock-screen.
  static Future<void> showIncomingCall({
    required String title,
    required String body,
    String? payload,
    bool playSound = true,
    bool video = false,
  }) async {
    if (!supported) return;
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      callChannelId,
      'Incoming calls',
      channelDescription: 'Voice and video calls',
      importance: Importance.max,
      priority: Priority.max,
      playSound: playSound,
      sound: const RawResourceAndroidNotificationSound('call_ringtone'),
      enableVibration: playSound,
      vibrationPattern: Int64List.fromList(<int>[0, 1000, 1000, 1000, 1000]),
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      timeoutAfter: 45000,
      additionalFlags: playSound ? Int32List.fromList(<int>[4]) : null, // FLAG_INSISTENT
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF25D366),
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          CallNotification.declineAction,
          'Decline',
          titleColor: Color(0xFFE53935),
          cancelNotification: true,
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          CallNotification.acceptAction,
          video ? 'Video' : 'Answer',
          titleColor: const Color(0xFF25D366),
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'call_ringtone.wav',
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'INCOMING_CALL',
    );

    await _plugin.show(
      CallNotification.notificationId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  static Future<void> showCall({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await showIncomingCall(title: title, body: body, payload: payload);
  }

  static Future<void> cancelIncomingCall() async {
    if (!supported) return;
    await _plugin.cancel(CallNotification.notificationId);
  }

  static Future<void> cancel(int id) async {
    if (!supported) return;
    await _plugin.cancel(id);
  }
}

@pragma('vm:entry-point')
void localNotificationBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  if (response.actionId == CallNotification.declineAction) {
    CallNotification.rejectViaHttp(response.payload);
  }
}
