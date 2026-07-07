import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// iGenHR — polished dark theme (aligned with monitor glass / indigo).
class AppTheme {
  AppTheme._();

  // Glassmorphism color palette - matching aims-webapps
  static const Color bgDeep = Color(0xFF0A1628);  // Deep ocean blue
  static const Color surface = Color(0xFF0F172A);  // Glass surface
  static const Color surface2 = Color(0xFF1E3A8A);  // Accent surface
  static const Color border = Color(0x1E93C5FD);  // Cyan glass border
  static const Color primary = Color(0xFF3B82F6);  // Primary blue
  static const Color primaryBright = Color(0xFF60A5FA);  // Sky blue
  static const Color accent = Color(0xFF38BDF8);  // Cyan accent
  static const Color success = Color(0xFF10B981);  // Emerald
  static const Color warning = Color(0xFFF59E0B);  // Amber
  static const Color danger = Color(0xFFEF4444);  // Red
  static const Color textPrimary = Color(0xFFFAFAFA);
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
        indicatorColor: Colors.white.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            letterSpacing: 0.2,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : textMuted.withValues(alpha: 0.85),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? primaryBright : textMuted.withValues(alpha: 0.75),
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
          Color(0xFF0C1929),
          Color(0xFF0A1628),
          Color(0xFF0F172A),
        ],
        stops: [0.0, 0.35, 1.0],
      ),
    );
  }
  
  /// Screen gradient with radial overlays (glassmorphism effect)
  static Widget screenGradientWithOverlay({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0C1929),
            Color(0xFF0A1628),
            Color(0xFF0F172A),
          ],
          stops: [0.0, 0.35, 1.0],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [
              const Color(0xFF38BDF8).withValues(alpha: 0.22),
              Colors.transparent,
            ],
            stops: const [0.0, 0.52],
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topRight,
              radius: 1.5,
              colors: [
                const Color(0xFF6366F1).withValues(alpha: 0.14),
                Colors.transparent,
              ],
              stops: const [0.0, 0.48],
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.bottomLeft,
                radius: 1.3,
                colors: [
                  const Color(0xFF0EA5E9).withValues(alpha: 0.1),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  /// Glassmorphism panel - matching aims-webapps style with darker variant
  static BoxDecoration glassPanel({
    double borderRadius = 16,
    Color? topTint,
    Color? bottomTint,
    bool darker = false,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: const Color(0xFF93C5FD).withValues(alpha: darker ? 0.1 : 0.12),
        width: 1,
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: darker
            ? [
                const Color(0xFF0F172A).withValues(alpha: 0.95),
                const Color(0xFF0F172A).withValues(alpha: 0.88),
              ]
            : [
                const Color(0xFF0F172A).withValues(alpha: 0.78),
                const Color(0xFF0F172A).withValues(alpha: 0.65),
              ],
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: darker ? 0.65 : 0.55),
          blurRadius: 32,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Project list card surface (Work tab) — surface2 tint with soft shadow.
  static BoxDecoration projectCardDecoration({double borderRadius = 16}) {
    return BoxDecoration(
      color: surface2.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  /// Inset panel inside a project-style card (stats, inputs).
  static BoxDecoration projectCardInset({double borderRadius = 10}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    );
  }

  /// Status / priority pill on project cards.
  static BoxDecoration projectStatusPill(Color color) {
    return BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    );
  }

  // ─── Task UI (Create Task modal theme) ───

  /// Deep navy panel — Create Task dialog / task edit sections.
  static BoxDecoration taskPanelDecoration({double borderRadius = 16}) {
    return BoxDecoration(
      color: surface2,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    );
  }

  /// Task list card — same family as Create Task modal.
  static BoxDecoration taskCardDecoration({double borderRadius = 16}) {
    return BoxDecoration(
      color: surface2.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  /// Inset field surface inside task panels.
  static BoxDecoration taskFieldDecoration({double borderRadius = 10}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    );
  }

  static InputDecoration taskInputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: featureVault.withValues(alpha: 0.6)),
      ),
    );
  }

  static InputDecoration taskLabeledInput(String label, {String? hint}) {
    return taskInputDecoration(hint).copyWith(
      labelText: label,
      labelStyle: TextStyle(color: textMuted.withValues(alpha: 0.9), fontSize: 12),
      floatingLabelStyle: const TextStyle(color: primaryBright, fontSize: 12),
    );
  }

  static ButtonStyle taskPrimaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: featureVault,
      foregroundColor: Colors.white,
      disabledForegroundColor: textPrimary.withValues(alpha: 0.7),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  static ButtonStyle taskSecondaryButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: primaryBright,
      side: BorderSide(color: primary.withValues(alpha: 0.45)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  static BoxDecoration taskFilterChip({required bool active}) {
    return BoxDecoration(
      color: active ? featureVault.withValues(alpha: 0.22) : surface2.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: active ? featureVault.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.1),
      ),
    );
  }

  static BoxDecoration taskPriorityChip({required bool selected, required Color color}) {
    return BoxDecoration(
      color: selected ? color.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: selected ? color : Colors.white.withValues(alpha: 0.12)),
    );
  }

  static Color taskPriorityColor(String? priority) {
    switch ((priority ?? 'medium').toLowerCase()) {
      case 'high':
      case 'critical':
        return danger;
      case 'low':
        return success;
      default:
        return warning;
    }
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

  /// Base gradient shared by shell and glass screens.
  static BoxDecoration get shellBackgroundDecoration => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0E2240),
            Color(0xFF0B1829),
            Color(0xFF101F3D),
            Color(0xFF0A1628),
          ],
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
      );

  /// Home / tool pages — same blue glass shell as Daily Report.
  static Widget homeGlassBackground({required Widget child}) {
    return DecoratedBox(
      decoration: shellBackgroundDecoration,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.2, -0.75),
                radius: 1.25,
                colors: [
                  primaryBright.withValues(alpha: 0.38),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.62],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.1, -0.2),
                radius: 1.0,
                colors: [
                  accent.withValues(alpha: 0.22),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, 1.1),
                radius: 1.15,
                colors: [
                  featureVault.withValues(alpha: 0.16),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.58],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  /// Premium glossy card for Home dashboard.
  static BoxDecoration homeGlossCardDecoration({double borderRadius = 16}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.16),
          primary.withValues(alpha: 0.12),
          surface.withValues(alpha: 0.52),
        ],
        stops: const [0.0, 0.4, 1.0],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
      boxShadow: [
        BoxShadow(
          color: primaryBright.withValues(alpha: 0.16),
          blurRadius: 32,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.32),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static BoxDecoration homeGlossInsetDecoration({double borderRadius = 12}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.11),
          Colors.white.withValues(alpha: 0.04),
        ],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
    );
  }

  static Widget homeGlossCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    double borderRadius = 16,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: homeGlossCardDecoration(borderRadius: borderRadius),
          child: child,
        ),
      ),
    );
  }

  /// Frosted glass panel decoration for cards.
  static BoxDecoration glassSurfaceDecoration({
    double borderRadius = 16,
    bool elevated = true,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.16),
          primary.withValues(alpha: 0.14),
          surface2.withValues(alpha: 0.32),
        ],
        stops: const [0.0, 0.45, 1.0],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: primary.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ]
          : [],
    );
  }

  /// Inset glass chip inside a card.
  static BoxDecoration glassInsetDecoration({double borderRadius = 10}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
    );
  }

  /// Card with backdrop blur — premium glassmorphism.
  static Widget glassCard({
    required Widget child,
    double borderRadius = 16,
    EdgeInsetsGeometry? padding,
    bool elevated = true,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: glassSurfaceDecoration(
            borderRadius: borderRadius,
            elevated: elevated,
          ),
          child: child,
        ),
      ),
    );
  }

  /// Bottom nav — same surface as My Tasks cards.
  static Widget footerBlueGlass({
    required Widget child,
    double topRadius = 16,
  }) {
    return DecoratedBox(
      decoration: taskCardDecoration(borderRadius: topRadius).copyWith(
        borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      ),
      child: child,
    );
  }

  /// Bottom nav / sheet: blur + darker glass tint.
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
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0F172A).withValues(alpha: 0.82),
                const Color(0xFF0A1628).withValues(alpha: 0.96),
              ],
            ),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
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
