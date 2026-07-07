import 'package:flutter/material.dart';

import '../pages/task_detail_page.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/task_helpers.dart';
import 'glass_card.dart';
import 'task_action_buttons.dart';
import 'task_status_dropdown.dart';

/// Task card for My Task page — status update, complete, open detail.
class MyTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final ApiService apiService;
  final VoidCallback onToggleComplete;
  final VoidCallback onUpdated;
  final bool showProjectName;
  final bool dense;

  const MyTaskCard({
    super.key,
    required this.task,
    required this.apiService,
    required this.onToggleComplete,
    required this.onUpdated,
    this.showProjectName = false,
    this.dense = false,
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

  @override
  Widget build(BuildContext context) {
    final isCompleted = taskIsCompleted(task);
    final priColor = priorityColor(task['priority']?.toString());
    final taskKey = taskDisplayKey(task);
    final subtaskCount = (task['subtask_count'] as num?)?.toInt() ?? 0;
    final completedSubtasks = (task['completed_subtask_count'] as num?)?.toInt() ?? 0;
    final due = (task['due_date'] ?? '').toString();
    final projectName = (task['project_name'] ?? '').toString();

    final body = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            dense ? 12 : 14,
            dense ? 12 : 14,
            dense ? 8 : 14,
            dense ? 8 : 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: dense ? 56 : 72,
                decoration: BoxDecoration(
                  color: priColor,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(color: priColor.withValues(alpha: 0.4), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (taskKey.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.featureVault.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              taskKey,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                                color: AppTheme.featureVault,
                              ),
                            ),
                          ),
                        const Spacer(),
                        TaskStatusBadge(task: task),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      taskDisplayTitle(task),
                      style: TextStyle(
                        fontSize: dense ? 14 : 16,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: AppTheme.textPrimary,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: dense ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (showProjectName && projectName.isNotEmpty)
                          _chip(Icons.folder_open_rounded, projectName, AppTheme.primaryBright),
                        if (due.isNotEmpty)
                          _chip(Icons.event_rounded, 'Due $due', priColor),
                        _chip(
                          Icons.flag_rounded,
                          (task['priority'] ?? 'medium').toString(),
                          priColor,
                        ),
                        if (subtaskCount > 0)
                          _chip(
                            Icons.checklist_rounded,
                            '$completedSubtasks/$subtaskCount',
                            AppTheme.accent,
                          ),
                      ],
                    ),
                    if (subtaskCount > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: completedSubtasks / subtaskCount,
                          minHeight: 5,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          color: priColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!dense)
                IconButton(
                  tooltip: 'Open task',
                  onPressed: () => _openDetail(context),
                  icon: Icon(
                    Icons.open_in_new_rounded,
                    color: AppTheme.textMuted.withValues(alpha: 0.85),
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final footer = Container(
      padding: EdgeInsets.fromLTRB(12, dense ? 8 : 10, 12, dense ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: dense
          ? Column(
              children: [
                TaskStatusDropdown(
                  key: ValueKey<String>(
                    'ts_${task['id']}_${task['status']}_${task['completed']}',
                  ),
                  taskId: taskIdFrom(task)!,
                  task: task,
                  projectId: taskProjectIdFrom(task) ?? 0,
                  apiService: apiService,
                  onUpdated: onUpdated,
                  compact: true,
                ),
                const SizedBox(height: 8),
                TaskCompleteButton(
                  isCompleted: isCompleted,
                  onPressed: onToggleComplete,
                  compact: true,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: TaskStatusDropdown(
                    key: ValueKey<String>(
                      'ts_${task['id']}_${task['status']}_${task['completed']}',
                    ),
                    taskId: taskIdFrom(task)!,
                    task: task,
                    projectId: taskProjectIdFrom(task) ?? 0,
                    apiService: apiService,
                    onUpdated: onUpdated,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TaskCompleteButton(
                    isCompleted: isCompleted,
                    onPressed: onToggleComplete,
                    compact: true,
                  ),
                ),
              ],
            ),
    );

    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dense) Expanded(child: body) else body,
          footer,
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: AppTheme.taskFieldDecoration(borderRadius: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
