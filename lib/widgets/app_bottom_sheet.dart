import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/sheet_safe_padding.dart';
import 'premium_glass.dart';

/// Task-themed bottom sheet helper — premium glass chrome.
class AppBottomSheet {
  AppBottomSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    Widget? trailing,
    bool isScrollControlled = true,
    double initialChildSize = 0.55,
    double minChildSize = 0.35,
    double maxChildSize = 0.92,
  }) {
    return PremiumGlass.showSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      builder: (ctx) {
        final bottomPad = sheetBottomSafePadding(ctx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: bottomPad > kSheetNavClearance ? bottomPad - kSheetNavClearance : 0,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: initialChildSize,
            minChildSize: minChildSize,
            maxChildSize: maxChildSize,
            builder: (_, scrollCtrl) => ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(PremiumGlass.sheetRadius),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(PremiumGlass.sheetRadius),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.14),
                        AppTheme.primary.withValues(alpha: 0.12),
                        AppTheme.surface2.withValues(alpha: 0.92),
                      ],
                    ),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Column(
                          children: [
                            PremiumGlass.handle(),
                            PremiumGlass.header(
                              icon: Icons.layers_rounded,
                              title: title,
                              accentColor: AppTheme.primaryBright,
                              trailing: trailing,
                              onClose: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollCtrl,
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + kSheetNavClearance),
                          child: child,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
