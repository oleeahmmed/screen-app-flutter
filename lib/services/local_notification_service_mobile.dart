import 'dart:async';
import 'dart:io';

import 'package:aims_style_notify/aims_style_notify.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../utils/whatsapp_avatar.dart';
import 'call_notification.dart';
import 'chat_notification.dart';

/// System tray notifications on Android / iOS — WhatsApp MessagingStyle + CallStyle.
class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static void Function(String? payload)? onTap;
  static void Function(String? actionId, String? payload, String? input)? onAction;

  static String? pendingActionId;
  static String? pendingPayload;
  static String? pendingInput;

  static const messageChannelId = 'aims_messages_v3';
  static const callChannelId = 'aims_calls_v3';
  static const keepaliveChannelId = 'aims_keepalive';

  static const _me = Person(name: 'You', key: 'me');
  static final Map<String, List<Message>> _threads = {};

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
      pendingInput = resp?.input;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_origin', AppConfig.apiOrigin);
    } catch (_) {}

    _initialized = true;
  }

  static void _onResponse(NotificationResponse details) {
    if (onAction != null) {
      onAction!(details.actionId, details.payload, details.input);
      return;
    }
    if (onTap != null && (details.actionId == null || details.actionId!.isEmpty)) {
      onTap!(details.payload);
      return;
    }
    pendingActionId = details.actionId;
    pendingPayload = details.payload;
    pendingInput = details.input;
  }

  static ({String? actionId, String? payload, String? input})? takePending() {
    if (pendingActionId == null && pendingPayload == null && pendingInput == null) {
      return null;
    }
    final out = (actionId: pendingActionId, payload: pendingPayload, input: pendingInput);
    pendingActionId = null;
    pendingPayload = null;
    pendingInput = null;
    return out;
  }

  static Future<bool> requestPermissions() async {
    if (!supported) return false;
    await initialize();

    if (Platform.isAndroid) {
      await Permission.notification.request();
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
    String? personName,
    int? personKey,
    bool groupConversation = false,
    String? conversationTitle,
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

    final isChat = payload != null && ChatNotification.isChatPayload(payload);
    if (isChat || personName != null) {
      await showChat(
        conversationKey: personKey != null
            ? '${groupConversation ? 'g' : 'u'}:$personKey'
            : 't:$id',
        personName: personName ?? title,
        body: body,
        payload: payload,
        isGroup: groupConversation,
        groupTitle: conversationTitle,
        personKey: personKey,
      );
      return;
    }

    await _showGeneric(id: id, title: title, body: body, payload: payload);
  }

  /// WhatsApp conversation notification: stacked bubbles, Reply, Mark as read.
  static Future<void> showChat({
    required String conversationKey,
    required String personName,
    required String body,
    String? payload,
    bool isGroup = false,
    String? groupTitle,
    int? personKey,
  }) async {
    if (!supported) return;
    await initialize();

    final text = body.trim().isEmpty ? 'New message' : body.trim();
    final name = personName.trim().isEmpty ? 'Aims' : personName.trim();
    Uint8List? avatar;
    try {
      avatar = await WhatsAppAvatar.pngBytes(name, key: personKey ?? conversationKey.hashCode);
    } catch (_) {}

    final senderName = isGroup && text.contains(':') ? text.split(':').first.trim() : name;
    final sender = Person(
      name: senderName,
      key: conversationKey,
      icon: avatar == null ? null : ByteArrayAndroidIcon(avatar),
      important: true,
    );
    final bubbleText =
        isGroup && text.contains(':') ? text.split(':').skip(1).join(':').trim() : text;
    final msg = Message(bubbleText.isEmpty ? text : bubbleText, DateTime.now(), sender);
    final thread = _threads.putIfAbsent(conversationKey, () => <Message>[]);
    thread.add(msg);
    if (thread.length > 6) thread.removeRange(0, thread.length - 6);

    final id = conversationKey.hashCode & 0x7fffffff;
    final title = isGroup ? (groupTitle?.trim().isNotEmpty == true ? groupTitle!.trim() : name) : name;

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
      icon: 'ic_stat_message',
      color: const Color(0xFF25D366),
      largeIcon: avatar == null ? null : ByteArrayAndroidBitmap(avatar),
      styleInformation: MessagingStyleInformation(
        _me,
        conversationTitle: isGroup ? title : null,
        groupConversation: isGroup,
        messages: List<Message>.from(thread),
      ),
      groupKey: 'aims_chats',
      visibility: NotificationVisibility.private,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          ChatNotification.markReadAction,
          'Mark as read',
          titleColor: Color(0xFF8696A0),
          cancelNotification: true,
          showsUserInterface: false,
        ),
        const AndroidNotificationAction(
          ChatNotification.replyAction,
          'Reply',
          titleColor: Color(0xFF00A884),
          cancelNotification: false,
          showsUserInterface: false,
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(label: 'Reply', allowFreeFormInput: true),
          ],
        ),
      ],
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
      text,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  static Future<void> _showGeneric({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    Uint8List? avatar;
    try {
      avatar = await WhatsAppAvatar.pngBytes(title, key: id);
    } catch (_) {}
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
      icon: 'ic_stat_message',
      color: const Color(0xFF25D366),
      largeIcon: avatar == null ? null : ByteArrayAndroidBitmap(avatar),
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
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

  /// WhatsApp-style incoming call: native CallStyle on Android, fallback otherwise.
  static Future<void> showIncomingCall({
    required String title,
    required String body,
    String? payload,
    bool playSound = true,
    bool video = false,
  }) async {
    if (!supported) return;
    await initialize();

    if (Platform.isAndroid) {
      final ok = await AimsStyleNotify.showIncomingCall(
        name: body.trim().isEmpty ? title : body,
        payload: payload ?? '',
        video: video,
        playSound: playSound,
      );
      if (ok) return;
    }

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
      additionalFlags: playSound ? Int32List.fromList(<int>[4]) : null,
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
    if (Platform.isAndroid) {
      await AimsStyleNotify.cancelIncomingCall();
    }
    await _plugin.cancel(CallNotification.notificationId);
  }

  static Future<void> cancel(int id) async {
    if (!supported) return;
    await _plugin.cancel(id);
  }

  static void clearChatThread(String conversationKey) {
    _threads.remove(conversationKey);
    unawaited(cancel(conversationKey.hashCode & 0x7fffffff));
  }
}

@pragma('vm:entry-point')
void localNotificationBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  if (response.actionId == CallNotification.declineAction) {
    CallNotification.rejectViaHttp(response.payload);
  } else if (response.actionId == ChatNotification.replyAction) {
    ChatNotification.replyViaHttp(response.payload, response.input);
  } else if (response.actionId == ChatNotification.markReadAction) {
    ChatNotification.markReadViaHttp(response.payload);
  }
}
