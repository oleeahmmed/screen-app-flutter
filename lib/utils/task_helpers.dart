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

List<int> taskAssigneeIdsFrom(dynamic task) {
  if (task is! Map) return [];
  final raw = task['assignee_ids'];
  if (raw is List && raw.isNotEmpty) {
    return raw.map((e) => int.tryParse('$e')).whereType<int>().toList();
  }
  final uid = int.tryParse('${task['user_id'] ?? task['user'] ?? task['assignee_id'] ?? ''}');
  return uid != null ? [uid] : [];
}

List<Map<String, dynamic>> taskAssigneeListFrom(dynamic task) {
  if (task is! Map) return [];
  final assignees = task['assignees'];
  if (assignees is List && assignees.isNotEmpty) {
    return assignees
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
  final ids = taskAssigneeIdsFrom(task);
  if (ids.isEmpty) return [];
  final name = task['user_name']?.toString() ?? task['assignee']?.toString() ?? 'User';
  return ids.map((id) => {'id': id, 'name': name}).toList();
}

String taskDisplayKey(dynamic task) {
  if (task is! Map) return '';
  return (task['task_key'] ?? task['taskKey'])?.toString() ?? '';
}

Color priorityColor(String? priority) {
  return AppTheme.taskPriorityColor(priority);
}

/// True when description looks like HTML from the web app.
bool descriptionLooksLikeHtml(String? text) {
  if (text == null || text.trim().isEmpty) return false;
  return RegExp(r'<\s*[a-z][^>]*>', caseSensitive: false).hasMatch(text);
}

/// Strip HTML for mobile preview / readable plain text.
String descriptionPlainText(String? html) {
  if (html == null || html.trim().isEmpty) return '';
  var s = html;
  s = s.replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*/\s*p\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '\n• ');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
  };
  entities.forEach((k, v) => s = s.replaceAll(k, v));
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Markdown preview source (HTML from API → plain text).
String descriptionPreviewMarkdown(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  if (descriptionLooksLikeHtml(raw)) return descriptionPlainText(raw);
  return raw;
}
