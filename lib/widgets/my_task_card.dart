import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../pages/task_detail_page.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/task_helpers.dart';
import 'task_action_buttons.dart';
import 'task_assignee_button.dart';
import 'task_stage_dropdown.dart';
import 'task_status_dropdown.dart';

/// My Task card — same actions as before, cleaner spacing and meta.
class MyTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final ApiService apiService;
  final VoidCallback onToggleComplete;
  final VoidCallback onUpdated;
  final bool compactGrid;
  final List<dynamic> stages;
  final List<dynamic> employees;

  const MyTaskCard({
    super.key,
    required this.task,
    required this.apiService,
    required this.onToggleComplete,
    required this.onUpdated,
    this.compactGrid = false,
    this.stages = const [],
    this.employees = const [],
  });

  void _openDetail(BuildContext context) {
    final id = taskIdFrom(task);
    if (id == null) return;
    openTaskDetailPage(
      context,
      apiService: apiService,
      taskId: id,
      projectId: taskProjectIdFrom(task) ?? 0,
      projectName: task['project_name']?.toString() ?? '',
      initialTask: Map<String, dynamic>.from(task),
      onClosed: onUpdated,
    );
  }

  String _formatDueDate(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return '';
    try {
      final parsed = DateTime.parse(s.split('T').first);
      return DateFormat('dd MMM yyyy').format(parsed);
    } catch (_) {
      return s.length > 10 ? s.substring(0, 10) : s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = taskIsCompleted(task);
    final title = taskDisplayTitle(task);
    final taskId = taskIdFrom(task);
    final projectId = taskProjectIdFrom(task) ?? 0;
    final projectName = taskProjectNameFrom(task);
    final dueLabel = _formatDueDate(task['due_date']);
    final hasStages = stages.isNotEmpty;
    final pad = compactGrid ? 8.0 : 14.0;

    return Container(
      decoration: AppTheme.loginInsetDecoration(borderRadius: compactGrid ? 12 : 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openDetail(context),
              borderRadius: BorderRadius.vertical(top: Radius.circular(compactGrid ? 11 : 13)),
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, compactGrid ? 4 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: compactGrid ? 12.5 : 15,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: isCompleted
                            ? AppTheme.textMuted
                            : AppTheme.textPrimary,
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                        decorationColor: AppTheme.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (projectName.isNotEmpty || dueLabel.isNotEmpty) ...[
                      SizedBox(height: compactGrid ? 6 : 8),
                      Wrap(
                        spacing: compactGrid ? 8 : 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (projectName.isNotEmpty)
                            _MetaLine(
                              icon: Icons.folder_open_rounded,
                              label: projectName,
                            ),
                          if (dueLabel.isNotEmpty)
                            _MetaLine(
                              icon: Icons.event_rounded,
                              label: dueLabel,
                              accent: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compactGrid ? 6 : 12,
              0,
              compactGrid ? 6 : 12,
              compactGrid ? 6 : 12,
            ),
            child: compactGrid
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (taskId != null) ...[
                        TaskStatusDropdown(
                          key: ValueKey<String>(
                            'ts_${task['id']}_${task['status']}_${task['completed']}',
                          ),
                          taskId: taskId,
                          task: task,
                          projectId: projectId,
                          apiService: apiService,
                          onUpdated: onUpdated,
                          compact: true,
                        ),
                        if (hasStages) ...[
                          const SizedBox(height: 6),
                          TaskStageDropdown(
                            key: ValueKey<String>(
                              'stg_${task['id']}_${task['stage_id']}',
                            ),
                            taskId: taskId,
                            task: task,
                            stages: stages,
                            projectId: projectId,
                            apiService: apiService,
                            onUpdated: onUpdated,
                            compact: true,
                          ),
                        ],
                        const SizedBox(height: 6),
                        TaskAssigneeButton(
                          task: task,
                          employees: employees,
                          apiService: apiService,
                          onUpdated: onUpdated,
                          compact: true,
                        ),
                      ],
                      const SizedBox(height: 6),
                      TaskCompleteButton(
                        isCompleted: isCompleted,
                        onPressed: onToggleComplete,
                        compact: true,
                        dense: true,
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (taskId != null)
                        Row(
                          children: [
                            Expanded(
                              child: TaskStatusDropdown(
                                key: ValueKey<String>(
                                  'ts_${task['id']}_${task['status']}_${task['completed']}',
                                ),
                                taskId: taskId,
                                task: task,
                                projectId: projectId,
                                apiService: apiService,
                                onUpdated: onUpdated,
                                compact: true,
                              ),
                            ),
                            if (hasStages) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: TaskStageDropdown(
                                  key: ValueKey<String>(
                                    'stg_${task['id']}_${task['stage_id']}',
                                  ),
                                  taskId: taskId,
                                  task: task,
                                  stages: stages,
                                  projectId: projectId,
                                  apiService: apiService,
                                  onUpdated: onUpdated,
                                  compact: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TaskAssigneeButton(
                              task: task,
                              employees: employees,
                              apiService: apiService,
                              onUpdated: onUpdated,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 118,
                            child: TaskCompleteButton(
                              isCompleted: isCompleted,
                              onPressed: onToggleComplete,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;

  const _MetaLine({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? AppTheme.accent.withValues(alpha: 0.9)
        : AppTheme.textMuted.withValues(alpha: 0.88);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
