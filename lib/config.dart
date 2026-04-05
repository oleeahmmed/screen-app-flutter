// config.dart — build-time overrides: --dart-define=API_ORIGIN=https://api.example.com

class AppConfig {
  static const String _apiOrigin = String.fromEnvironment(
    'API_ORIGIN',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const int screenshotInterval = int.fromEnvironment(
    'SCREENSHOT_INTERVAL_SEC',
    defaultValue: 30,
  );

  /// Must match Django `DATA_PRIVACY_NOTICE_VERSION` — bump both when notice text changes.
  static const int dataPrivacyNoticeVersion = int.fromEnvironment(
    'DATA_PRIVACY_NOTICE_VERSION',
    defaultValue: 1,
  );

  static String get apiBaseUrl {
    final base = _apiOrigin.endsWith('/') ? _apiOrigin.substring(0, _apiOrigin.length - 1) : _apiOrigin;
    return '$base/api';
  }

  static String get wsBaseUri {
    final u = Uri.parse(_apiOrigin);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    final port = u.hasPort ? ':${u.port}' : '';
    return '$scheme://${u.host}$port';
  }

  static String get screenshotUploadUrl => '$apiBaseUrl/screenshots/upload/';
  static String get checkInUrl => '$apiBaseUrl/attendance/checkin/';
  static String get checkOutUrl => '$apiBaseUrl/attendance/checkout/';
  static String get tasksUrl => '$apiBaseUrl/tasks/';
  static String get chatUsersUrl => '$apiBaseUrl/chat/users/';
  static String get chatConversationUrl => '$apiBaseUrl/chat/conversation/';
  static String get chatSendUrl => '$apiBaseUrl/chat/send/';
  static String get chatUnreadUrl => '$apiBaseUrl/chat/unread/';
  static String get chatMarkReadUrl => '$apiBaseUrl/chat/mark-read/';
  static String get chatOnlineUrl => '$apiBaseUrl/chat/online/';
  static String get chatMessageDetailUrl => '$apiBaseUrl/chat/messages/';
  static String get chatGroupsUrl => '$apiBaseUrl/chat/groups/';
  static String get profileUrl => '$apiBaseUrl/user/profile/';
  static String get uploadPhotoUrl => '$apiBaseUrl/user/upload-photo/';
  static String get accessCheckUrl => '$apiBaseUrl/access-check/';
  static String get privacyNoticeAcceptUrl => '$apiBaseUrl/privacy-notice/accept/';

  static String get notificationsUrl => '$apiBaseUrl/notifications/';
  static String get notificationsUnreadUrl => '$apiBaseUrl/notifications/unread-count/';
  static String get notificationsMarkAllReadUrl => '$apiBaseUrl/notifications/mark-all-read/';
  static String get notificationsClearUrl => '$apiBaseUrl/notifications/clear/';

  static String get companyDashboardUrl => '$apiBaseUrl/company/';
  static String get companySettingsUrl => '$apiBaseUrl/company/settings/';
  static String get subscriptionUsageUrl => '$apiBaseUrl/company/subscription/usage/';
  static String get companyEmployeesUrl => '$apiBaseUrl/company/employees/';
  static String get companyTeamsUrl => '$apiBaseUrl/company/teams/';
  static String get companyInvitationsUrl => '$apiBaseUrl/company/invitations/';

  static String get plansUrl => '$apiBaseUrl/plans/';
  static String get registerUrl => '$apiBaseUrl/register/';

  static String get projectsUrl => '$apiBaseUrl/projects/';
  static String get projectsMetaUrl => '$apiBaseUrl/projects/meta/';
  static String projectArchiveUrl(int projectId) => '$apiBaseUrl/projects/$projectId/archive/';
  static String projectRestoreUrl(int projectId) => '$apiBaseUrl/projects/$projectId/restore/';

  static String get p2pCreateSessionUrl => '$apiBaseUrl/p2p/session/create/';
  static String get p2pJoinSessionUrl => '$apiBaseUrl/p2p/session/join/';
  static String get p2pSessionDetailUrl => '$apiBaseUrl/p2p/session/';
  static String get p2pWsUrl => '$wsBaseUri/ws/p2p/';
}
