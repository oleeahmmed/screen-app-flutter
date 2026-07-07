import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared task complete / restore buttons (aims-webapps TaskDetailModal footer).
class TaskCompleteButton extends StatelessWidget {
  final bool isCompleted;
  final VoidCallback? onPressed;
  final bool compact;

  const TaskCompleteButton({
    super.key,
    required this.isCompleted,
    this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompleted) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(Icons.replay_rounded, size: compact ? 16 : 18),
          label: Text(compact ? 'Reopen' : 'Restore'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.warning,
            side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.55)),
            padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 10 : 12)),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          gradient: const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(Icons.check_circle_outline_rounded, size: compact ? 16 : 18),
          label: Text(compact ? 'Complete' : 'Mark complete'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 10 : 12)),
          ),
        ),
      ),
    );
  }
}

/// Save / Discard row matching web task detail footer.
class TaskDetailFooterActions extends StatelessWidget {
  final bool dirty;
  final bool saving;
  final bool isCompleted;
  final VoidCallback? onDiscard;
  final VoidCallback? onSave;
  final VoidCallback? onToggleComplete;
  final String saveHint;

  const TaskDetailFooterActions({
    super.key,
    this.dirty = false,
    this.saving = false,
    this.isCompleted = false,
    this.onDiscard,
    this.onSave,
    this.onToggleComplete,
    this.saveHint = '',
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final hint = saveHint.isNotEmpty
        ? saveHint
        : (compact ? 'Auto-saves' : 'Auto-saves · Ctrl+S · Esc');

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: saveHint == 'Saved'
                      ? const Color(0xFF10B981)
                      : Colors.white.withValues(alpha: 0.35),
                  fontSize: 11,
                ),
              ),
            ),
          TaskCompleteButton(isCompleted: isCompleted, onPressed: saving ? null : onToggleComplete),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: dirty ? onDiscard : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _saveButton(compact: true),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 140,
          child: TaskCompleteButton(
            isCompleted: isCompleted,
            onPressed: saving ? null : onToggleComplete,
            compact: true,
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: dirty ? onDiscard : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('Discard'),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            hint,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: saveHint == 'Saved'
                  ? const Color(0xFF10B981)
                  : Colors.white.withValues(alpha: 0.25),
              fontSize: 11,
            ),
          ),
        ),
        const Spacer(),
        _saveButton(compact: false),
      ],
    );
  }

  Widget _saveButton({required bool compact}) {
    return FilledButton.icon(
      onPressed: saving ? null : onSave,
      icon: saving
          ? SizedBox(
              width: compact ? 16 : 18,
              height: compact ? 16 : 18,
              child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.check, size: 16),
      label: Text(compact ? 'Save' : 'Save Changes'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.featureVault,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 20,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
