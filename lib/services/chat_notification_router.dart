/// Tracks which chat thread is open so we can suppress duplicate tray toasts.
abstract final class ChatNotificationRouter {
  static bool chatTabActive = false;
  static int? activePeerId;
  static int? activeGroupId;

  static void setActiveChat({int? peerId, int? groupId}) {
    chatTabActive = true;
    activePeerId = peerId;
    activeGroupId = groupId;
  }

  static void clear() {
    chatTabActive = false;
    activePeerId = null;
    activeGroupId = null;
  }

  /// User returned to inbox list — still on Chat tab but no thread open.
  static void clearActiveThread() {
    chatTabActive = true;
    activePeerId = null;
    activeGroupId = null;
  }

  static bool shouldSuppress({
    required int? senderId,
    required int? myUserId,
    int? peerId,
    int? groupId,
  }) {
    if (myUserId != null && senderId == myUserId) return true;
    if (!chatTabActive) return false;
    if (groupId != null) return activeGroupId == groupId;
    if (peerId != null) return activePeerId == peerId;
    return false;
  }
}
