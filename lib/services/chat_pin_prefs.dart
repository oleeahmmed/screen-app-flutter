import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_data_service.dart';

/// Local pinned chat order for the inbox list (per signed-in user).
class ChatPinPrefs {
  ChatPinPrefs._();

  static const _keyPrefix = 'chat_pinned_chats_v1';

  static String chatKey({required bool isGroup, required int id}) {
    return isGroup ? 'g:$id' : 'u:$id';
  }

  static Future<String> _storageKey() async {
    final userId = (await UserDataService.getUserData())['user_id']?.toString() ?? '';
    if (userId.isEmpty) return _keyPrefix;
    return '${_keyPrefix}_$userId';
  }

  static Future<List<String>> loadOrderedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await _storageKey();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((k) => k.contains(':')).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<String>> saveOrderedKeys(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await _storageKey();
    await prefs.setString(storageKey, jsonEncode(keys));
    return keys;
  }

  /// Most recently pinned chats appear first in the pinned section.
  static Future<List<String>> togglePin(String chatKey) async {
    final list = await loadOrderedKeys();
    if (list.contains(chatKey)) {
      list.remove(chatKey);
    } else {
      list.insert(0, chatKey);
    }
    return saveOrderedKeys(list);
  }
}
