import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// iGenHR — polished dark theme (aligned with monitor glass / indigo).
class AppTheme {
  AppTheme._();

  static const Color bgDeep = Color(0xFF0B1220);
  static const Color surface = Color(0xFF111827);
  static const Color surface2 = Color(0xFF1E293B);
  static const Color border = Color(0x1AFFFFFF);
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryBright = Color(0xFF818CF8);
  static const Color accent = Color(0xFF22D3EE);
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF94A3B8);

  // Semantic tokens (status, priority, feature accents)
  static const Color statusActive = success;
  static const Color statusPending = warning;
  static const Color statusInactive = textMuted;
  static const Color priorityHigh = danger;
  static const Color priorityMedium = primary;
  static const Color priorityLow = Color(0xFF64748B);
  static const Color featureChat = accent;
  static const Color featureVault = Color(0xFFA78BFA);
  static const Color featureReport = primaryBright;

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        surface: surface,
        primary: primary,
        secondary: accent,
        error: danger,
        onSurface: textPrimary,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: bgDeep,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: primary.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            letterSpacing: 0.2,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primaryBright : textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? primaryBright : textMuted,
            size: 24,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBright,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface2.withValues(alpha: 0.6),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface2,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
    );
  }

  static EdgeInsets dialogInsets(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return EdgeInsets.symmetric(
      horizontal: w < 400 ? 12 : 24,
      vertical: h < 640 ? 16 : 24,
    );
  }

  static double dialogMaxWidth(BuildContext context, {double max = 480}) {
    return (MediaQuery.sizeOf(context).width - 32).clamp(280.0, max);
  }

  /// Login card shell — matches aims-webapps `.login-shell`.
  static BoxDecoration loginShell() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0x3393C5FD)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          surface2.withValues(alpha: 0.92),
          const Color(0xFF0F172A).withValues(alpha: 0.88),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: primary.withValues(alpha: 0.18),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  static LinearGradient titleGradient() {
    return const LinearGradient(
      colors: [Color(0xFFA5B4FC), Color(0xFF7DD3FC), Color(0xFF67E8F9)],
    );
  }

  static ButtonStyle primaryButton({double radius = 12}) {
    return FilledButton.styleFrom(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      elevation: 0,
    );
  }

  static ButtonStyle secondaryButton({double radius = 12}) {
    return OutlinedButton.styleFrom(
      foregroundColor: primaryBright,
      side: BorderSide(color: primary.withValues(alpha: 0.4)),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    );
  }

  static ButtonStyle dangerButton({double radius = 12}) {
    return FilledButton.styleFrom(
      backgroundColor: danger,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      elevation: 0,
    );
  }

  static TextStyle get pageTitle => const TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      );

  static TextStyle get sectionTitle => const TextStyle(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get caption => TextStyle(
        color: textMuted.withValues(alpha: 0.9),
        fontSize: 12,
      );

  static BoxDecoration screenGradient() {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF1E3A8A),
          Color(0xFF172554),
          Color(0xFF0F172A),
          bgDeep,
        ],
        stops: [0.0, 0.35, 0.65, 1.0],
      ),
    );
  }

  /// Frosted glass panel (gradient + border + soft shadow). Pair with [glassBlur] for stronger effect.
  static BoxDecoration glassPanel({
    double borderRadius = 16,
    Color? topTint,
    Color? bottomTint,
  }) {
    final a = topTint ?? surface2;
    final b = bottomTint ?? surface;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          a.withValues(alpha: 0.72),
          b.withValues(alpha: 0.55),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Solid surface for modals — blocks scroll content from showing through.
  static BoxDecoration dialogPanel({double borderRadius = 20}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      color: surface2,
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.55),
          blurRadius: 40,
          offset: const Offset(0, 16),
        ),
      ],
    );
  }

  static Color get modalBarrierColor => Colors.black.withValues(alpha: 0.85);

  /// Bottom nav / sheet: blur + dark glass tint.
  static Widget glassBlur({
    required Widget child,
    double topRadius = 28,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface2.withValues(alpha: 0.94),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
