import 'package:flutter/foundation.dart';

/// No-op local notifications (desktop / web).
class LocalNotificationService {
  LocalNotificationService._();

  static bool _initialized = false;
  static void Function(String? payload)? onTap;
  static void Function(String? actionId, String? payload, String? input)? onAction;

  static String? pendingActionId;
  static String? pendingPayload;
  static String? pendingInput;

  static const messageChannelId = 'aims_messages_v3';
  static const callChannelId = 'aims_calls_v3';

  static bool get supported => false;

  static Future<void> initialize() async {
    _initialized = true;
  }

  static ({String? actionId, String? payload, String? input})? takePending() => null;

  static Future<bool> requestPermissions() async => false;

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
  }) async {}

  static Future<void> showChat({
    required String conversationKey,
    required String personName,
    required String body,
    String? payload,
    bool isGroup = false,
    String? groupTitle,
    int? personKey,
  }) async {}

  static Future<void> showIncomingCall({
    required String title,
    required String body,
    String? payload,
    bool playSound = true,
    bool video = false,
  }) async {}

  static Future<void> showCall({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {}

  static Future<void> cancelIncomingCall() async {}

  static Future<void> cancel(int id) async {}

  static void clearChatThread(String conversationKey) {}
}
