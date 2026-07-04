/// Global tab switching from pushed routes (task detail, project detail, etc.).
class AppNavigation {
  AppNavigation._();

  static final AppNavigation instance = AppNavigation._();

  int selectedTabIndex = 0;
  int unreadNotifs = 0;

  void Function(int index)? onSelectTab;
  void Function(int index)? onNavigateToTab;
  Future<void> Function()? onOpenDailyReport;
  Future<void> Function()? onOpenActivity;
  Future<void> Function()? onOpenVault;
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

  void goHome() => navigateToTab(0);
  void goWork() => navigateToTab(1);
  void goChat() => navigateToTab(2);
  void goAlerts() => navigateToTab(3);
  void goProfile() => navigateToTab(4);

  Future<void> openDailyReport() async => await onOpenDailyReport?.call();

  Future<void> openActivity() async => await onOpenActivity?.call();

  Future<void> openVault() async => await onOpenVault?.call();

  Future<void> logout() async => onLogout?.call();
}
