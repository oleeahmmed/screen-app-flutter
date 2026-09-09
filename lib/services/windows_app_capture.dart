// Android branch — Windows foreground-window capture is not available.

class WindowsAppInfo {
  final String name;
  final String exe;
  final String title;

  const WindowsAppInfo({
    required this.name,
    required this.exe,
    required this.title,
  });

  factory WindowsAppInfo.fromJson(Map<String, dynamic> json) {
    return WindowsAppInfo(
      name: json['name']?.toString() ?? '',
      exe: json['exe']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'exe': exe, 'title': title};
}

abstract final class WindowsAppCapture {
  static Future<List<WindowsAppInfo>> listRunningApps() async => const [];
}
