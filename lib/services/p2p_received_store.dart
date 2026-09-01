import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local history of P2P received files (device only).
class P2pReceivedStore {
  static const _key = 'p2p_received_files_v1';
  static const _max = 40;

  static Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List? ?? [];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add({
    required String name,
    required String path,
    required int size,
    String? contentUri,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    items.removeWhere((e) => e['path'] == path);
    items.insert(0, {
      'name': name,
      'path': path,
      'size': size,
      if (contentUri != null && contentUri.isNotEmpty) 'contentUri': contentUri,
      'at': DateTime.now().toIso8601String(),
    });
    while (items.length > _max) {
      items.removeLast();
    }
    await prefs.setString(_key, jsonEncode(items));
  }

  static Future<void> remove(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    items.removeWhere((e) => e['path'] == path);
    await prefs.setString(_key, jsonEncode(items));
  }
}
