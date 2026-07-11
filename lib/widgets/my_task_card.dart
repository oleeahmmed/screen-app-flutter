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

/// Minimal task card for My Task — quick actions without opening detail.
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

    return Container(
      decoration: AppTheme.loginInsetDecoration(borderRadius: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openDetail(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compactGrid ? 10 : 14,
                  compactGrid ? 10 : 14,
                  compactGrid ? 10 : 14,
                  compactGrid ? 4 : 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: compactGrid ? 13 : 15,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: AppTheme.textPrimary,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                        decorationColor: AppTheme.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (compactGrid && (projectName.isNotEmpty || dueLabel.isNotEmpty)) ...[
                      const SizedBox(height: 6),
                      if (projectName.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 11,
                              color: AppTheme.textMuted.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                projectName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textMuted.withValues(alpha: 0.9),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      if (dueLabel.isNotEmpty) ...[
                        if (projectName.isNotEmpty) const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.event_rounded,
                              size: 11,
                              color: AppTheme.accent.withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                dueLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.accent.withValues(alpha: 0.9),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compactGrid ? 8 : 12,
              0,
              compactGrid ? 8 : 12,
              compactGrid ? 8 : 12,
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
                            key: ValueKey<String>('stg_${task['id']}_${task['stage_id']}'),
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
                                  key: ValueKey<String>('stg_${task['id']}_${task['stage_id']}'),
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
