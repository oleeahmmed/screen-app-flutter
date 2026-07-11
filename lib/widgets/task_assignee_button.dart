import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/task_helpers.dart';
import 'kanban_assignee_picker.dart';

Color _avatarColorForName(String name) {
  const palette = [
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
  ];
  if (name.isEmpty) return palette[0];
  return palette[name.codeUnitAt(0) % palette.length];
}

/// Compact assign control for task cards — opens multi-select picker.
class TaskAssigneeButton extends StatefulWidget {
  final Map<String, dynamic> task;
  final List<dynamic> employees;
  final ApiService apiService;
  final VoidCallback onUpdated;
  final bool compact;

  const TaskAssigneeButton({
    super.key,
    required this.task,
    required this.employees,
    required this.apiService,
    required this.onUpdated,
    this.compact = false,
  });

  @override
  State<TaskAssigneeButton> createState() => _TaskAssigneeButtonState();
}

class _TaskAssigneeButtonState extends State<TaskAssigneeButton> {
  bool _busy = false;

  Future<void> _openPicker() async {
    if (_busy) return;
    final ids = await showKanbanAssigneePicker(
      context: context,
      employees: widget.employees,
      selectedIds: taskAssigneeIdsFrom(widget.task),
    );
    if (ids == null || !mounted) return;

    setState(() => _busy = true);
    final taskId = taskIdFrom(widget.task);
    if (taskId == null) {
      setState(() => _busy = false);
      return;
    }

    final r = await widget.apiService.updateTaskAssignees(
      taskId,
      ids,
      projectId: taskProjectIdFrom(widget.task) ?? 0,
      task: widget.task,
    );

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
    final people = taskAssigneeListFrom(widget.task);
    final radius = widget.compact ? 10.0 : 12.0;
    final canAssign = widget.employees.isNotEmpty;

    return Opacity(
      opacity: _busy ? 0.65 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canAssign ? _openPicker : null,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 8 : 10,
              vertical: widget.compact ? 6 : 8,
            ),
            decoration: AppTheme.glassPanel(borderRadius: 12),
            child: Row(
              children: [
                if (people.isEmpty)
                  CircleAvatar(
                    radius: radius,
                    backgroundColor: AppTheme.surface2,
                    child: Icon(
                      Icons.person_add_alt_1_rounded,
                      size: radius + 2,
                      color: AppTheme.textMuted,
                    ),
                  )
                else
                  SizedBox(
                    width: radius * 2 + (people.length.clamp(1, 3) - 1) * (radius * 1.1),
                    height: radius * 2 + 2,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var i = 0; i < people.length && i < 3; i++)
                          Positioned(
                            left: i * (radius * 1.05),
                            child: CircleAvatar(
                              radius: radius,
                              backgroundColor: _avatarColorForName(
                                people[i]['name']?.toString() ?? '',
                              ),
                              child: Text(
                                (people[i]['name']?.toString() ?? '?')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: radius * 0.8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        if (people.length > 3)
                          Positioned(
                            left: 3 * (radius * 1.05),
                            child: CircleAvatar(
                              radius: radius,
                              backgroundColor: AppTheme.surface2,
                              child: Text(
                                '+${people.length - 3}',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: radius * 0.7,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    people.isEmpty
                        ? (canAssign ? 'Assign' : 'No team')
                        : people.length == 1
                            ? people.first['name']?.toString() ?? 'Assigned'
                            : '${people.length} assigned',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: widget.compact ? 11 : 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.group_add_rounded,
                  size: widget.compact ? 16 : 18,
                  color: canAssign ? AppTheme.accent : AppTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
