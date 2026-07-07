import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Card surface matching Project / My Task pages.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool darker;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.borderColor,
    this.onTap,
    this.darker = false,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = AppTheme.taskCardDecoration(borderRadius: borderRadius).copyWith(
      color: AppTheme.surface2.withValues(alpha: darker ? 0.98 : 0.94),
      border: borderColor != null
          ? Border.all(color: borderColor!)
          : Border.all(color: Colors.white.withValues(alpha: 0.08)),
    );

    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      ),
    );
  }
}
