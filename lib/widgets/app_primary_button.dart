import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool compact;
  final bool expanded;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.compact = false,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox(
            width: compact ? 18 : 22,
            height: compact ? 18 : 22,
            child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : (icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: compact ? 16 : 18),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              )
            : Text(label));

    final btn = FilledButton(
      onPressed: loading ? null : onPressed,
      style: AppTheme.primaryButton(radius: compact ? 10 : 12).copyWith(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: compact ? 16 : 20,
            vertical: compact ? 10 : 14,
          ),
        ),
      ),
      child: child,
    );

    if (expanded) {
      return SizedBox(width: double.infinity, child: btn);
    }
    return btn;
  }
}

class AppDangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  const AppDangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: AppTheme.dangerButton(radius: compact ? 10 : 12).copyWith(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: compact ? 16 : 20,
            vertical: compact ? 10 : 14,
          ),
        ),
      ),
      child: Text(label),
    );
  }
}
