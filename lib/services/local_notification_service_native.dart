import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_notification_service_desktop.dart' as desktop;
import 'local_notification_service_mobile.dart' as mobile;

/// Routes local notifications to mobile (Android/iOS) or desktop (Win/Mac/Linux).
abstract final class LocalNotificationService {
  static bool get supported => !kIsWeb && (_isMobile || desktop.LocalNotificationService.supported);

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static void Function(String? payload)? get onTap =>
      _isMobile ? mobile.LocalNotificationService.onTap : desktop.LocalNotificationService.onTap;

  static set onTap(void Function(String? payload)? cb) {
    mobile.LocalNotificationService.onTap = cb;
    desktop.LocalNotificationService.onTap = cb;
  }

  static void Function(String? actionId, String? payload, String? input)? get onAction =>
      _isMobile ? mobile.LocalNotificationService.onAction : desktop.LocalNotificationService.onAction;

  static set onAction(void Function(String? actionId, String? payload, String? input)? cb) {
    mobile.LocalNotificationService.onAction = cb;
    desktop.LocalNotificationService.onAction = cb;
  }

  static String? get pendingActionId =>
      _isMobile ? mobile.LocalNotificationService.pendingActionId : desktop.LocalNotificationService.pendingActionId;

  static set pendingActionId(String? v) {
    mobile.LocalNotificationService.pendingActionId = v;
    desktop.LocalNotificationService.pendingActionId = v;
  }

  static String? get pendingPayload =>
      _isMobile ? mobile.LocalNotificationService.pendingPayload : desktop.LocalNotificationService.pendingPayload;

  static set pendingPayload(String? v) {
    mobile.LocalNotificationService.pendingPayload = v;
    desktop.LocalNotificationService.pendingPayload = v;
  }

  static String? get pendingInput =>
      _isMobile ? mobile.LocalNotificationService.pendingInput : desktop.LocalNotificationService.pendingInput;

  static set pendingInput(String? v) {
    mobile.LocalNotificationService.pendingInput = v;
    desktop.LocalNotificationService.pendingInput = v;
  }

  static const messageChannelId = mobile.LocalNotificationService.messageChannelId;
  static const callChannelId = mobile.LocalNotificationService.callChannelId;

  static Future<void> initialize() async {
    if (_isMobile) {
      await mobile.LocalNotificationService.initialize();
    } else if (desktop.LocalNotificationService.supported) {
      await desktop.LocalNotificationService.initialize();
    }
  }

  static ({String? actionId, String? payload, String? input})? takePending() {
    if (_isMobile) return mobile.LocalNotificationService.takePending();
    return desktop.LocalNotificationService.takePending();
  }

  static Future<bool> requestPermissions() async {
    if (_isMobile) return mobile.LocalNotificationService.requestPermissions();
    return desktop.LocalNotificationService.requestPermissions();
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
    if (_isMobile) {
      await mobile.LocalNotificationService.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        channelId: channelId,
        personName: personName,
        personKey: personKey,
        groupConversation: groupConversation,
        conversationTitle: conversationTitle,
      );
    } else {
      await desktop.LocalNotificationService.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        channelId: channelId,
        personName: personName,
        personKey: personKey,
        groupConversation: groupConversation,
        conversationTitle: conversationTitle,
      );
    }
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
    if (_isMobile) {
      await mobile.LocalNotificationService.showChat(
        conversationKey: conversationKey,
        personName: personName,
        body: body,
        payload: payload,
        isGroup: isGroup,
        groupTitle: groupTitle,
        personKey: personKey,
      );
    } else {
      await desktop.LocalNotificationService.showChat(
        conversationKey: conversationKey,
        personName: personName,
        body: body,
        payload: payload,
        isGroup: isGroup,
        groupTitle: groupTitle,
        personKey: personKey,
      );
    }
  }

  static Future<void> showIncomingCall({
    required String title,
    required String body,
    String? payload,
    bool playSound = true,
    bool video = false,
  }) async {
    if (_isMobile) {
      await mobile.LocalNotificationService.showIncomingCall(
        title: title,
        body: body,
        payload: payload,
        playSound: playSound,
        video: video,
      );
    } else {
      await desktop.LocalNotificationService.showIncomingCall(
        title: title,
        body: body,
        payload: payload,
        playSound: playSound,
        video: video,
      );
    }
  }

  static Future<void> showCall({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (_isMobile) {
      await mobile.LocalNotificationService.showCall(id: id, title: title, body: body, payload: payload);
    } else {
      await desktop.LocalNotificationService.showCall(id: id, title: title, body: body, payload: payload);
    }
  }

  static Future<void> cancelIncomingCall() async {
    if (_isMobile) await mobile.LocalNotificationService.cancelIncomingCall();
    else await desktop.LocalNotificationService.cancelIncomingCall();
  }

  static Future<void> cancel(int id) async {
    if (_isMobile) await mobile.LocalNotificationService.cancel(id);
    else await desktop.LocalNotificationService.cancel(id);
  }

  static void clearChatThread(String conversationKey) {
    if (_isMobile) mobile.LocalNotificationService.clearChatThread(conversationKey);
    else desktop.LocalNotificationService.clearChatThread(conversationKey);
  }
}
