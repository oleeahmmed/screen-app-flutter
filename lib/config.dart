// config.dart — build-time overrides: --dart-define=API_ORIGIN=http://127.0.0.1:8000

class AppConfig {
  static const String _apiOrigin = String.fromEnvironment(
    'API_ORIGIN',
    defaultValue: 'https://aims.igenhr.com',
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

  /// JWT login (`/api/auth/login/` or legacy `/api/token/`).
  static String get authLoginUrl => '$apiBaseUrl/auth/login/';
  static String get authTokenUrl => '$apiBaseUrl/token/';
  static String get authRefreshUrl => '$apiBaseUrl/auth/refresh/';
  static String get authTokenRefreshUrl => '$apiBaseUrl/token/refresh/';
  static String get authAccessCheckUrl => '$apiBaseUrl/auth/access-check/';

  /// Build ws/wss URL string (no implicit :0 port — fixes Windows WebSocket).
  static String _wsUrl(String path, Map<String, String> query) {
    final u = Uri.parse(_apiOrigin);
    final secure = u.scheme == 'https' || u.scheme == 'wss';
    final scheme = secure ? 'wss' : 'ws';
    final defaultPort = secure ? 443 : 80;
    final port = u.hasPort && u.port > 0 ? u.port : defaultPort;
    final portSuffix = port != defaultPort ? ':$port' : '';
    final q = query.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$scheme://${u.host}$portSuffix$path?$q';
  }

  static String get wsBaseUri {
    final u = Uri.parse(_apiOrigin);
    final secure = u.scheme == 'https' || u.scheme == 'wss';
    final scheme = secure ? 'wss' : 'ws';
    final defaultPort = secure ? 443 : 80;
    final port = u.hasPort && u.port > 0 ? u.port : defaultPort;
    final portSuffix = port != defaultPort ? ':$port' : '';
    return '$scheme://${u.host}$portSuffix';
  }

  /// WebSocket for chat + personal notifications (JWT via query string).
  static String chatWsUrl(String token) =>
      _wsUrl('/ws/chat/', {'token': token});

  static Uri chatWsUri(String token) => Uri.parse(chatWsUrl(token));

  static String p2pWsUrl(String sessionId, String token) =>
      _wsUrl('/ws/p2p/$sessionId/', {'token': token});

  static Uri p2pWsUri(String sessionId, String token) =>
      Uri.parse(p2pWsUrl(sessionId, token));

  static String get screenshotUploadUrl => '$apiBaseUrl/screenshots/upload/';
  static String get checkInUrl => '$apiBaseUrl/attendance/checkin/';
  static String get checkOutUrl => '$apiBaseUrl/attendance/checkout/';
  static String get tasksUrl => '$apiBaseUrl/tasks/';
  static String get chatUsersUrl => '$apiBaseUrl/chat/users/';
  static String get chatConversationUrl => '$apiBaseUrl/chat/conversation/';
  static String get chatSendUrl => '$apiBaseUrl/chat/send/';
  static String get chatUnreadUrl => '$apiBaseUrl/chat/unread-count/';
  static String get chatMarkReadUrl => '$apiBaseUrl/chat/mark-read/';
  static String get chatOnlineUrl => '$apiBaseUrl/chat/online-users/';
  static String get chatMessageDetailUrl => '$apiBaseUrl/chat/messages/';
  static String get chatGroupsUrl => '$apiBaseUrl/chat/groups/';
  static String get profileUrl => '$apiBaseUrl/user/profile/';
  static String get uploadPhotoUrl => '$apiBaseUrl/user/upload-photo/';
  /// Primary access-check path; legacy alias at [/access-check/](accessCheckLegacyUrl).
  static String get accessCheckUrl => authAccessCheckUrl;
  static String get accessCheckLegacyUrl => '$apiBaseUrl/access-check/';

  static String employeeProjectsUrl(String employeeId) =>
      '$apiBaseUrl/employees/$employeeId/projects/';
  static String employeeTasksUrl(String employeeId) =>
      '$apiBaseUrl/employees/$employeeId/tasks/';
  static String userProjectsUrl(String userId) => '$apiBaseUrl/users/$userId/projects/';
  static String userTasksUrl(String userId) => '$apiBaseUrl/users/$userId/tasks/';

  static String projectTasksUrl(int projectId) => '$apiBaseUrl/projects/$projectId/tasks/';
  static String projectTaskUrl(int projectId, int taskId) =>
      '$apiBaseUrl/projects/$projectId/tasks/$taskId/';
  static String projectTaskMoveUrl(int projectId, int taskId) =>
      '$apiBaseUrl/projects/$projectId/tasks/$taskId/move/';
  static String projectTaskCompleteUrl(int projectId, int taskId) =>
      '$apiBaseUrl/projects/$projectId/tasks/$taskId/complete/';
  static String projectTaskReopenUrl(int projectId, int taskId) =>
      '$apiBaseUrl/projects/$projectId/tasks/$taskId/reopen/';
  static String projectSubtasksUrl(int projectId, int taskId) =>
      '$apiBaseUrl/projects/$projectId/tasks/$taskId/subtasks/';
  static String projectSubtaskUrl(int projectId, int taskId, int subtaskId) =>
      '$apiBaseUrl/projects/$projectId/tasks/$taskId/subtasks/$subtaskId/';
  static String projectTaskActivityUrl(int projectId, int taskId) =>
      '$apiBaseUrl/projects/$projectId/tasks/$taskId/activity/';
  static String get privacyNoticeAcceptUrl => '$apiBaseUrl/auth/privacy-notice/accept/';
  static String get privacyNoticeAcceptLegacyUrl => '$apiBaseUrl/privacy-notice/accept/';

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
  static String get p2pIceServersUrl => '$apiBaseUrl/p2p/ice-servers/';
  static String get p2pWsPathPrefix => '/ws/p2p/';

  static String get breaksStartUrl => '$apiBaseUrl/breaks/start/';
  static String get breaksBackUrl => '$apiBaseUrl/breaks/back/';
  static String get breaksStatusUrl => '$apiBaseUrl/breaks/status/';
  static String get breaksMyBreaksUrl => '$apiBaseUrl/breaks/my-breaks/';

  static String get attendanceCurrentUrl => '$apiBaseUrl/attendance/current/';
  static String get attendanceListUrl => '$apiBaseUrl/attendance/';
  static String get closingReportsUrl => '$apiBaseUrl/closing-reports/';
  static String get closingReportsPendingUrl => '$apiBaseUrl/closing-reports/pending/';

  // Project vault (credentials per project)
  static String vaultCategoriesUrl(int projectId) =>
      '$apiBaseUrl/projects/$projectId/vault/categories/';
  static String vaultCategoryUrl(int projectId, int categoryId) =>
      '$apiBaseUrl/projects/$projectId/vault/categories/$categoryId/';
  static String vaultEntriesUrl(int projectId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/';
  static String vaultEntryUrl(int projectId, int entryId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/$entryId/';
  static String vaultEntryRevealUrl(int projectId, int entryId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/$entryId/reveal/';
  static String vaultEntryCopyFieldUrl(int projectId, int entryId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/$entryId/copy-field/';
  static String vaultEntryHidePasswordUrl(int projectId, int entryId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/$entryId/hide-password/';
  static String vaultEntryAttachmentUrl(int projectId, int entryId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/$entryId/attachments/add/';
  static String vaultEntryShareUrl(int projectId, int entryId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/$entryId/share/';
  static String vaultEntrySharesUrl(int projectId, int entryId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/$entryId/shares/';
  static String vaultShareDetailUrl(int projectId, int entryId, int shareId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/$entryId/shares/$shareId/';
  static String vaultActivityUrl(int projectId) =>
      '$apiBaseUrl/projects/$projectId/vault/activity/';
  static String vaultEntryActivityUrl(int projectId, int entryId) =>
      '$apiBaseUrl/projects/$projectId/vault/entries/$entryId/activity/';
  static String get vaultContextCustomersUrl =>
      '$apiBaseUrl/projects/vault/context/customers/';
  static String vaultContextCustomerProjectsUrl(int customerId) =>
      '$apiBaseUrl/projects/vault/context/customers/$customerId/projects/';
}
