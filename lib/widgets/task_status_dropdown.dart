import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Normalized task status for dropdown (matches Django `Task.STATUS_CHOICES`).
String taskStatusValueFromMap(dynamic t) {
  final c = t['completed'] == true;
  final s = (t['status'] ?? 'pending').toString().toLowerCase();
  if (c || s == 'completed') return 'completed';
  if (s == 'in_progress') return 'in_progress';
  return 'pending';
}

/// Normalized subtask status (`SubTask.STATUS_CHOICES`).
String subtaskStatusValueFromMap(dynamic s) {
  final done = s['completed'] == true || s['status'] == 'done';
  final raw = (s['status'] ?? 'to_do').toString().toLowerCase();
  if (done || raw == 'done') return 'done';
  if (raw == 'in_progress') return 'in_progress';
  return 'to_do';
}

/// Read-only pill so status is visible at a glance (same labels as [TaskStatusDropdown]).
class TaskStatusBadge extends StatelessWidget {
  final dynamic task;

  const TaskStatusBadge({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final k = taskStatusValueFromMap(task);
    late final String label;
    late final Color color;
    switch (k) {
      case 'completed':
        label = 'Completed';
        color = AppTheme.success;
        break;
      case 'in_progress':
        label = 'In progress';
        color = const Color(0xFF3B82F6);
        break;
      default:
        label = 'Pending';
        color = const Color(0xFFF59E0B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    );
  }
}

/// Read-only pill for subtask (same labels as [SubtaskStatusDropdown]).
class SubtaskStatusBadge extends StatelessWidget {
  final dynamic subtask;

  const SubtaskStatusBadge({super.key, required this.subtask});

  @override
  Widget build(BuildContext context) {
    final k = subtaskStatusValueFromMap(subtask);
    late final String label;
    late final Color color;
    switch (k) {
      case 'done':
        label = 'Done';
        color = AppTheme.success;
        break;
      case 'in_progress':
        label = 'In progress';
        color = const Color(0xFF3B82F6);
        break;
      default:
        label = 'To do';
        color = const Color(0xFF94A3B8);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    );
  }
}

/// Glass-style status control for [Task] — PATCH `status` (pending / in_progress / completed).
class TaskStatusDropdown extends StatefulWidget {
  final int taskId;
  final dynamic task;
  final ApiService apiService;
  final VoidCallback onUpdated;
  final bool compact;

  const TaskStatusDropdown({
    super.key,
    required this.taskId,
    required this.task,
    required this.apiService,
    required this.onUpdated,
    this.compact = false,
  });

  @override
  State<TaskStatusDropdown> createState() => _TaskStatusDropdownState();
}

class _TaskStatusDropdownState extends State<TaskStatusDropdown> {
  bool _busy = false;

  Future<void> _onChanged(String? v) async {
    if (v == null || _busy) return;
    final current = taskStatusValueFromMap(widget.task);
    if (v == current) return;
    setState(() => _busy = true);
    final r = await widget.apiService.updateTask(widget.taskId, {'status': v});
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['success'] == true) {
      widget.onUpdated();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not update status')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = taskStatusValueFromMap(widget.task);
    final pad = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 6);

    return Opacity(
      opacity: _busy ? 0.65 : 1,
      child: Container(
        padding: pad,
        decoration: AppTheme.glassPanel(borderRadius: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            isExpanded: true,
            dropdownColor: AppTheme.surface2,
            borderRadius: BorderRadius.circular(12),
            icon: Icon(Icons.expand_more_rounded, color: AppTheme.textMuted, size: widget.compact ? 18 : 20),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: widget.compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
            items: const [
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
            ],
            onChanged: _busy ? null : _onChanged,
          ),
        ),
      ),
    );
  }
}

/// Glass-style status control for [SubTask] — PATCH `status` (to_do / in_progress / done).
class SubtaskStatusDropdown extends StatefulWidget {
  final int taskId;
  final int subtaskId;
  final dynamic subtask;
  final ApiService apiService;
  final VoidCallback onUpdated;

  const SubtaskStatusDropdown({
    super.key,
    required this.taskId,
    required this.subtaskId,
    required this.subtask,
    required this.apiService,
    required this.onUpdated,
  });

  @override
  State<SubtaskStatusDropdown> createState() => _SubtaskStatusDropdownState();
}

class _SubtaskStatusDropdownState extends State<SubtaskStatusDropdown> {
  bool _busy = false;

  Future<void> _onChanged(String? v) async {
    if (v == null || _busy) return;
    final current = subtaskStatusValueFromMap(widget.subtask);
    if (v == current) return;
    setState(() => _busy = true);
    final r = await widget.apiService.updateSubTask(widget.taskId, widget.subtaskId, {'status': v});
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['success'] == true) {
      widget.onUpdated();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not update status')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = subtaskStatusValueFromMap(widget.subtask);
    return Opacity(
      opacity: _busy ? 0.65 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: AppTheme.glassPanel(borderRadius: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            isExpanded: true,
            dropdownColor: AppTheme.surface2,
            borderRadius: BorderRadius.circular(12),
            icon: Icon(Icons.expand_more_rounded, color: AppTheme.textMuted, size: 18),
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            items: const [
              DropdownMenuItem(value: 'to_do', child: Text('To do')),
              DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
              DropdownMenuItem(value: 'done', child: Text('Done')),
            ],
            onChanged: _busy ? null : _onChanged,
          ),
        ),
      ),
    );
  }
}
