import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppToastType { success, error, warning, info }

/// Unified floating toast for save/update and action feedback across the app.
abstract final class AppToast {
  static void show(
    BuildContext context, {
    required String message,
    AppToastType type = AppToastType.success,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final (IconData icon, Color accent) = switch (type) {
      AppToastType.success => (Icons.check_circle_rounded, AppTheme.success),
      AppToastType.error => (Icons.error_outline_rounded, AppTheme.danger),
      AppToastType.warning => (Icons.warning_amber_rounded, AppTheme.warning),
      AppToastType.info => (Icons.info_outline_rounded, AppTheme.primaryBright),
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          duration: duration,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          content: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.surface2.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.42)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  static void saved(BuildContext context, {String? message}) =>
      show(context, message: message ?? 'Saved successfully', type: AppToastType.success);

  static void updated(BuildContext context, {String? message}) =>
      show(context, message: message ?? 'Updated successfully', type: AppToastType.success);

  static void saveFailed(BuildContext context, [String? error]) =>
      show(context, message: error ?? 'Could not save', type: AppToastType.error);

  static void updateFailed(BuildContext context, [String? error]) =>
      show(context, message: error ?? 'Could not update', type: AppToastType.error);

  static void success(BuildContext context, String message) =>
      show(context, message: message, type: AppToastType.success);

  static void error(BuildContext context, String message) =>
      show(context, message: message, type: AppToastType.error);

  static void warning(BuildContext context, String message) =>
      show(context, message: message, type: AppToastType.warning);

  static void info(BuildContext context, String message) =>
      show(context, message: message, type: AppToastType.info);
}
