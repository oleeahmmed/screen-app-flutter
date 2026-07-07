import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Task-themed bottom sheet helper.
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
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      barrierColor: AppTheme.modalBarrierColor,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        builder: (_, scrollCtrl) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: DecoratedBox(
            decoration: AppTheme.taskCardDecoration(borderRadius: 20).copyWith(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTheme.sectionTitle.copyWith(fontSize: 16),
                        ),
                      ),
                      if (trailing != null) trailing,
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
