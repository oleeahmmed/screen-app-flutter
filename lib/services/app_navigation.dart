/// Global tab switching from pushed routes (task detail, project detail, etc.).
class AppNavigation {
  AppNavigation._();

  static final AppNavigation instance = AppNavigation._();

  static const int tabHome = 0;
  static const int tabMyTasks = 1;
  static const int tabChat = 2;
  static const int tabVault = 3;
  static const int tabProject = 4;
  static const int tabCount = 5;

  /// @deprecated Notifications live in the top bar — use [openNotifications].
  static const int tabAlerts = tabVault;

  /// Profile is opened from the top bar (not a bottom tab).
  static const int tabProfile = -1;

  int selectedTabIndex = 0;
  int unreadNotifs = 0;
  int? pendingChatUserId;
  int? pendingChatGroupId;
  void Function()? onPendingChatOpen;

  void Function(int index)? onSelectTab;
  void Function(int index)? onNavigateToTab;
  Future<void> Function()? onOpenDailyReport;
  Future<void> Function()? onOpenActivity;
  Future<void> Function()? onOpenAttendanceReport;
  Future<void> Function()? onOpenVault;
  Future<void> Function()? onOpenProject;
  Future<void> Function()? onOpenP2P;
  Future<void> Function()? onOpenSubmitReport;
  Future<void> Function()? onOpenNotifications;
  Future<void> Function()? onOpenProfile;
  Future<void> Function()? onLogout;

  void selectTab(int index) => onSelectTab?.call(index);

  /// Pop stacked routes (task detail, tools) then switch main tab.
  void navigateToTab(int index) {
    if (index < 0 || index >= tabCount) return;
    if (onNavigateToTab != null) {
      onNavigateToTab!(index);
    } else {
      selectTab(index);
    }
  }

  void goHome() => navigateToTab(tabHome);
  void goMyTasks() => navigateToTab(tabMyTasks);
  void goChat() => navigateToTab(tabChat);

  void goChatWithPeer({int? userId, int? groupId}) {
    pendingChatUserId = userId;
    pendingChatGroupId = groupId;
    goChat();
    onPendingChatOpen?.call();
  }
  void goVault() => navigateToTab(tabVault);
  void goProject() => navigateToTab(tabProject);

  /// Opens profile from the top bar.
  void goProfile() => openProfile();

  /// Opens notifications (top-bar action — not a bottom tab).
  void goAlerts() => openNotifications();

  Future<void> openDailyReport() async => await onOpenDailyReport?.call();

  Future<void> openActivity() async => await onOpenActivity?.call();

  Future<void> openAttendanceReport() async => await onOpenAttendanceReport?.call();

  Future<void> openVault() async => await onOpenVault?.call();

  Future<void> openProject() async => await onOpenProject?.call();

  Future<void> openP2P() async => await onOpenP2P?.call();

  Future<void> openSubmitReport() async => await onOpenSubmitReport?.call();

  Future<void> openNotifications() async => await onOpenNotifications?.call();

  Future<void> openProfile() async => await onOpenProfile?.call();

  Future<void> logout() async {
    final fn = onLogout;
    if (fn != null) await fn();
  }
}
