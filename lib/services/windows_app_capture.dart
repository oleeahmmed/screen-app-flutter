// windows_app_capture.dart — lightweight foreground-window capture via PowerShell (Windows only)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Minimal Win32 helper — no extra native binary; reuses PowerShell like full-screen capture.
abstract final class WindowsAppCapture {
  static bool get supported => Platform.isWindows;

  static Future<List<WindowsAppInfo>> listRunningApps() async {
    if (!supported) return const [];

    const script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Diagnostics;
using System.Collections.Generic;
public static class WinApps {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll", SetLastError=true)] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  public static string ListJson() {
    var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    var items = new List<string>();
    EnumWindows((hWnd, lParam) => {
      if (!IsWindowVisible(hWnd)) return true;
      var sb = new StringBuilder(512);
      GetWindowText(hWnd, sb, sb.Capacity);
      var title = sb.ToString();
      if (string.IsNullOrWhiteSpace(title)) return true;
      uint pid;
      GetWindowThreadProcessId(hWnd, out pid);
      if (pid == 0) return true;
      try {
        var p = Process.GetProcessById((int)pid);
        var exe = "";
        try { exe = System.IO.Path.GetFileName(p.MainModule.FileName); } catch { exe = p.ProcessName + ".exe"; }
        var key = exe + "|" + title;
        if (seen.Add(key)) {
          var name = string.IsNullOrWhiteSpace(p.ProcessName) ? exe : p.ProcessName;
          items.Add("{\"name\":\"" + Escape(name) + "\",\"exe\":\"" + Escape(exe) + "\",\"title\":\"" + Escape(title) + "\"}");
        }
      } catch { }
      return true;
    }, IntPtr.Zero);
    return "[" + string.Join(",", items) + "]";
  }
  static string Escape(string s) {
    return (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"");
  }
}
"@
try {
  Write-Output ("JSON:" + [WinApps]::ListJson())
} catch {
  Write-Output ("ERROR:" + $_.Exception.Message)
}
''';

    final out = await _runPs(script);
    if (out == null || !out.startsWith('JSON:')) return const [];
    try {
      final raw = out.substring(5);
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => WindowsAppInfo.fromJson(Map<String, dynamic>.from(e)))
          .where((a) => a.exe.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      return const [];
    }
  }

  /// Captures foreground window when its exe is in [allowedExes]. Returns null if skipped.
  static Future<Uint8List?> captureForegroundIfAllowed(
    List<String> allowedExes,
    String outputPath,
  ) async {
    if (!supported || allowedExes.isEmpty) return null;

    final allowed = allowedExes.map((e) => e.toLowerCase()).toSet().join('|');
    final script = '''
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;
using System.Diagnostics;
using System.IO;
public static class WinCap {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static string ForegroundExe() {
    IntPtr hwnd = GetForegroundWindow();
    if (hwnd == IntPtr.Zero) return "";
    uint pid;
    GetWindowThreadProcessId(hwnd, out pid);
    if (pid == 0) return "";
    try {
      var p = Process.GetProcessById((int)pid);
      try { return Path.GetFileName(p.MainModule.FileName); } catch { return p.ProcessName + ".exe"; }
    } catch { return ""; }
  }
  public static bool Capture(string allowedCsv, string outPath) {
    var allowed = (allowedCsv ?? "").Split(new char[]{'|'}, StringSplitOptions.RemoveEmptyEntries);
    IntPtr hwnd = GetForegroundWindow();
    if (hwnd == IntPtr.Zero || IsIconic(hwnd)) return false;
    var exe = ForegroundExe();
    if (string.IsNullOrEmpty(exe)) return false;
    bool ok = false;
    foreach (var a in allowed) {
      if (string.Equals(exe, a.Trim(), StringComparison.OrdinalIgnoreCase)) { ok = true; break; }
    }
    if (!ok) return false;
    RECT r;
    if (!GetWindowRect(hwnd, out r)) return false;
    int w = r.Right - r.Left, h = r.Bottom - r.Top;
    if (w <= 0 || h <= 0) return false;
    using (var bmp = new Bitmap(w, h)) {
      using (var g = Graphics.FromImage(bmp)) {
        IntPtr hdc = g.GetHdc();
        PrintWindow(hwnd, hdc, 2);
        g.ReleaseHdc(hdc);
      }
      bmp.Save(outPath, ImageFormat.Png);
    }
    return File.Exists(outPath) && new FileInfo(outPath).Length > 0;
  }
}
"@
try {
  \$ok = [WinCap]::Capture('$allowed', '$outputPath')
  if (\$ok) { Write-Output "SUCCESS" } else { Write-Output "SKIP" }
} catch {
  Write-Output ("ERROR:" + \$_.Exception.Message)
}
''';

    final out = await _runPs(script);
    if (out != 'SUCCESS') return null;
    final file = File(outputPath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete().catchError((_) => file);
    return bytes.isEmpty ? null : bytes;
  }

  static Future<String?> _runPs(String script) async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-ExecutionPolicy',
          'Bypass',
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-Command',
          script,
        ],
        runInShell: false,
      );
      return result.stdout.toString().trim();
    } catch (_) {
      return null;
    }
  }
}
