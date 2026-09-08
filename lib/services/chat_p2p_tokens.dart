/// Hidden chat tokens for in-chat P2P file transfer invites (no server file storage).
abstract final class ChatP2pTokens {
  static const invitePrefix = '__AIMS_P2P_FILE__|';
  static const acceptPrefix = '__AIMS_P2P_FILE_ACCEPT__|';
  static const rejectPrefix = '__AIMS_P2P_FILE_REJECT__|';

  static String buildInvite({
    required String sessionId,
    required String fileName,
    required int fileSize,
    required int senderId,
  }) {
    final safeName = fileName.replaceAll('|', '_');
    return '$invitePrefix$sessionId|$safeName|$fileSize|$senderId';
  }

  static Map<String, dynamic>? parseInvite(String? message) {
    final msg = message ?? '';
    if (!msg.startsWith(invitePrefix)) return null;
    final parts = msg.split('|');
    if (parts.length < 5) return null;
    final sessionId = parts[1].trim();
    if (sessionId.isEmpty) return null;
    final fileName = parts[2].trim();
    final fileSize = int.tryParse(parts[3].trim()) ?? 0;
    final senderId = int.tryParse(parts[4].trim());
    if (senderId == null) return null;
    return {
      'type': 'p2p_file_invite',
      'session_id': sessionId,
      'file_name': fileName,
      'file_size': fileSize,
      'sender_id': senderId,
    };
  }

  static bool isHiddenMessage(String? message) {
    final m = message ?? '';
    return m.startsWith(invitePrefix) ||
        m.startsWith(acceptPrefix) ||
        m.startsWith(rejectPrefix);
  }
}
