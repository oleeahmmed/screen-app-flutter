// screenshot_service.dart — periodic screenshot upload (Windows, Linux, macOS)

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';
import 'activity_detection_service.dart';
import 'image_compress_util.dart';
import 'windows_app_capture.dart';
import '../config.dart';
import '../app_session.dart';
import '../utils/platform_capabilities.dart';

class ScreenshotService {
  /// Platforms with a working capture implementation (desktop only).
  static bool get isPlatformSupported => PlatformCapabilities.screenshotMonitoring;

  static String get platformLabel {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return Platform.operatingSystem;
  }
  final ApiService apiService;
  final ActivityDetectionService activityDetection = ActivityDetectionService();
  Timer? _screenshotTimer;
  Timer? _activityCheckTimer;
  bool _isRunning = false;
  int _captureCount = 0;
  DateTime _lastActivityTime = DateTime.now();
  bool _isUserActive = true;
  bool _appFilterMode = false;
  bool _captureInFlight = false;
  List<WindowsAppInfo> _allowedApps = const [];
  /// Last content hash successfully stored on the server, per screen.
  final Map<int, String> _lastUploadedHashByScreen = {};
  static const int idleThresholdSeconds = 60;
  static const bool enableDebugLogs = true;

  static const List<String> _linuxCaptureTools = [
    'grim',
    'gnome-screenshot',
    'spectacle',
    'scrot',
    'import',
    'maim',
  ];

  static const List<String> _linuxToolPaths = [
    '/usr/bin',
    '/usr/local/bin',
    '/bin',
    '/snap/bin',
  ];

  ScreenshotService(this.apiService);

  void _debugLog(String message) {
    if (enableDebugLogs) {
      print(message);
    }
  }

  void recordActivity() {
    if (AppSession.onBreak) return;
    _lastActivityTime = DateTime.now();
    if (!_isUserActive) {
      _isUserActive = true;
      _updateActivityStatus(true);
    }
  }

  Future<void> startCapture() async {
    _appFilterMode = false;
    _allowedApps = const [];
    await _startCaptureInternal();
  }

  /// Capture only the foreground window when it matches [allowedApps] (Windows).
  Future<void> startAppFilterCapture(List<WindowsAppInfo> allowedApps) async {
    if (!Platform.isWindows) {
      _debugLog('App-filter capture is Windows-only');
      return;
    }
    final cleaned = allowedApps.where((a) => a.exe.trim().isNotEmpty).toList();
    if (cleaned.isEmpty) {
      _debugLog('App-filter capture skipped — no apps selected');
      return;
    }
    _appFilterMode = true;
    _allowedApps = cleaned;
    await _startCaptureInternal();
  }

  /// Backward-compatible entry when only exe names are known.
  Future<void> startAppFilterCaptureByExe(List<String> allowedExes) async {
    await startAppFilterCapture(
      allowedExes
          .map((e) => WindowsAppInfo(name: e, exe: e, title: ''))
          .toList(),
    );
  }

  Future<void> _startCaptureInternal() async {
    if (_isRunning) await stopCapture();
    if (AppSession.onBreak) {
      _debugLog('Screenshot capture skipped — user is on break');
      return;
    }
    if (!isPlatformSupported) {
      _debugLog('Screenshot capture not supported on ${Platform.operatingSystem}');
      return;
    }

    if (Platform.isLinux) {
      final hasTool = await _linuxCaptureToolAvailable();
      if (!hasTool) {
        _debugLog(
          'Linux screenshot skipped — install: sudo apt install gnome-screenshot grim scrot',
        );
        return;
      }
    }

    _isRunning = true;

    final interval = AppConfig.screenshotInterval.clamp(15, 600);
    final modeLabel = _appFilterMode ? 'app-window filter' : 'full monitor';
    _debugLog('Screenshot service started ($platformLabel · $modeLabel)');
    _debugLog('Capture interval: ${interval}s');
    if (_appFilterMode) {
      _debugLog('Allowed apps: ${_allowedApps.map((a) => a.exe).join(', ')}');
    }

    _screenshotTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      await _captureOnce();
    });

    _activityCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkActivityStatus();
    });

    unawaited(_captureOnce());
  }

  Future<void> _captureOnce() async {
    if (!_isRunning || _captureInFlight) return;
    if (!AppSession.mayCaptureScreenshots) {
      _debugLog('Screenshot skipped (no consent)');
      return;
    }

    _captureInFlight = true;
    try {
      _captureCount++;
      final frames = <Uint8List>[];

      if (Platform.isWindows && _appFilterMode) {
        final tempDir = await getTemporaryDirectory();
        final tempFile =
            '${tempDir.path}${Platform.pathSeparator}app_filter_${DateTime.now().millisecondsSinceEpoch}.png';
        final result = await WindowsAppCapture.captureForegroundIfAllowed(
          _allowedApps,
          tempFile,
        );
        if (result == null || result.bytes.isEmpty) {
          _debugLog('App-filter capture #$_captureCount skipped (foreground not in selected apps)');
          return;
        }
        _debugLog('App-filter capture #$_captureCount: ${result.exe} · ${result.windowTitle}');
        await _uploadImage(result.bytes, screenIndex: 1);
        return;
      }

      if (Platform.isWindows) {
        frames.addAll(await _captureWindowsPerMonitor());
      } else if (Platform.isLinux) {
        final one = await _captureLinuxNative();
        if (one != null && one.isNotEmpty) frames.add(one);
      } else if (Platform.isMacOS) {
        frames.addAll(await _captureMacOSPerDisplay());
      }

      if (frames.isEmpty) {
        _debugLog('Capture #$_captureCount failed');
        return;
      }

      _debugLog('Capture #$_captureCount: ${frames.length} screen(s)');
      // Upload each monitor as its own backend slot (date/screenN/…).
      for (var i = 0; i < frames.length; i++) {
        await _uploadImage(frames[i], screenIndex: i + 1);
      }
    } catch (e) {
      _debugLog('Capture error: $e');
    } finally {
      _captureInFlight = false;
    }
  }

  /// Capture each Windows monitor as its own image (not one stitched VirtualScreen).
  Future<List<Uint8List>> _captureWindowsPerMonitor() async {
    File? scriptFile;
    try {
      final tempDir = await getTemporaryDirectory();
      final sep = Platform.pathSeparator;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final prefix = '${tempDir.path}${sep}aims_cap_$stamp';
      scriptFile = File('${tempDir.path}${sep}aims_cap_$stamp.ps1');

      // Primary first, then left→right. Backend slots: screen1, screen2, …
      final psScript = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public class AimsDpi {
  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();
}
"@
  [AimsDpi]::SetProcessDPIAware() | Out-Null
} catch {}
try {
  \$screens = [System.Windows.Forms.Screen]::AllScreens |
    Sort-Object { -not \$_.Primary }, { \$_.Bounds.X }, { \$_.Bounds.Y }
  if (-not \$screens -or \$screens.Count -lt 1) {
    Write-Output "ERROR:No screens"
    exit 1
  }
  \$i = 0
  \$saved = New-Object System.Collections.Generic.List[int]
  foreach (\$screen in \$screens) {
    \$i++
    \$b = \$screen.Bounds
    if (\$b.Width -lt 1 -or \$b.Height -lt 1) { continue }
    \$bitmap = New-Object System.Drawing.Bitmap([int]\$b.Width, [int]\$b.Height)
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
    try {
      \$graphics.CopyFromScreen([int]\$b.X, [int]\$b.Y, 0, 0, \$bitmap.Size)
      \$out = "${prefix}_\$i.png"
      \$bitmap.Save(\$out, [System.Drawing.Imaging.ImageFormat]::Png)
      if (Test-Path -LiteralPath \$out) { [void]\$saved.Add(\$i) }
    } finally {
      \$graphics.Dispose()
      \$bitmap.Dispose()
    }
  }
  if (\$saved.Count -lt 1) {
    Write-Output "ERROR:No frames saved"
    exit 1
  }
  Write-Output ("SUCCESS:" + ([string]::Join(",", \$saved)))
} catch {
  Write-Output "ERROR:\$(\$_.Exception.Message)"
  exit 1
}
''';

      await scriptFile.writeAsString(psScript, flush: true);

      final result = await Process.run(
        'powershell',
        [
          '-ExecutionPolicy',
          'Bypass',
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-File',
          scriptFile.path,
        ],
        runInShell: false,
      );

      final out = result.stdout.toString().trim();
      final successLine = out
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.trim())
          .firstWhere((l) => l.startsWith('SUCCESS:'), orElse: () => '');

      if (result.exitCode != 0 || successLine.isEmpty) {
        _debugLog('Windows multi-monitor capture failed: $out');
        final legacy = await _captureWindowsVirtualScreen();
        return legacy == null ? <Uint8List>[] : <Uint8List>[legacy];
      }

      final ids = successLine
          .substring('SUCCESS:'.length)
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();

      final frames = <Uint8List>[];
      for (final i in ids) {
        final file = File('${prefix}_$i.png');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await file.delete().catchError((_) => file);
          if (bytes.isNotEmpty) frames.add(bytes);
        }
      }
      if (frames.isEmpty) {
        final legacy = await _captureWindowsVirtualScreen();
        return legacy == null ? <Uint8List>[] : <Uint8List>[legacy];
      }
      _debugLog('Windows captured ${frames.length} monitor(s)');
      return frames;
    } catch (e) {
      _debugLog('Windows per-monitor capture error: $e');
      final legacy = await _captureWindowsVirtualScreen();
      return legacy == null ? <Uint8List>[] : <Uint8List>[legacy];
    } finally {
      if (scriptFile != null) {
        await scriptFile.delete().catchError((_) => scriptFile!);
      }
    }
  }

  Future<Uint8List?> _captureWindowsVirtualScreen() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final sep = Platform.pathSeparator;
      final tempFile =
          '${tempDir.path}${sep}silent_capture_${DateTime.now().millisecondsSinceEpoch}.png';

      final psScript = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
  \$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
  \$bitmap = New-Object System.Drawing.Bitmap(\$bounds.Width, \$bounds.Height)
  \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
  \$graphics.CopyFromScreen(\$bounds.Location, [System.Drawing.Point]::Empty, \$bounds.Size)
  \$bitmap.Save('$tempFile', [System.Drawing.Imaging.ImageFormat]::Png)
  \$graphics.Dispose()
  \$bitmap.Dispose()
  if (Test-Path '$tempFile') {
    \$fileInfo = Get-Item '$tempFile'
    Write-Output "SUCCESS:\$(\$fileInfo.Length)"
  } else {
    Write-Output "ERROR:File not created"
  }
} catch {
  Write-Output "ERROR:\$(\$_.Exception.Message)"
}
''';

      final result = await Process.run(
        'powershell',
        [
          '-ExecutionPolicy',
          'Bypass',
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-Command',
          psScript,
        ],
        runInShell: false,
      );

      if (result.exitCode == 0 &&
          result.stdout.toString().startsWith('SUCCESS:')) {
        final file = File(tempFile);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await file.delete().catchError((_) => file);
          return bytes;
        }
      }
      return null;
    } catch (e) {
      _debugLog('Windows capture error: $e');
      return null;
    }
  }

  /// One PNG per macOS display (Display 1 → screen1, …).
  Future<List<Uint8List>> _captureMacOSPerDisplay() async {
    final frames = <Uint8List>[];
    try {
      final tempDir = await getTemporaryDirectory();
      final sep = Platform.pathSeparator;
      final stamp = DateTime.now().millisecondsSinceEpoch;

      for (var display = 1; display <= 8; display++) {
        final tempFile =
            '${tempDir.path}${sep}mac_cap_${stamp}_d$display.png';
        final result = await Process.run(
          'screencapture',
          ['-x', '-D', '$display', tempFile],
          runInShell: false,
        ).timeout(const Duration(seconds: 12));
        final file = File(tempFile);
        if (result.exitCode != 0 || !await file.exists()) {
          await file.delete().catchError((_) => file);
          if (display == 1) {
            // Fallback: whole desktop as a single frame
            final one = await _captureMacOS();
            return one == null ? <Uint8List>[] : <Uint8List>[one];
          }
          break;
        }
        final bytes = await file.readAsBytes();
        await file.delete().catchError((_) => file);
        if (bytes.isEmpty) {
          if (display == 1) {
            final one = await _captureMacOS();
            return one == null ? <Uint8List>[] : <Uint8List>[one];
          }
          break;
        }
        frames.add(bytes);
      }
      return frames;
    } catch (e) {
      _debugLog('macOS multi-display capture error: $e');
      final one = await _captureMacOS();
      return one == null ? <Uint8List>[] : <Uint8List>[one];
    }
  }

  Future<Uint8List?> _captureMacOS() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile =
          '${tempDir.path}${Platform.pathSeparator}mac_capture_${DateTime.now().millisecondsSinceEpoch}.png';
      final result = await Process.run(
        'screencapture',
        ['-x', tempFile],
        runInShell: false,
      ).timeout(const Duration(seconds: 12));
      if (result.exitCode != 0) return null;

      final file = File(tempFile);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await file.delete().catchError((_) => file);
        if (bytes.isNotEmpty) return bytes;
      }
      return null;
    } catch (e) {
      _debugLog('macOS capture error: $e');
      return null;
    }
  }

  Future<Uint8List?> _captureLinuxNative() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile =
          '${tempDir.path}${Platform.pathSeparator}linux_capture_${DateTime.now().millisecondsSinceEpoch}.png';
      final wayland = _linuxIsWayland;

      // X11: maim/scrot are silent (no portal, no flash).
      // Wayland + GNOME: those grab a black XWayland root — skip them.
      final tools = <List<String>>[
        if (!wayland) ...[
          ['maim', tempFile],
          ['scrot', '--silent', tempFile],
          ['scrot', tempFile],
          ['import', '-window', 'root', tempFile],
          ['xwd', '-root', '-out', tempFile.replaceAll('.png', '.xwd')],
        ],
        // No portal dialog (GTK_USE_PORTAL=0). gnome-screenshot may still flash.
        ['gnome-screenshot', '-f', tempFile],
        ['spectacle', '-b', '-n', '-o', tempFile],
        ['grim', tempFile],
      ];
      for (final tool in tools) {
        try {
          final exe = tool[0];
          final resolved = await _resolveCommand(exe);
          if (resolved == null) continue;
          final args = tool.sublist(1);
          final env = Map<String, String>.from(Platform.environment);
          if (exe == 'gnome-screenshot') {
            env['GTK_USE_PORTAL'] = '0';
          }
          ProcessResult result;
          try {
            result = await Process.run(
              resolved,
              args,
              runInShell: false,
              environment: env,
            ).timeout(const Duration(seconds: 8));
          } on TimeoutException {
            _debugLog('Linux capture timeout: $exe');
            continue;
          }
          if (result.exitCode != 0) continue;

          var readPath = tempFile;
          if (exe == 'xwd') {
            readPath = tempFile.replaceAll('.png', '.xwd');
            final convert = await _resolveCommand('convert');
            if (convert != null) {
              final pngPath = tempFile;
              final conv = await Process.run(convert, [readPath, pngPath]);
              if (conv.exitCode == 0) {
                await File(readPath).delete().catchError((_) => File(readPath));
                readPath = pngPath;
              }
            }
          }

          final file = File(readPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            await file.delete().catchError((_) => file);
            if (_isUsableCapture(bytes)) return bytes;
            _debugLog('Linux capture discarded (blank): $exe');
          }
        } catch (_) {}
      }
      _debugLog('Linux: install maim (Xorg) or gnome-screenshot for capture');
      return null;
    } catch (e) {
      _debugLog('Linux capture error: $e');
      return null;
    }
  }

  bool get _linuxIsWayland {
    final session = Platform.environment['XDG_SESSION_TYPE']?.toLowerCase();
    if (session == 'wayland') return true;
    if (session == 'x11') return false;
    return (Platform.environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;
  }

  /// Black XWayland roots are tiny; a real desktop PNG is much larger.
  bool _isUsableCapture(Uint8List bytes) {
    if (bytes.length < 24 * 1024) return false;
    return true;
  }

  Future<bool> _linuxCaptureToolAvailable() async {
    for (final tool in _linuxCaptureTools) {
      if (await _commandExists(tool)) return true;
    }
    return false;
  }

  Future<bool> _commandExists(String command) async {
    try {
      final result = await Process.run('which', [command], runInShell: false);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return true;
      }
    } catch (_) {}
    if (command.contains('/')) {
      try {
        return await File(command).exists();
      } catch (_) {
        return false;
      }
    }
    for (final dir in _linuxToolPaths) {
      try {
        if (await File('$dir/$command').exists()) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<String?> _resolveCommand(String command) async {
    if (command.contains('/')) return command;
    for (final dir in _linuxToolPaths) {
      final path = '$dir/$command';
      try {
        if (await File(path).exists()) return path;
      } catch (_) {}
    }
    try {
      final result = await Process.run('which', [command], runInShell: false);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _uploadImage(Uint8List imageBytes, {int screenIndex = 1}) async {
    try {
      final activityStatus = activityDetection.analyzeScreenshot(
        imageBytes,
        screenIndex: screenIndex,
      );
      final unchanged = activityStatus['unchanged'] == true;
      final contentHash = (activityStatus['content_hash'] ?? '').toString();
      final isIdle = activityStatus['is_idle'] == true;
      final idleDuration = activityStatus['idle_duration'] as int? ?? 0;
      final lastActivityAt = activityStatus['last_activity_at']?.toString();

      if (isIdle) {
        _isUserActive = false;
      } else {
        _isUserActive = true;
      }

      // Same pixels as last successful upload → heartbeat only (no duplicate file).
      if (unchanged &&
          contentHash.isNotEmpty &&
          _lastUploadedHashByScreen[screenIndex] == contentHash) {
        final beat = await apiService.screenshotHeartbeat(
          isIdle: isIdle,
          idleDuration: idleDuration,
          lastActivityAt: lastActivityAt,
          screenIndex: screenIndex,
        );
        if (beat['success'] == true) {
          _debugLog(
            'Heartbeat screen $screenIndex (unchanged · ${isIdle ? "idle" : "active"})',
          );
          return;
        }
        // No prior shot on server — fall through to real upload.
        if ((beat['code'] ?? '').toString() != 'NO_SCREENSHOT') {
          _debugLog('Heartbeat failed (screen $screenIndex): ${beat['error']} — uploading frame');
        }
      }

      final uploadBytes = compressToJpeg(imageBytes, maxWidth: 1280, quality: 72);
      final result = await apiService.uploadScreenshot(
        uploadBytes,
        isIdle: isIdle,
        idleDuration: idleDuration,
        lastActivityAt: lastActivityAt,
        screenIndex: screenIndex,
      );

      if (result['success'] == true) {
        if (contentHash.isNotEmpty) {
          _lastUploadedHashByScreen[screenIndex] = contentHash;
        }
        _debugLog(
          'Uploaded screen $screenIndex ${(uploadBytes.length / 1024).toStringAsFixed(0)}KB',
        );
      } else {
        _debugLog('Upload failed (screen $screenIndex): ${result['error']}');
      }
    } catch (e) {
      _debugLog('Upload error: $e');
    }
  }

  Future<void> stopCapture() async {
    _isRunning = false;
    _captureInFlight = false;
    _appFilterMode = false;
    _allowedApps = const [];
    _lastUploadedHashByScreen.clear();
    activityDetection.reset();
    _screenshotTimer?.cancel();
    _activityCheckTimer?.cancel();
    _debugLog('Screenshot service stopped');
  }

  void _checkActivityStatus() {
    if (AppSession.onBreak) return;
    final secondsSince = DateTime.now().difference(_lastActivityTime).inSeconds;
    if (secondsSince > idleThresholdSeconds && _isUserActive) {
      _isUserActive = false;
      _updateActivityStatus(false);
    } else if (secondsSince <= idleThresholdSeconds && !_isUserActive) {
      _isUserActive = true;
      _updateActivityStatus(true);
    }
  }

  Future<void> _updateActivityStatus(bool isActive) async {
    try {
      await apiService.updateActivityStatus(isActive);
    } catch (_) {}
  }

  bool get isRunning => _isRunning;
  bool get isAppFilterMode => _appFilterMode;
  bool get isUserActive => _isUserActive;
  int get displayCount => Platform.isWindows ? -1 : 1;
}
