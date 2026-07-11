import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppToastType { success, error, warning, info }

enum AppToastPlacement { bottom, top }

/// Unified floating toast for save/update and action feedback across the app.
abstract final class AppToast {
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    AppToastType type = AppToastType.success,
    AppToastPlacement placement = AppToastPlacement.bottom,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final (IconData defaultIcon, Color accent) = switch (type) {
      AppToastType.success => (Icons.check_circle_rounded, AppTheme.success),
      AppToastType.error => (Icons.error_outline_rounded, AppTheme.danger),
      AppToastType.warning => (Icons.warning_amber_rounded, AppTheme.warning),
      AppToastType.info => (Icons.info_outline_rounded, AppTheme.primaryBright),
    };
    final toastIcon = icon ?? defaultIcon;
    final padding = MediaQuery.paddingOf(context);
    final margin = placement == AppToastPlacement.top
        ? EdgeInsets.fromLTRB(16, padding.top + 10, 16, 0)
        : EdgeInsets.fromLTRB(16, 0, 16, 16 + padding.bottom);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          duration: duration,
          margin: margin,
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.surface2.withValues(alpha: 0.97),
                    const Color(0xFF0F172A).withValues(alpha: 0.94),
                  ],
                ),
                border: Border.all(color: accent.withValues(alpha: 0.38)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.22),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 4, color: accent),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      accent.withValues(alpha: 0.32),
                                      accent.withValues(alpha: 0.14),
                                    ],
                                  ),
                                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                                ),
                                child: Icon(toastIcon, color: accent, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (title != null && title.isNotEmpty) ...[
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                    ],
                                    Text(
                                      message,
                                      style: TextStyle(
                                        color: title != null
                                            ? AppTheme.textMuted.withValues(alpha: 0.95)
                                            : AppTheme.textPrimary,
                                        fontSize: title != null ? 12 : 13,
                                        fontWeight:
                                            title != null ? FontWeight.w500 : FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
