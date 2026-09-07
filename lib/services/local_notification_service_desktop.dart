import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

/// Windows / macOS / Linux toast notifications (Action Center / Notification Center).
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

  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static Future<void> initialize() async {
    if (_initialized || !supported) return;
    await localNotifier.setup(
      appName: 'Aims',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    _initialized = true;
  }

  static ({String? actionId, String? payload, String? input})? takePending() {
    if (pendingPayload == null) return null;
    final out = (
      actionId: pendingActionId,
      payload: pendingPayload,
      input: pendingInput,
    );
    pendingActionId = null;
    pendingPayload = null;
    pendingInput = null;
    return out;
  }

  static Future<bool> requestPermissions() async {
    await initialize();
    return true;
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
    final n = LocalNotification(
      title: title,
      body: body.isNotEmpty ? body : 'Tap to open Aims',
    );
    final p = payload;
    n.onClick = () {
      onTap?.call(p);
      pendingPayload = p;
    };
    await n.show();
  }

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
    final title = isGroup ? (groupTitle ?? personName) : personName;
    final n = LocalNotification(
      title: title,
      body: body.isNotEmpty ? body : 'New message',
    );
    final p = payload;
    n.onClick = () {
      onTap?.call(p);
      pendingPayload = p;
    };
    await n.show();
  }

  static Future<void> showIncomingCall({
    required String title,
    required String body,
    String? payload,
    bool playSound = true,
    bool video = false,
  }) async {
    await show(id: 8802, title: title, body: body, payload: payload, channelId: callChannelId);
  }

  static Future<void> showCall({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await show(id: id, title: title, body: body, payload: payload, channelId: callChannelId);
  }

  static Future<void> cancelIncomingCall() async {}

  static Future<void> cancel(int id) async {}

  static void clearChatThread(String conversationKey) {}
}
