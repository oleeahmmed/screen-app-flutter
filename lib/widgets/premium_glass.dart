import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/sheet_safe_padding.dart';

/// Shared “Direct transfer” style glassmorphism primitives.
abstract final class PremiumGlass {
  static const double sheetRadius = 22;
  static const double cardRadius = 20;
  static const Color accent = Color(0xFF3B82F6);

  /// Frosted panel — same language as [ChatP2pTransferSheet].
  static Widget panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    EdgeInsetsGeometry margin = EdgeInsets.zero,
    double borderRadius = cardRadius,
    bool elevated = true,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          margin: margin,
          padding: padding,
          decoration: AppTheme.glassSurfaceDecoration(
            borderRadius: borderRadius,
            elevated: elevated,
          ),
          child: child,
        ),
      ),
    );
  }

  /// Bottom-sheet chrome (top-rounded only) with blur + safe bottom lift.
  static Widget sheetBody({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final bottom = sheetBottomSafePadding(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(sheetRadius)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(sheetRadius)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.14),
                  AppTheme.primary.withValues(alpha: 0.12),
                  AppTheme.surface2.withValues(alpha: 0.88),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                left: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                right: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Padding(
              padding: padding ?? const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  static Widget handle() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  /// Gradient icon tile + title / subtitle (+ optional trailing).
  static Widget header({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? accentColor,
    VoidCallback? onClose,
    Widget? trailing,
  }) {
    final a = accentColor ?? accent;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                a.withValues(alpha: 0.95),
                a.withValues(alpha: 0.65),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: a.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
        if (onClose != null)
          IconButton(
            onPressed: onClose,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: AppTheme.textMuted.withValues(alpha: 0.9),
            ),
          ),
      ],
    );
  }

  /// Inset pill row (file row in Direct transfer).
  static Widget insetRow({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    double borderRadius = 14,
  }) {
    return Container(
      padding: padding,
      decoration: AppTheme.loginInsetDecoration(borderRadius: borderRadius),
      child: child,
    );
  }

  static Widget primaryButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    Color? color,
  }) {
    final c = color ?? accent;
    return FilledButton.icon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: c,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static Future<T?> showSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: builder,
    );
  }
}
