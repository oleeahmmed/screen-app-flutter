import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Windows shared_preferences can leave a zeroed / corrupt JSON file that makes
/// every login fail with FormatException after a successful API response.
abstract final class PrefsRepair {
  static const _candidates = <List<String>>[
    ['igenhr', 'Aims'],
    ['com.example', 'igen_app'],
  ];

  /// Delete unreadable shared_preferences.json before the plugin loads it.
  static Future<void> repairIfNeeded() async {
    if (kIsWeb || !Platform.isWindows) return;
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return;

    for (final parts in _candidates) {
      final file = File(
        [
          appData,
          ...parts,
          'shared_preferences.json',
        ].join(Platform.pathSeparator),
      );
      await _repairFile(file);
    }
  }

  static Future<void> _repairFile(File file) async {
    try {
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        await file.delete();
        debugPrint('PrefsRepair: deleted empty ${file.path}');
        return;
      }
      // All-null / binary garbage from a crashed write.
      final nonZero = bytes.any((b) => b != 0);
      if (!nonZero) {
        await file.delete();
        debugPrint('PrefsRepair: deleted zeroed ${file.path}');
        return;
      }
      final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
      if (!text.startsWith('{')) {
        await file.delete();
        debugPrint('PrefsRepair: deleted non-JSON ${file.path}');
        return;
      }
      jsonDecode(text);
    } catch (e) {
      try {
        if (await file.exists()) await file.delete();
        debugPrint('PrefsRepair: deleted corrupt ${file.path} ($e)');
      } catch (_) {}
    }
  }
}
