import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/task_helpers.dart';

int? taskStageIdFrom(dynamic task) {
  if (task is! Map) return null;
  return int.tryParse('${task['stage_id'] ?? task['stage'] ?? ''}');
}

/// Glass-style stage control for task cards — PATCH `stage_id` on the task.
class TaskStageDropdown extends StatefulWidget {
  final int taskId;
  final dynamic task;
  final List<dynamic> stages;
  final ApiService apiService;
  final VoidCallback onUpdated;
  final bool compact;
  final int projectId;

  const TaskStageDropdown({
    super.key,
    required this.taskId,
    required this.task,
    required this.stages,
    required this.apiService,
    required this.onUpdated,
    this.compact = false,
    this.projectId = 0,
  });

  @override
  State<TaskStageDropdown> createState() => _TaskStageDropdownState();
}

class _TaskStageDropdownState extends State<TaskStageDropdown> {
  bool _busy = false;

  Future<void> _onChanged(String? v) async {
    if (v == null || _busy) return;
    final current = '${taskStageIdFrom(widget.task) ?? ''}';
    if (v == current) return;

    setState(() => _busy = true);
    final taskMap = widget.task is Map ? Map<String, dynamic>.from(widget.task as Map) : null;
    final projectId = widget.projectId > 0
        ? widget.projectId
        : (taskProjectIdFrom(widget.task) ?? 0);
    final stageId = int.tryParse(v);

    Map<String, dynamic> r;
    if (stageId == null) {
      r = await widget.apiService.updateTask(
        widget.taskId,
        {'stage_id': null},
        projectId: projectId,
        task: taskMap,
      );
    } else {
      r = await widget.apiService.updateTask(
        widget.taskId,
        {'stage_id': stageId},
        projectId: projectId,
        task: taskMap,
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (r['success'] == true) {
      widget.onUpdated();
    } else {
      AppToast.updateFailed(context, r['error']?.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stages.isEmpty) return const SizedBox.shrink();

    final currentId = taskStageIdFrom(widget.task);
    final value = currentId != null && widget.stages.any((s) => int.tryParse('${s['id']}') == currentId)
        ? '$currentId'
        : (currentId != null ? '$currentId' : null);

    final validValue = value != null &&
            widget.stages.any((s) => '${s['id']}' == value)
        ? value
        : null;

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
            value: validValue,
            isDense: true,
            isExpanded: true,
            hint: Text(
              widget.task['stage_name']?.toString() ?? 'Stage',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: widget.compact ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            dropdownColor: AppTheme.surface2,
            borderRadius: BorderRadius.circular(12),
            icon: Icon(
              Icons.expand_more_rounded,
              color: AppTheme.textMuted,
              size: widget.compact ? 18 : 20,
            ),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: widget.compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final s in widget.stages)
                DropdownMenuItem(
                  value: '${s['id']}',
                  child: Text(
                    s['name']?.toString() ?? 'Stage',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy ? null : _onChanged,
          ),
        ),
      ),
    );
  }
}
