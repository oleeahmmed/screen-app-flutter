/// Global tab switching from pushed routes (task detail, project detail, etc.).
class AppNavigation {
  AppNavigation._();

  static final AppNavigation instance = AppNavigation._();

  void Function(int index)? onSelectTab;
  Future<void> Function()? onOpenDailyReport;
  Future<void> Function()? onOpenActivity;
  Future<void> Function()? onOpenVault;
  Future<void> Function()? onLogout;

  void selectTab(int index) => onSelectTab?.call(index);

  void goHome() => selectTab(0);
  void goWork() => selectTab(1);
  void goChat() => selectTab(2);
  void goAlerts() => selectTab(3);
  void goProfile() => selectTab(4);

  Future<void> openDailyReport() async => await onOpenDailyReport?.call();

  Future<void> openActivity() async => await onOpenActivity?.call();

  Future<void> openVault() async => await onOpenVault?.call();

  Future<void> logout() async => onLogout?.call();
}
