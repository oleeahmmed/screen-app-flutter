import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// App branding mark — uses bundled launcher icon when available.
class AppLogo extends StatelessWidget {
  final double size;
  final bool showBorder;

  const AppLogo({super.key, this.size = 72, this.showBorder = true});

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/branding/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.22),
            gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF6366F1)]),
          ),
          child: Icon(Icons.monitor_rounded, color: Colors.white, size: size * 0.45),
        ),
      ),
    );

    if (!showBorder) return image;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: const Color(0x3393C5FD)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: image,
    );
  }
}
