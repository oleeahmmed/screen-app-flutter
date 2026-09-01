/// Hidden chat tokens used to deliver call invites on production (no extra REST endpoints).
abstract final class CallTokens {
  static const invitePrefix = '__AIMS_CALL__|';
  static const acceptPrefix = '__AIMS_CALL_ACCEPT__|';
  static const rejectPrefix = '__AIMS_CALL_REJECT__|';
  static const endPrefix = '__AIMS_CALL_END__|';

  static Map<String, dynamic>? chatMessageToCallSignal(Map<String, dynamic> data) {
    final msg = data['message']?.toString() ?? '';
    if (msg.startsWith(invitePrefix)) {
      final parts = msg.split('|');
      if (parts.length < 3) return null;
      final sessionId = parts[1].trim();
      if (sessionId.isEmpty) return null;
      final callerFromToken = parts.length >= 4 ? int.tryParse(parts[3].trim()) : null;
      return {
        'type': 'call_invite',
        'call_id': sessionId,
        'session_id': sessionId,
        'call_type': parts[2].trim() == 'video' ? 'video' : 'audio',
        'sender_id': callerFromToken ?? data['sender_id'],
        'caller_id': callerFromToken ?? data['sender_id'],
        'sender_username': data['sender_username'],
        'sender_name': data['sender_name'] ?? data['sender_username'],
        'receiver_id': data['receiver_id'],
      };
    }
    if (msg.startsWith(acceptPrefix)) {
      final sessionId = msg.substring(acceptPrefix.length).trim();
      return {
        'type': 'call_accept',
        'call_id': sessionId,
        'peer_id': data['sender_id'],
      };
    }
    if (msg.startsWith(rejectPrefix)) {
      final sessionId = msg.substring(rejectPrefix.length).trim();
      return {
        'type': 'call_reject',
        'call_id': sessionId,
        'caller_id': data['sender_id'],
        'reason': 'Declined',
      };
    }
    if (msg.startsWith(endPrefix)) {
      final sessionId = msg.substring(endPrefix.length).trim();
      return {
        'type': 'call_hangup',
        'call_id': sessionId,
        'peer_id': data['sender_id'],
      };
    }
    return null;
  }

  static bool isHiddenCallChatMessage(String? message) {
    final m = message ?? '';
    return m.startsWith(invitePrefix) ||
        m.startsWith(acceptPrefix) ||
        m.startsWith(rejectPrefix) ||
        m.startsWith(endPrefix);
  }

  static String buildInvite({
    required String sessionId,
    required String callType,
    required int callerId,
  }) =>
      '$invitePrefix$sessionId|$callType|$callerId';
}
