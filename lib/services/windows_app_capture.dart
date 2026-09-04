// windows_app_capture.dart — foreground-window capture for selected apps (Windows only)

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

class WindowsAppCaptureResult {
  final Uint8List bytes;
  final String exe;
  final String windowTitle;

  const WindowsAppCaptureResult({
    required this.bytes,
    required this.exe,
    required this.windowTitle,
  });
}

/// Win32 helpers via PowerShell — no extra native binary.
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

  /// Captures the foreground window when it matches [allowedApps]. Returns null if skipped.
  static Future<WindowsAppCaptureResult?> captureForegroundIfAllowed(
    List<WindowsAppInfo> allowedApps,
    String outputPath,
  ) async {
    if (!supported || allowedApps.isEmpty) return null;

    final sep = String.fromCharCode(0x1f);
    final allowedPacked = allowedApps
        .map((a) => '${_pack(a.exe)}$sep${_pack(a.title)}$sep${_pack(a.name)}')
        .join('|');
    final outPathEsc = outputPath.replaceAll("'", "''");

    final script = '''
\$allowedPacked = '$allowedPacked'
\$outPath = '$outPathEsc'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;
using System.Diagnostics;
using System.IO;
using System.Text;
public static class WinCap {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public class AppEntry { public string exe; public string title; public string name; }
  public static AppEntry[] ParseAllowed(string packed) {
    var list = new System.Collections.Generic.List<AppEntry>();
    if (string.IsNullOrWhiteSpace(packed)) return list.ToArray();
    foreach (var item in packed.Split(new char[]{'|'}, StringSplitOptions.RemoveEmptyEntries)) {
      var parts = item.Split(new char[]{(char)0x1f});
      if (parts.Length < 1) continue;
      list.Add(new AppEntry {
        exe = parts[0] ?? "",
        title = parts.Length > 1 ? parts[1] : "",
        name = parts.Length > 2 ? parts[2] : ""
      });
    }
    return list.ToArray();
  }
  public static string ForegroundExe(IntPtr hwnd) {
    if (hwnd == IntPtr.Zero) return "";
    uint pid;
    GetWindowThreadProcessId(hwnd, out pid);
    if (pid == 0) return "";
    try {
      var p = Process.GetProcessById((int)pid);
      try { return Path.GetFileName(p.MainModule.FileName); } catch { return p.ProcessName + ".exe"; }
    } catch { return ""; }
  }
  public static string ForegroundTitle(IntPtr hwnd) {
    var sb = new StringBuilder(512);
    GetWindowText(hwnd, sb, sb.Capacity);
    return sb.ToString() ?? "";
  }
  public static bool IsAllowed(string exe, string winTitle, AppEntry[] allowed) {
    if (allowed == null || allowed.Length == 0) return false;
    foreach (var a in allowed) {
      if (a == null) continue;
      var wantExe = (a.exe ?? "").Trim();
      if (wantExe.Length == 0) continue;
      if (string.Equals(exe, wantExe, StringComparison.OrdinalIgnoreCase)) return true;
      var wantBase = wantExe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
        ? wantExe.Substring(0, wantExe.Length - 4) : wantExe;
      if (string.Equals(exe, wantBase + ".exe", StringComparison.OrdinalIgnoreCase)) return true;
      var savedTitle = (a.title ?? "").Trim();
      if (savedTitle.Length > 0 && !string.IsNullOrWhiteSpace(winTitle)) {
        if (winTitle.IndexOf(savedTitle, StringComparison.OrdinalIgnoreCase) >= 0) return true;
        if (savedTitle.IndexOf(winTitle, StringComparison.OrdinalIgnoreCase) >= 0) return true;
      }
      var savedName = (a.name ?? "").Trim();
      if (savedName.Length > 0 && !string.IsNullOrWhiteSpace(winTitle)) {
        if (winTitle.IndexOf(savedName, StringComparison.OrdinalIgnoreCase) >= 0) return true;
      }
      if (string.Equals(exe, "ApplicationFrameHost.exe", StringComparison.OrdinalIgnoreCase)
          && (savedTitle.Length > 0 || savedName.Length > 0)) {
        if (!string.IsNullOrWhiteSpace(winTitle)) {
          if (savedTitle.Length > 0 && winTitle.IndexOf(savedTitle, StringComparison.OrdinalIgnoreCase) >= 0) return true;
          if (savedName.Length > 0 && winTitle.IndexOf(savedName, StringComparison.OrdinalIgnoreCase) >= 0) return true;
        }
      }
    }
    return false;
  }
  public static bool CaptureWindow(IntPtr hwnd, string outPath) {
    if (hwnd == IntPtr.Zero || IsIconic(hwnd)) return false;
    RECT r;
    if (!GetWindowRect(hwnd, out r)) return false;
    int w = r.Right - r.Left, h = r.Bottom - r.Top;
    if (w <= 4 || h <= 4) return false;
    using (var bmp = new Bitmap(w, h)) {
      bool gotPixels = false;
      using (var g = Graphics.FromImage(bmp)) {
        g.Clear(Color.Black);
        IntPtr hdc = g.GetHdc();
        try {
          if (PrintWindow(hwnd, hdc, 2)) gotPixels = true;
          else if (PrintWindow(hwnd, hdc, 0)) gotPixels = true;
          else if (PrintWindow(hwnd, hdc, 1)) gotPixels = true;
        } finally {
          g.ReleaseHdc(hdc);
        }
        if (!gotPixels) {
          try {
            g.CopyFromScreen(new Point(r.Left, r.Top), Point.Empty, new Size(w, h));
            gotPixels = true;
          } catch { gotPixels = false; }
        }
      }
      if (!gotPixels) return false;
      bmp.Save(outPath, ImageFormat.Png);
    }
    return File.Exists(outPath) && new FileInfo(outPath).Length > 512;
  }
  public static string Run(string packed, string outPath) {
    var allowed = ParseAllowed(packed);
    IntPtr hwnd = GetForegroundWindow();
    if (hwnd == IntPtr.Zero) return "SKIP:no foreground";
    var exe = ForegroundExe(hwnd);
    var title = ForegroundTitle(hwnd);
    if (!IsAllowed(exe, title, allowed)) return "SKIP:" + exe + "|" + title;
    if (!CaptureWindow(hwnd, outPath)) return "ERROR:capture failed";
    return "SUCCESS:" + exe + "|" + title;
  }
}
"@
try {
  \$result = [WinCap]::Run(\$allowedPacked, \$outPath)
  Write-Output \$result
} catch {
  Write-Output ("ERROR:" + \$_.Exception.Message)
}
''';

    final out = await _runPs(script);
    if (out == null || !out.startsWith('SUCCESS:')) {
      if (out != null && out.startsWith('SKIP:')) {
        // useful for debugging in screenshot_service
      }
      return null;
    }

    final meta = out.length > 8 ? out.substring(8) : '';
    final parts = meta.split('|');
    final file = File(outputPath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete().catchError((_) => file);
    if (bytes.isEmpty) return null;

    return WindowsAppCaptureResult(
      bytes: bytes,
      exe: parts.isNotEmpty ? parts.first : '',
      windowTitle: parts.length > 1 ? parts.sublist(1).join('|') : '',
    );
  }

  static String _pack(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('|', '\\|').replaceAll('\x1f', ' ');

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
      final stdout = result.stdout.toString().trim();
      if (stdout.isNotEmpty) return stdout.split('\n').last.trim();
      final stderr = result.stderr.toString().trim();
      if (stderr.isNotEmpty) return 'ERROR:$stderr';
      return null;
    } catch (e) {
      return 'ERROR:$e';
    }
  }
}
