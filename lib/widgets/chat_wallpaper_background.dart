import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/chat_wallpaper_prefs.dart';

/// WhatsApp-style chat thread background (doodle / solid / custom image).
class ChatWallpaperBackground extends StatelessWidget {
  const ChatWallpaperBackground({
    super.key,
    required this.kind,
    this.solidColor = 0xFF0B141A,
    this.imagePath,
  });

  final ChatWallpaperKind kind;
  final int solidColor;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case ChatWallpaperKind.image:
        final path = imagePath;
        if (path != null && File(path).existsSync()) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true),
              ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
            ],
          );
        }
        return const CustomPaint(painter: WhatsAppDoodleWallpaperPainter());
      case ChatWallpaperKind.solid:
        return ColoredBox(color: Color(solidColor));
      case ChatWallpaperKind.doodle:
        return const CustomPaint(painter: WhatsAppDoodleWallpaperPainter());
    }
  }
}

/// Tail corner for WhatsApp-like bubbles (sharp corner on the outer top edge).
BorderRadius chatBubbleRadius({required bool isOwn}) {
  if (isOwn) {
    return const BorderRadius.only(
      topLeft: Radius.circular(8),
      topRight: Radius.circular(2),
      bottomLeft: Radius.circular(8),
      bottomRight: Radius.circular(8),
    );
  }
  return const BorderRadius.only(
    topLeft: Radius.circular(2),
    topRight: Radius.circular(8),
    bottomLeft: Radius.circular(8),
    bottomRight: Radius.circular(8),
  );
}

class WhatsAppDoodleWallpaperPainter extends CustomPainter {
  const WhatsAppDoodleWallpaperPainter();

  static const _bg = Color(0xFF0B141A);
  static const _ink = Color(0x14FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    const stepX = 96.0;
    const stepY = 96.0;
    final icons = <void Function(Canvas, Offset)>[
      _drawHeart,
      _drawStar,
      _drawMic,
      _drawCamera,
      _drawClock,
      _drawBubble,
      _drawPin,
      _drawSmile,
    ];

    var n = 0;
    for (double y = -24; y < size.height + 24; y += stepY) {
      for (double x = -24; x < size.width + 24; x += stepX) {
        final ox = x + ((n % 3) - 1) * 18;
        final oy = y + ((n % 5) - 2) * 14;
        canvas.save();
        canvas.translate(ox + 24, oy + 24);
        canvas.rotate((n % 7 - 3) * 0.12);
        icons[n % icons.length](canvas, Offset.zero);
        canvas.restore();
        n++;
      }
    }

    // Subtle vignette so bubbles stay readable.
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.12)],
        stops: const [0.72, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, vignette);

    void doodle(void Function(Canvas, Offset) fn, Offset at) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      fn(canvas, Offset.zero);
      canvas.restore();
    }

    // Extra scattered accents (stroke only).
    for (var i = 0; i < 8; i++) {
      doodle(_drawStar, Offset(size.width * (0.1 + i * 0.11), size.height * (0.08 + (i % 4) * 0.22)));
    }
  }

  static void _drawHeart(Canvas canvas, Offset c) {
    final p = Path()
      ..moveTo(c.dx, c.dy + 4)
      ..cubicTo(c.dx - 10, c.dy - 8, c.dx - 18, c.dy + 6, c.dx, c.dy + 16)
      ..cubicTo(c.dx + 18, c.dy + 6, c.dx + 10, c.dy - 8, c.dx, c.dy + 4)
      ..close();
    canvas.drawPath(p, Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.1);
  }

  static void _drawStar(Canvas canvas, Offset c) {
    const r = 9.0;
    final p = Path();
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 4 * math.pi / 5;
      final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    p.close();
    canvas.drawPath(p, Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.0);
  }

  static void _drawMic(Canvas canvas, Offset c) {
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: 10, height: 16),
      const Radius.circular(5),
    );
    canvas.drawRRect(r, Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.1);
    canvas.drawLine(Offset(c.dx, c.dy + 10), Offset(c.dx, c.dy + 18), Paint()..color = _ink..strokeWidth = 1.1);
    canvas.drawLine(Offset(c.dx - 7, c.dy + 18), Offset(c.dx + 7, c.dy + 18), Paint()..color = _ink..strokeWidth = 1.1);
  }

  static void _drawCamera(Canvas canvas, Offset c) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 22, height: 16), const Radius.circular(3)),
      Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.1,
    );
    canvas.drawCircle(c, 5, Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.0);
  }

  static void _drawClock(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 9, Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.1);
    canvas.drawLine(c, Offset(c.dx, c.dy - 4), Paint()..color = _ink..strokeWidth = 1.0);
    canvas.drawLine(c, Offset(c.dx + 4, c.dy), Paint()..color = _ink..strokeWidth = 1.0);
  }

  static void _drawBubble(Canvas canvas, Offset c) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(0, 2), width: 20, height: 14), const Radius.circular(5)),
      Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.0,
    );
    canvas.drawCircle(Offset(c.dx - 8, c.dy + 10), 2, Paint()..color = _ink);
    canvas.drawCircle(Offset(c.dx - 12, c.dy + 14), 1.5, Paint()..color = _ink);
  }

  static void _drawPin(Canvas canvas, Offset c) {
    canvas.drawCircle(Offset(c.dx, c.dy - 4), 5, Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.0);
    canvas.drawLine(Offset(c.dx, c.dy + 1), Offset(c.dx, c.dy + 14), Paint()..color = _ink..strokeWidth = 1.0);
  }

  static void _drawSmile(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 9, Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.0);
    canvas.drawArc(
      Rect.fromCenter(center: c.translate(0, 2), width: 10, height: 6),
      0.1,
      math.pi - 0.2,
      false,
      Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
