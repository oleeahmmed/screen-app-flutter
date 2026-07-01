import 'package:flutter/material.dart';

/// Icons and colors for backend `notification_type` values.
class NotificationUi {
  NotificationUi._();

  static IconData iconFor(String type) {
    switch (type) {
      case 'new_message':
      case 'new_group_message':
        return Icons.chat_bubble_rounded;
      case 'group_added':
      case 'employee_joined':
      case 'team_added':
        return Icons.person_add_rounded;
      case 'group_removed':
      case 'team_removed':
        return Icons.person_remove_rounded;
      case 'task_assigned':
      case 'subtask_assigned':
        return Icons.assignment_ind_rounded;
      case 'task_completed':
      case 'subtask_completed':
      case 'project_completed':
        return Icons.check_circle_rounded;
      case 'task_updated':
      case 'project_updated':
        return Icons.edit_note_rounded;
      case 'task_due_soon':
      case 'late_checkin':
        return Icons.schedule_rounded;
      case 'task_overdue':
      case 'absent':
      case 'subscription_expired':
        return Icons.warning_amber_rounded;
      case 'project_created':
        return Icons.create_new_folder_rounded;
      case 'checkin':
        return Icons.login_rounded;
      case 'checkout':
        return Icons.logout_rounded;
      case 'team_created':
        return Icons.groups_rounded;
      case 'team_deleted':
        return Icons.group_off_rounded;
      case 'invitation_received':
        return Icons.mail_rounded;
      case 'subscription_expiring':
        return Icons.event_busy_rounded;
      case 'video_ready':
        return Icons.movie_rounded;
      case 'announcement':
        return Icons.campaign_rounded;
      case 'closing_report_due':
      case 'closing_report_dependency':
        return Icons.assignment_late_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  static Color colorFor(String type) {
    switch (type) {
      case 'new_message':
      case 'new_group_message':
        return const Color(0xFF06B6D4);
      case 'task_assigned':
      case 'subtask_assigned':
        return const Color(0xFF8B5CF6);
      case 'task_completed':
      case 'subtask_completed':
      case 'project_completed':
      case 'checkin':
      case 'employee_joined':
        return const Color(0xFF10B981);
      case 'task_updated':
      case 'project_updated':
      case 'project_created':
        return const Color(0xFF3B82F6);
      case 'task_due_soon':
      case 'late_checkin':
      case 'closing_report_due':
      case 'subscription_expiring':
        return const Color(0xFFF59E0B);
      case 'task_overdue':
      case 'absent':
      case 'subscription_expired':
      case 'group_removed':
        return const Color(0xFFEF4444);
      case 'invitation_received':
        return const Color(0xFFEC4899);
      case 'announcement':
        return const Color(0xFF6366F1);
      case 'closing_report_dependency':
        return const Color(0xFFF97316);
      default:
        return const Color(0xFF64748B);
    }
  }
}
