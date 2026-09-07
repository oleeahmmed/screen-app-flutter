import 'dart:convert';

import 'chat_notification.dart';
import 'notification_deep_link.dart';

/// Queues notification tap / FCM open targets until [MainScreen] is logged in.
abstract final class NotificationLaunchRouter {
  static String? pendingPayload;
  static Map<String, dynamic>? pendingData;

  static void queuePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    pendingPayload = payload;
    pendingData = null;
  }

  static void queueData(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    pendingData = Map<String, dynamic>.from(data);
    pendingPayload = null;
  }

  static void clear() {
    pendingPayload = null;
    pendingData = null;
  }

  static bool get hasPending => pendingPayload != null || pendingData != null;

  /// Returns navigation intent for main.dart to execute.
  static ({String? payload, Map<String, dynamic>? data, bool isChat})? take() {
    if (pendingPayload != null) {
      final p = pendingPayload!;
      pendingPayload = null;
      return (
        payload: p,
        data: null,
        isChat: ChatNotification.isChatPayload(p),
      );
    }
    if (pendingData != null) {
      final d = pendingData!;
      pendingData = null;
      final type = d['notification_type']?.toString() ?? '';
      final isChat = type == 'new_message' || type == 'new_group_message';
      return (payload: null, data: d, isChat: isChat);
    }
    return null;
  }

  static Map<String, dynamic> normalizeFcmData(Map<String, dynamic> raw) {
    final data = Map<String, dynamic>.from(raw);
    final title = data['title']?.toString().trim() ?? '';
    final body = (data['message'] ?? data['body'] ?? '').toString().trim();
    if (title.isNotEmpty) data['title'] = title;
    if (body.isNotEmpty) {
      data['message'] = body;
      data['body'] = body;
    }
    final link = data['link']?.toString() ?? '';
    if (data['group_id'] == null && link.contains('group=')) {
      final m = RegExp(r'[?&]group=(\d+)').firstMatch(link);
      if (m != null) data['group_id'] = m.group(1);
    }
    if (data['peer_id'] == null && data['sender_id'] == null && link.contains('user=')) {
      final m = RegExp(r'[?&]user=(\d+)').firstMatch(link);
      if (m != null) data['sender_id'] = m.group(1);
    }
    return data;
  }

  static String encodePayloadFromData(Map<String, dynamic> data) {
    final normalized = normalizeFcmData(data);
    final type = normalized['notification_type']?.toString() ?? '';
    if (type == 'new_message' || type == 'new_group_message') {
      final chat = ChatNotification.fromData(normalized);
      return ChatNotification.encode(
        name: chat.name,
        peerId: chat.peerId,
        groupId: chat.groupId,
        notificationType: type,
      );
    }
    return NotificationDeepLink.encodeFromData(normalized);
  }

  static bool looksLikeJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  static Map<String, dynamic>? tryDecodeMap(String? raw) {
    if (raw == null || raw.isEmpty || !looksLikeJson(raw)) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}
