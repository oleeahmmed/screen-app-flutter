import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_primary_button.dart';

/// Themed dialogs aligned with AppTheme glass style.
class AppDialog {
  AppDialog._();

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: AppTheme.modalBarrierColor,
      builder: (ctx) => AlertDialog(
        insetPadding: AppTheme.dialogInsets(context),
        backgroundColor: Colors.transparent,
        elevation: 0,
        contentPadding: EdgeInsets.zero,
        content: Material(
          color: AppTheme.surface2,
          elevation: 0,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: BoxConstraints(maxWidth: AppTheme.dialogMaxWidth(context)),
            decoration: AppTheme.dialogPanel(borderRadius: 20),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: AppTheme.sectionTitle.copyWith(fontSize: 16)),
              const SizedBox(height: 12),
              content,
              if (actions != null && actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions,
                ),
              ],
            ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) {
    return show<bool>(
      context: context,
      title: title,
      content: Text(message, style: AppTheme.caption.copyWith(height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
        destructive
            ? AppDangerButton(
                label: confirmLabel,
                onPressed: () => Navigator.pop(context, true),
                compact: true,
              )
            : AppPrimaryButton(
                label: confirmLabel,
                onPressed: () => Navigator.pop(context, true),
                compact: true,
              ),
      ],
    );
  }

  static Future<void> alert({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    return show<void>(
      context: context,
      title: title,
      content: Text(message, style: AppTheme.caption.copyWith(height: 1.45)),
      actions: [
        AppPrimaryButton(
          label: 'OK',
          onPressed: () => Navigator.pop(context),
          compact: true,
        ),
      ],
    );
  }
}
