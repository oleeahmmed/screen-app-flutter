import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_data_service.dart';

/// Local WhatsApp-style inbox flags (no server/DB):
/// mute (with optional expiry), mark unread, archive.
class ChatInboxPrefs {
  ChatInboxPrefs._();

  static const _mutePrefix = 'chat_muted_until_v2';
  static const _muteLegacyPrefix = 'chat_muted_v1';
  static const _unreadPrefix = 'chat_marked_unread_v1';
  static const _archivePrefix = 'chat_archived_v1';

  /// chatKey → mute-until epoch ms; `0` means forever.
  static final Map<String, int> muteUntilMs = {};
  static final Set<String> markedUnreadKeys = {};
  static final Set<String> archivedKeys = {};

  static String chatKey({required bool isGroup, required int id}) =>
      isGroup ? 'g:$id' : 'u:$id';

  static Future<String> _storageKey(String prefix) async {
    final userId = (await UserDataService.getUserData())['user_id']?.toString() ?? '';
    if (userId.isEmpty) return prefix;
    return '${prefix}_$userId';
  }

  static Future<Set<String>> _loadSet(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _storageKey(prefix));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((k) => k.contains(':')).toSet();
      }
    } catch (_) {}
    return {};
  }

  static Future<void> _saveSet(String prefix, Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _storageKey(prefix), jsonEncode(keys.toList()));
  }

  static Future<Map<String, int>> _loadMuteMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _storageKey(_mutePrefix));
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map(
            (k, v) => MapEntry(k.toString(), int.tryParse('$v') ?? 0),
          );
        }
      } catch (_) {}
    }
    // Migrate forever-mutes from v1 list.
    final legacy = await _loadSet(_muteLegacyPrefix);
    if (legacy.isEmpty) return {};
    return {for (final k in legacy) k: 0};
  }

  static Future<void> _saveMuteMap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _storageKey(_mutePrefix), jsonEncode(muteUntilMs));
  }

  /// Drop expired mutes and refresh caches.
  static Future<void> load() async {
    muteUntilMs
      ..clear()
      ..addAll(await _loadMuteMap());
    markedUnreadKeys
      ..clear()
      ..addAll(await _loadSet(_unreadPrefix));
    archivedKeys
      ..clear()
      ..addAll(await _loadSet(_archivePrefix));
    await _pruneExpiredMutes();
  }

  static Future<void> _pruneExpiredMutes() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final before = muteUntilMs.length;
    muteUntilMs.removeWhere((_, until) => until > 0 && until <= now);
    if (muteUntilMs.length != before) await _saveMuteMap();
  }

  static Set<String> get mutedKeys =>
      muteUntilMs.keys.where(isMuted).toSet();

  static bool isMuted(String chatKey) {
    final until = muteUntilMs[chatKey];
    if (until == null) return false;
    if (until == 0) return true;
    if (until <= DateTime.now().millisecondsSinceEpoch) {
      muteUntilMs.remove(chatKey);
      return false;
    }
    return true;
  }

  static bool isMutedPeer({int? peerId, int? groupId}) {
    if (groupId != null) return isMuted(chatKey(isGroup: true, id: groupId));
    if (peerId != null) return isMuted(chatKey(isGroup: false, id: peerId));
    return false;
  }

  static bool isMarkedUnread(String chatKey) => markedUnreadKeys.contains(chatKey);

  static bool isArchived(String chatKey) => archivedKeys.contains(chatKey);

  /// [duration] null = forever. Pass Duration.zero to unmute.
  static Future<bool> setMute(String chatKey, {Duration? duration}) async {
    if (duration != null && duration == Duration.zero) {
      muteUntilMs.remove(chatKey);
      await _saveMuteMap();
      return false;
    }
    if (duration == null) {
      muteUntilMs[chatKey] = 0;
    } else {
      muteUntilMs[chatKey] =
          DateTime.now().add(duration).millisecondsSinceEpoch;
    }
    await _saveMuteMap();
    return true;
  }

  /// Toggle forever mute (legacy helper). Prefer [setMute] with duration UI.
  static Future<bool> toggleMute(String chatKey) async {
    if (isMuted(chatKey)) {
      return setMute(chatKey, duration: Duration.zero);
    }
    return setMute(chatKey);
  }

  static Future<bool> toggleArchive(String chatKey) async {
    if (archivedKeys.contains(chatKey)) {
      archivedKeys.remove(chatKey);
    } else {
      archivedKeys.add(chatKey);
    }
    await _saveSet(_archivePrefix, archivedKeys);
    return archivedKeys.contains(chatKey);
  }

  static Future<void> markUnread(String chatKey) async {
    markedUnreadKeys.add(chatKey);
    await _saveSet(_unreadPrefix, markedUnreadKeys);
  }

  static Future<void> clearMarkedUnread(String chatKey) async {
    if (!markedUnreadKeys.remove(chatKey)) return;
    await _saveSet(_unreadPrefix, markedUnreadKeys);
  }

  static Future<void> clearAllMarkedUnread() async {
    if (markedUnreadKeys.isEmpty) return;
    markedUnreadKeys.clear();
    await _saveSet(_unreadPrefix, markedUnreadKeys);
  }
}
