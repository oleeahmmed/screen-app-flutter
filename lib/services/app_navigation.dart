/// Global tab switching from pushed routes (task detail, project detail, etc.).
class AppNavigation {
  AppNavigation._();

  static final AppNavigation instance = AppNavigation._();

  static const int tabHome = 0;
  static const int tabMyTasks = 1;
  static const int tabChat = 2;
  static const int tabAlerts = 3;
  static const int tabProfile = 4;
  static const int tabCount = 5;

  int selectedTabIndex = 0;
  int unreadNotifs = 0;

  void Function(int index)? onSelectTab;
  void Function(int index)? onNavigateToTab;
  Future<void> Function()? onOpenDailyReport;
  Future<void> Function()? onOpenActivity;
  Future<void> Function()? onOpenAttendanceReport;
  Future<void> Function()? onOpenVault;
  Future<void> Function()? onOpenProject;
  Future<void> Function()? onOpenP2P;
  Future<void> Function()? onOpenSubmitReport;
  Future<void> Function()? onLogout;

  void selectTab(int index) => onSelectTab?.call(index);

  /// Pop stacked routes (task detail, tools) then switch main tab.
  void navigateToTab(int index) {
    if (onNavigateToTab != null) {
      onNavigateToTab!(index);
    } else {
      selectTab(index);
    }
  }

  void goHome() => navigateToTab(tabHome);
  void goMyTasks() => navigateToTab(tabMyTasks);
  void goChat() => navigateToTab(tabChat);
  void goAlerts() => navigateToTab(tabAlerts);
  void goProfile() => navigateToTab(tabProfile);

  /// Opens project list as a pushed screen (not a bottom tab).
  Future<void> goProject() async => await openProject();

  /// @deprecated Use [goProject].
  void goWork() => goProject();

  Future<void> openDailyReport() async => await onOpenDailyReport?.call();

  Future<void> openActivity() async => await onOpenActivity?.call();

  Future<void> openAttendanceReport() async => await onOpenAttendanceReport?.call();

  Future<void> openVault() async => await onOpenVault?.call();

  Future<void> openProject() async => await onOpenProject?.call();

  Future<void> openP2P() async => await onOpenP2P?.call();

  Future<void> openSubmitReport() async => await onOpenSubmitReport?.call();

  Future<void> logout() async => onLogout?.call();
}
