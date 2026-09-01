import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Circular initials avatar used in WhatsApp-style tray notifications.
abstract final class WhatsAppAvatar {
  static const _palette = <int>[
    0xFF00A884,
    0xFF53BDEB,
    0xFF6B7C85,
    0xFF25D366,
    0xFF027EB5,
    0xFF02A698,
    0xFF7F66FF,
    0xFFFF8A00,
  ];

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static Color colorFor(String name, {int? key}) {
    final n = key ?? name.hashCode;
    return Color(_palette[n.abs() % _palette.length]);
  }

  static Future<Uint8List> pngBytes(String name, {int? key, int size = 192}) async {
    final color = colorFor(name, key: key);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final s = size.toDouble();
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
        text: initials(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: s * 0.38,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((s - tp.width) / 2, (s - tp.height) / 2));
    final image = await recorder.endRecording().toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }
}
