import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Payload + helpers for WhatsApp-style chat tray actions (Reply / Mark as read).
abstract final class ChatNotification {
  static const replyAction = 'msg_reply';
  static const markReadAction = 'msg_mark_read';
  static const kind = 'chat';

  static String encode({
    required String name,
    int? peerId,
    int? groupId,
    String notificationType = 'new_message',
  }) =>
      jsonEncode({
        'kind': kind,
        'name': name,
        'peer_id': peerId,
        'group_id': groupId,
        'notification_type': notificationType,
      });

  static Map<String, dynamic>? parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload == 'chat') return {'kind': kind, 'type': 'chat'};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['kind'] != kind && map['type']?.toString() != 'chat') return null;
      return map;
    } catch (_) {
      return null;
    }
  }

  static bool isChatPayload(String? payload) => parse(payload) != null;

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse('${v ?? ''}');
  }

  /// Build chat fields from a backend notification map / FCM data.
  static ({
    String name,
    String body,
    int? peerId,
    int? groupId,
    bool isGroup,
  }) fromData(Map<String, dynamic> data) {
    final type = data['notification_type']?.toString() ?? '';
    final isGroup = type == 'new_group_message';
    final title = data['title']?.toString() ?? '';
    final body = data['message']?.toString() ?? data['body']?.toString() ?? '';
    final link = data['link']?.toString() ?? '';

    var peerId = _asInt(data['sender_id'] ?? data['peer_id'] ?? data['user_id']);
    var groupId = _asInt(data['group_id']);
    if (groupId == null && (data['object_type']?.toString() == 'chat_group')) {
      groupId = _asInt(data['object_id']);
    }

    final userMatch = RegExp(r'[?&]user=(\d+)').firstMatch(link);
    if (peerId == null && userMatch != null) {
      peerId = int.tryParse(userMatch.group(1)!);
    }
    final groupMatch = RegExp(r'[?&]group=(\d+)').firstMatch(link);
    if (groupId == null && groupMatch != null) {
      groupId = int.tryParse(groupMatch.group(1)!);
    }

    var name = data['sender_name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      final fromMsg = RegExp(r'^New message from (.+)$').firstMatch(title);
      if (fromMsg != null) {
        name = fromMsg.group(1)!.trim();
      } else if (isGroup && title.contains(':')) {
        name = title.split(':').last.trim();
      } else {
        name = title.isNotEmpty ? title : 'Aims';
      }
    }

    final groupTitle = isGroup && title.contains(':')
        ? title.split(':').first.trim()
        : (data['group_name']?.toString() ?? '');

    return (
      name: isGroup && groupTitle.isNotEmpty ? groupTitle : name,
      body: isGroup && name.isNotEmpty && body.isNotEmpty ? '$name: $body' : body,
      peerId: peerId,
      groupId: groupId,
      isGroup: isGroup || groupId != null,
    );
  }

  static Future<void> replyViaHttp(String? payload, String? text) async {
    final chat = parse(payload);
    final message = text?.trim() ?? '';
    if (chat == null || message.isEmpty) return;
    final peerId = _asInt(chat['peer_id']);
    final groupId = _asInt(chat['group_id']);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) return;

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    try {
      if (groupId != null) {
        await http
            .post(
              Uri.parse('${AppConfig.chatGroupsUrl}$groupId/messages/'),
              headers: headers,
              body: jsonEncode({'message': message}),
            )
            .timeout(const Duration(seconds: 8));
      } else if (peerId != null) {
        await http
            .post(
              Uri.parse(AppConfig.chatSendUrl),
              headers: headers,
              body: jsonEncode({'receiver_id': peerId, 'message': message}),
            )
            .timeout(const Duration(seconds: 8));
      }
    } catch (_) {}
  }

  static Future<void> markReadViaHttp(String? payload) async {
    final chat = parse(payload);
    if (chat == null) return;
    final peerId = _asInt(chat['peer_id']);
    if (peerId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse(AppConfig.chatMarkReadUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'sender_id': peerId}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }
}
