import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared task complete / restore buttons.
class TaskCompleteButton extends StatelessWidget {
  final bool isCompleted;
  final VoidCallback? onPressed;
  final bool compact;
  final bool dense;
  /// When false, button sizes to its label (for app-bar placement).
  final bool expand;

  const TaskCompleteButton({
    super.key,
    required this.isCompleted,
    this.onPressed,
    this.compact = false,
    this.dense = false,
    this.expand = true,
  });

  double get _verticalPad {
    if (dense) return 10;
    if (compact) return 12;
    return 14;
  }

  @override
  Widget build(BuildContext context) {
    final radius = expand ? 14.0 : 20.0;
    final hPad = expand ? 0.0 : 14.0;

    final Widget button;
    if (isCompleted) {
      button = OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.replay_rounded, size: compact ? 16 : 20),
        label: Text(compact ? 'Reopen' : 'Restore task'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.warning,
          side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.55)),
          padding: EdgeInsets.symmetric(vertical: expand ? _verticalPad : 8, horizontal: hPad),
          minimumSize: expand ? null : const Size(0, 36),
          tapTargetSize: expand ? null : MaterialTapTargetSize.shrinkWrap,
          visualDensity: expand ? VisualDensity.standard : VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      );
    } else {
      button = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: expand ? 0.35 : 0.28),
              blurRadius: expand ? 14 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(Icons.check_circle_outline_rounded, size: dense || !expand ? 16 : 20),
          label: Text(
            compact ? 'Complete' : 'Mark complete',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: expand ? 15 : 13,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: expand ? _verticalPad : 8, horizontal: hPad),
            minimumSize: expand ? null : const Size(0, 36),
            tapTargetSize: expand ? null : MaterialTapTargetSize.shrinkWrap,
            visualDensity: expand ? VisualDensity.standard : VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          ),
        ),
      );
    }

    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// Under title: Discard + Mark complete only.
class TaskDetailHeaderActions extends StatelessWidget {
  final bool dirty;
  final bool saving;
  final bool isCompleted;
  final VoidCallback? onDiscard;
  final VoidCallback? onToggleComplete;
  final bool completeOnly;

  const TaskDetailHeaderActions({
    super.key,
    this.dirty = false,
    this.saving = false,
    this.isCompleted = false,
    this.onDiscard,
    this.onToggleComplete,
    this.completeOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (completeOnly) {
      return TaskCompleteButton(
        isCompleted: isCompleted,
        onPressed: saving ? null : onToggleComplete,
        dense: true,
        compact: true,
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: (dirty && !saving) ? onDiscard : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textPrimary.withValues(alpha: dirty ? 0.95 : 0.4),
              side: BorderSide(color: Colors.white.withValues(alpha: dirty ? 0.22 : 0.1)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Discard', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: TaskCompleteButton(
            isCompleted: isCompleted,
            onPressed: saving ? null : onToggleComplete,
            dense: true,
          ),
        ),
      ],
    );
  }
}

/// Bottom: one Save button after tabs — bright, distinct bar.
class TaskDetailFooterActions extends StatelessWidget {
  final bool dirty;
  final bool saving;
  final VoidCallback? onSave;
  final String saveHint;

  const TaskDetailFooterActions({
    super.key,
    this.dirty = false,
    this.saving = false,
    this.onSave,
    this.saveHint = '',
  });

  @override
  Widget build(BuildContext context) {
    final hint = saveHint.isNotEmpty
        ? saveHint
        : (dirty ? 'Unsaved changes' : '');
    final active = dirty || saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: active
                  ? const [
                      Color(0xFF38BDF8),
                      Color(0xFF3B82F6),
                      Color(0xFF2563EB),
                    ]
                  : const [
                      Color(0xFF0EA5E9),
                      Color(0xFF2563EB),
                      Color(0xFF1D4ED8),
                    ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.35 : 0.18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF38BDF8).withValues(alpha: active ? 0.45 : 0.28),
                blurRadius: active ? 22 : 16,
                spreadRadius: active ? 1 : 0,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: saving ? null : onSave,
              borderRadius: BorderRadius.circular(16),
              splashColor: Colors.white.withValues(alpha: 0.18),
              highlightColor: Colors.white.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (saving)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    else
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        child: const Icon(Icons.save_rounded, size: 16, color: Colors.white),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      dirty ? 'Save changes' : 'Save',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: saveHint == 'Saved'
                  ? AppTheme.success
                  : AppTheme.warning.withValues(alpha: 0.95),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
