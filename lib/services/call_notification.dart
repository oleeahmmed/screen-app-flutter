import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'call_tokens.dart';

/// Payload + helpers for incoming-call tray actions (Answer / Decline).
abstract final class CallNotification {
  static const acceptAction = 'call_accept';
  static const declineAction = 'call_decline';
  static const notificationId = 900001;

  static String encode({
    required String callId,
    required int callerId,
    required String callType,
    required String callerName,
  }) =>
      jsonEncode({
        'kind': 'call',
        'call_id': callId,
        'caller_id': callerId,
        'sender_id': callerId,
        'call_type': callType,
        'caller_name': callerName,
        'sender_name': callerName,
        'type': 'call_invite',
      });

  static Map<String, dynamic>? parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload.startsWith('call:') || payload == 'call') {
      final id = payload.startsWith('call:') ? payload.substring(5) : '';
      return {
        'type': 'call_invite',
        'call_id': id,
        'kind': 'call',
      };
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['kind'] != 'call' && map['type'] != 'call_invite') return null;
      map['type'] = 'call_invite';
      return map;
    } catch (_) {
      return null;
    }
  }

  static bool isCallPayload(String? payload) => parse(payload) != null;

  /// Decline without a live CallService (killed-state notification action).
  static Future<void> rejectViaHttp(String? payload) async {
    final invite = parse(payload);
    if (invite == null) return;
    final callId = invite['call_id']?.toString() ?? '';
    final callerId = int.tryParse('${invite['caller_id'] ?? invite['sender_id'] ?? ''}');
    if (callId.isEmpty || callerId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    await prefs.setString('pending_call_decline', payload ?? '');
    if (token == null || token.isEmpty) return;

    try {
      await http
          .post(
            Uri.parse(AppConfig.chatSendUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'receiver_id': callerId,
              'message': '${CallTokens.rejectPrefix}$callId',
            }),
          )
          .timeout(const Duration(seconds: 8));
      await prefs.remove('pending_call_decline');
    } catch (_) {}
  }

  static Future<void> flushPendingDecline() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('pending_call_decline');
    if (stored == null || stored.isEmpty) return;
    await prefs.remove('pending_call_decline');
    await rejectViaHttp(stored);
  }
}
