import 'dart:convert';

import 'call_notification.dart';
import 'chat_notification.dart';

/// Where a tray / FCM / in-app notification tap should land.
enum NotificationDest {
  chat,
  task,
  call,
  project,
  report,
  vault,
  p2p,
  myTasks,
  attendance,
  alerts,
}

/// Encodes and parses notification tap payloads so the app opens the real
/// screen (task, chat, call…) instead of the alerts list.
class NotificationDeepLink {
  const NotificationDeepLink({
    required this.dest,
    this.notificationType = '',
    this.peerId,
    this.groupId,
    this.taskId,
    this.projectId,
    this.callPayload,
    this.projectName = '',
  });

  final NotificationDest dest;
  final String notificationType;
  final int? peerId;
  final int? groupId;
  final int? taskId;
  final int? projectId;
  final String? callPayload;
  final String projectName;

  static int? asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v > 0 ? v : null;
    if (v is num) {
      final n = v.round();
      return n > 0 ? n : null;
    }
    final n = int.tryParse('$v');
    return n != null && n > 0 ? n : null;
  }

  static String encodeFromData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    var notifType = data['notification_type']?.toString() ?? '';
    if (type == 'task_notification' && notifType.isEmpty) {
      notifType = 'task_assigned';
    }
    if (type == 'call_invite' || notifType == 'call_invite') {
      return CallNotification.encode(
        callId: data['call_id']?.toString() ?? '',
        callerId: asInt(data['caller_id'] ?? data['sender_id']) ?? 0,
        callType: data['call_type']?.toString() == 'video' ? 'video' : 'audio',
        callerName: data['caller_name']?.toString() ??
            data['sender_name']?.toString() ??
            'Incoming call',
      );
    }

    if (_isChatType(notifType)) {
      final chat = ChatNotification.fromData(data);
      return ChatNotification.encode(
        name: chat.name,
        peerId: chat.peerId,
        groupId: chat.groupId,
        notificationType: notifType,
      );
    }

    return jsonEncode({
      'kind': 'notif',
      'notification_type': notifType,
      'object_id': data['object_id'],
      'object_type': data['object_type'],
      'task_id': data['task_id'] ?? data['task'],
      'project_id': data['project_id'] ?? data['project'],
      'sender_id': data['sender_id'],
      'peer_id': data['peer_id'] ?? data['user_id'],
      'group_id': data['group_id'],
      'link': data['link'],
      'title': data['title'],
      'message': data['message'] ?? data['body'],
    });
  }

  static NotificationDeepLink parse(String? payload, {Map<String, dynamic>? data}) {
    if (data != null && data.isNotEmpty) {
      return fromData(data);
    }
    if (payload == null || payload.isEmpty || payload == 'alerts') {
      return const NotificationDeepLink(dest: NotificationDest.alerts);
    }
    if (CallNotification.isCallPayload(payload)) {
      return NotificationDeepLink(
        dest: NotificationDest.call,
        notificationType: 'call_invite',
        callPayload: payload,
      );
    }
    if (ChatNotification.isChatPayload(payload) || payload == 'chat') {
      final chat = ChatNotification.parse(payload);
      return NotificationDeepLink(
        dest: NotificationDest.chat,
        notificationType: chat?['notification_type']?.toString() ?? 'new_message',
        peerId: asInt(chat?['peer_id']),
        groupId: asInt(chat?['group_id']),
      );
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return fromData(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return const NotificationDeepLink(dest: NotificationDest.alerts);
  }

  static NotificationDeepLink fromData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    var notifType = data['notification_type']?.toString() ?? '';
    if (type == 'task_notification' && notifType.isEmpty) {
      notifType = 'task_assigned';
    }
    if (type == 'call_invite' || notifType == 'call_invite') {
      return NotificationDeepLink(
        dest: NotificationDest.call,
        notificationType: 'call_invite',
        callPayload: jsonEncode(data),
        peerId: asInt(data['caller_id'] ?? data['sender_id']),
      );
    }

    if (_isChatType(notifType)) {
      final chat = ChatNotification.fromData(data);
      return NotificationDeepLink(
        dest: NotificationDest.chat,
        notificationType: notifType,
        peerId: chat.peerId,
        groupId: chat.groupId,
      );
    }

    final objectType = data['object_type']?.toString().toLowerCase() ?? '';
    final objectId = asInt(data['object_id']);
    final link = data['link']?.toString() ?? '';
    var taskId = asInt(data['task_id'] ?? data['task']);
    var projectId = asInt(data['project_id'] ?? data['project']);

    if (taskId == null && (objectType == 'task' || objectType == 'subtask')) {
      taskId = objectId;
    }
    if (projectId == null && objectType == 'project') {
      projectId = objectId;
    }

    final taskMatch = RegExp(r'tasks?/(\d+)', caseSensitive: false).firstMatch(link);
    if (taskId == null && taskMatch != null) {
      taskId = int.tryParse(taskMatch.group(1)!);
    }
    final projectMatch =
        RegExp(r'projects?/(\d+)|/monitor/project/(\d+)', caseSensitive: false)
            .firstMatch(link);
    if (projectId == null && projectMatch != null) {
      projectId = int.tryParse(projectMatch.group(1) ?? projectMatch.group(2) ?? '');
    }

    if (taskId != null || _isTaskType(notifType)) {
      return NotificationDeepLink(
        dest: taskId != null ? NotificationDest.task : NotificationDest.myTasks,
        notificationType: notifType,
        taskId: taskId,
        projectId: projectId,
      );
    }
    if (projectId != null || _isProjectType(notifType)) {
      return NotificationDeepLink(
        dest: projectId != null ? NotificationDest.project : NotificationDest.alerts,
        notificationType: notifType,
        projectId: projectId,
        projectName: data['title']?.toString() ?? '',
      );
    }
    if (notifType == 'closing_report_due' ||
        notifType == 'closing_report_dependency') {
      return NotificationDeepLink(
        dest: NotificationDest.report,
        notificationType: notifType,
      );
    }
    if (notifType.contains('vault')) {
      return const NotificationDeepLink(dest: NotificationDest.vault);
    }
    if (notifType == 'checkin' ||
        notifType == 'checkout' ||
        notifType == 'late_checkin' ||
        notifType == 'absent') {
      return const NotificationDeepLink(dest: NotificationDest.attendance);
    }

    return NotificationDeepLink(
      dest: NotificationDest.alerts,
      notificationType: notifType,
    );
  }

  static bool isChatType(String type) => _isChatType(type);

  static bool _isChatType(String type) {
    switch (type) {
      case 'new_message':
      case 'new_group_message':
      case 'mention':
      case 'group_added':
      case 'group_removed':
        return true;
      default:
        return false;
    }
  }

  static bool _isTaskType(String type) {
    return type.startsWith('task_') || type.startsWith('subtask_');
  }

  static bool _isProjectType(String type) {
    return type.startsWith('project_');
  }
}
