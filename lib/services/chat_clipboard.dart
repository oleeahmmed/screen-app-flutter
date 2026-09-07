import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pasteboard/pasteboard.dart';

import '../widgets/chat_image_send_preview.dart';

/// WhatsApp-style clipboard helpers for chat (text + images).
abstract final class ChatClipboard {
  static const MethodChannel _androidChannel =
      MethodChannel('com.example.igen_app/clipboard');

  static Future<Uint8List?> readImage({Uint8List? fallback}) async {
    final inApp = InAppImageClipboard.bytes;
    if (inApp != null && inApp.isNotEmpty) return inApp;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final native = await _androidChannel.invokeMethod('readClipboardImage');
        final bytes = _asBytes(native);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (_) {}
    }

    try {
      final bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (_) {}

    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  static Uint8List? _asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return null;
  }

  static Future<bool> writeImage(List<int> bytes) async {
    final data = Uint8List.fromList(bytes);

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final ok = await _androidChannel.invokeMethod<bool>(
          'writeClipboardImage',
          {'bytes': data},
        );
        if (ok == true) return true;
      } catch (_) {}
    }

    try {
      await Pasteboard.writeImage(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> writeText(String text) async {
    if (text.trim().isEmpty) return false;
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  static Future<bool> hasImage() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        return await _androidChannel.invokeMethod<bool>('hasClipboardImage') == true;
      } catch (_) {}
    }
    return false;
  }

  static Future<String?> readText() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final hasImage = await _androidChannel.invokeMethod<bool>('hasClipboardImage');
        if (hasImage == true) return null;
      } catch (_) {}
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static Future<bool> copyImageFromUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: headers ?? const {});
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return await writeImage(resp.bodyBytes);
      }
    } catch (_) {}
    return false;
  }

  static Future<Uint8List?> downloadImageBytes(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: headers ?? const {});
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
    } catch (_) {}
    return null;
  }
}
