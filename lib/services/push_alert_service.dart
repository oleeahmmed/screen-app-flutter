import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'call_notification.dart';
import 'call_service.dart';
import 'chat_notification.dart';
import 'chat_notification_router.dart';
import 'local_notification_service.dart';
import 'notification_launch_router.dart';
import 'notification_sound.dart';
import 'user_data_service.dart';

/// Draws tray notifications from FCM / WebSocket payloads (same pipeline as calls).
abstract final class PushAlertService {
  static Future<void> showFromData(
    Map<String, dynamic> raw, {
    bool playSound = true,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (!LocalNotificationService.supported) return;

    final data = NotificationLaunchRouter.normalizeFcmData(raw);
    final type = data['type']?.toString() ?? '';
    final notifType = data['notification_type']?.toString() ?? '';

    if (type == 'call_dismiss') {
      await LocalNotificationService.cancelIncomingCall();
      if (playSound) await NotificationSound.stopCallSounds();
      return;
    }

    if (type == 'call_invite' || notifType == 'call_invite') {
      final name = data['caller_name']?.toString() ??
          data['sender_name']?.toString() ??
          'Incoming call';
      final callType = data['call_type']?.toString() ?? 'audio';
      final callId = data['call_id']?.toString() ?? '';
      final callerId =
          int.tryParse('${data['caller_id'] ?? data['sender_id'] ?? ''}') ?? 0;
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

    if (type == 'chat_message' || type == 'group_message') {
      await _showChatFromWs(data, isGroup: type == 'group_message');
      return;
    }

    final isChat = notifType == 'new_message' || notifType == 'new_group_message';
    if (isChat) {
      final senderId = int.tryParse('${data['sender_id'] ?? ''}');
      final myId = int.tryParse(await UserDataService.getUserId());
      if (senderId != null &&
          ChatNotificationRouter.shouldSuppress(
            senderId: senderId,
            myUserId: myId,
            peerId: senderId,
            groupId: int.tryParse('${data['group_id'] ?? ''}'),
          )) {
        return;
      }
      final chat = ChatNotification.fromData(data);
      await LocalNotificationService.showChat(
        conversationKey: chat.isGroup
            ? 'g:${chat.groupId ?? chat.name.hashCode}'
            : 'u:${chat.peerId ?? chat.name.hashCode}',
        personName: chat.name,
        body: chat.body.isNotEmpty ? chat.body : 'New message',
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

    final title = data['title']?.toString() ?? 'Aims';
    final body = (data['message'] ?? data['body'] ?? '').toString();
    if (body.isEmpty && title == 'Aims') return;

    final rawId = data['notification_id'] ?? data['id'];
    final id = rawId is int
        ? rawId
        : int.tryParse('$rawId') ?? title.hashCode;

    await LocalNotificationService.show(
      id: id & 0x7fffffff,
      title: title,
      body: body.isNotEmpty ? body : 'Tap to open Aims',
      payload: NotificationLaunchRouter.encodePayloadFromData(data),
    );
  }

  static Future<void> _showChatFromWs(
    Map<String, dynamic> data, {
    required bool isGroup,
  }) async {
    final senderId = int.tryParse('${data['sender_id'] ?? ''}');
    if (senderId == null) return;

    final myId = int.tryParse(await UserDataService.getUserId());
    if (myId != null && senderId == myId) return;

    final text = (data['message'] ?? '').toString();
    if (CallService.isHiddenCallChatMessage(text)) return;

    if (ChatNotificationRouter.shouldSuppress(
      senderId: senderId,
      myUserId: myId,
      peerId: isGroup ? null : senderId,
      groupId: isGroup ? int.tryParse('${data['group_id'] ?? ''}') : null,
    )) {
      return;
    }

    final senderName = (data['sender_full_name'] ??
            data['sender_name'] ??
            data['sender_username'] ??
            'Someone')
        .toString();
    final preview = text.trim().isEmpty
        ? ({'image': '[Image]', 'file': '[File]', 'voice': '[Voice]'})[
                data['message_type']?.toString() ?? 'text'] ??
            'New message'
        : (text.length > 120 ? '${text.substring(0, 120)}\u2026' : text);

    final notifType = isGroup ? 'new_group_message' : 'new_message';
    final chat = ChatNotification.fromData({
      'notification_type': notifType,
      'title': senderName,
      'message': preview,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_username': data['sender_username'],
      'group_id': data['group_id'],
    });

    await LocalNotificationService.showChat(
      conversationKey: chat.isGroup
          ? 'g:${chat.groupId ?? senderName.hashCode}'
          : 'u:${chat.peerId ?? senderId}',
      personName: chat.name,
      body: chat.body.isNotEmpty ? chat.body : preview,
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
  }
}
