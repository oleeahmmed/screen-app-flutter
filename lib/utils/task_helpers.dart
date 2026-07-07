import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared task field helpers — mirrors aims-webapps `normalizeTask` fields.

int? taskIdFrom(dynamic task) {
  if (task is! Map) return null;
  return int.tryParse('${task['id']}');
}

int? taskProjectIdFrom(dynamic task) {
  if (task is! Map) return null;
  final raw = task['project_id'] ?? task['projectId'] ?? task['project'];
  return int.tryParse('$raw');
}

bool taskIsCompleted(dynamic task) {
  if (task is! Map) return false;
  if (task['completed'] == true) return true;
  return (task['status'] ?? '').toString().toLowerCase() == 'completed';
}

String taskDisplayTitle(dynamic task) {
  if (task is! Map) return 'Task';
  return (task['name'] ?? task['title'])?.toString() ?? 'Task';
}

String taskProjectNameFrom(dynamic task) {
  if (task is! Map) return '';
  return (task['project_name'] ?? task['projectName'] ?? '').toString();
}

String taskDisplayKey(dynamic task) {
  if (task is! Map) return '';
  return (task['task_key'] ?? task['taskKey'])?.toString() ?? '';
}

Color priorityColor(String? priority) {
  return AppTheme.taskPriorityColor(priority);
}
