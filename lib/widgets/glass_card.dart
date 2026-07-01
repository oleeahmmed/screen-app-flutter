import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Glass panel wrapper — consistent padding, radius, optional tap.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = AppTheme.glassPanel(borderRadius: borderRadius).copyWith(
      border: borderColor != null
          ? Border.all(color: borderColor!)
          : Border.all(color: Colors.white.withValues(alpha: 0.1)),
    );

    if (onTap == null) {
      return Container(
        width: double.infinity,
        padding: padding,
        decoration: decoration,
        child: child,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(
          width: double.infinity,
          padding: padding,
          decoration: decoration,
          child: child,
        ),
      ),
    );
  }
}
