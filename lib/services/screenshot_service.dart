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
  List<String> _allowedAppExes = const [];
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
    _allowedAppExes = const [];
    await _startCaptureInternal();
  }

  /// Option B — capture only the foreground window when it matches [allowedExes].
  Future<void> startAppFilterCapture(List<String> allowedExes) async {
    if (!Platform.isWindows) {
      _debugLog('App-filter capture is Windows-only');
      return;
    }
    final cleaned = allowedExes.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (cleaned.isEmpty) {
      _debugLog('App-filter capture skipped — no apps selected');
      return;
    }
    _appFilterMode = true;
    _allowedAppExes = cleaned;
    await _startCaptureInternal();
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
      _debugLog('Allowed apps: ${_allowedAppExes.join(', ')}');
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
    if (!_isRunning) return;
    if (!AppSession.mayCaptureScreenshots) {
      _debugLog('Screenshot skipped (no consent)');
      return;
    }

    try {
      _captureCount++;
      final frames = <Uint8List>[];

      if (Platform.isWindows && _appFilterMode) {
        final tempDir = await getTemporaryDirectory();
        final tempFile =
            '${tempDir.path}${Platform.pathSeparator}app_filter_${DateTime.now().millisecondsSinceEpoch}.png';
        final frame = await WindowsAppCapture.captureForegroundIfAllowed(
          _allowedAppExes,
          tempFile,
        );
        if (frame == null || frame.isEmpty) {
          _debugLog('App-filter capture #$_captureCount skipped (foreground not allowed)');
          return;
        }
        _debugLog('App-filter capture #$_captureCount: window captured');
        await _uploadImage(frame, screenIndex: 1);
        return;
      }

      if (Platform.isWindows) {
        frames.addAll(await _captureWindowsPerMonitor());
      } else if (Platform.isLinux) {
        final one = await _captureLinuxNative();
        if (one != null && one.isNotEmpty) frames.add(one);
      } else if (Platform.isMacOS) {
        final one = await _captureMacOS();
        if (one != null && one.isNotEmpty) frames.add(one);
      }

      if (frames.isEmpty) {
        _debugLog('Capture #$_captureCount failed');
        return;
      }

      _debugLog('Capture #$_captureCount: ${frames.length} screen(s)');
      for (var i = 0; i < frames.length; i++) {
        await _uploadImage(frames[i], screenIndex: i + 1);
      }
    } catch (e) {
      _debugLog('Capture error: $e');
    }
  }

  /// Capture each Windows monitor as its own image (not one stitched VirtualScreen).
  Future<List<Uint8List>> _captureWindowsPerMonitor() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final sep = Platform.pathSeparator;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final prefix = '${tempDir.path}${sep}aims_cap_$stamp';

      final psScript = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
  \$screens = [System.Windows.Forms.Screen]::AllScreens
  if (-not \$screens -or \$screens.Count -lt 1) {
    Write-Output "ERROR:No screens"
    exit 1
  }
  \$i = 0
  foreach (\$screen in \$screens) {
    \$i++
    \$b = \$screen.Bounds
    \$bitmap = New-Object System.Drawing.Bitmap(\$b.Width, \$b.Height)
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
    \$graphics.CopyFromScreen(\$b.Location, [System.Drawing.Point]::Empty, \$b.Size)
    \$out = '${prefix}_' + \$i + '.png'
    \$bitmap.Save(\$out, [System.Drawing.Imaging.ImageFormat]::Png)
    \$graphics.Dispose()
    \$bitmap.Dispose()
  }
  Write-Output "SUCCESS:\$i"
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

      final out = result.stdout.toString().trim();
      if (result.exitCode != 0 || !out.startsWith('SUCCESS:')) {
        _debugLog('Windows multi-monitor capture failed: $out');
        // Fallback: legacy virtual-desktop capture
        final legacy = await _captureWindowsVirtualScreen();
        return legacy == null ? <Uint8List>[] : <Uint8List>[legacy];
      }

      final count = int.tryParse(out.split(':').last.trim()) ?? 0;
      final frames = <Uint8List>[];
      for (var i = 1; i <= count; i++) {
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
      return frames;
    } catch (e) {
      _debugLog('Windows per-monitor capture error: $e');
      final legacy = await _captureWindowsVirtualScreen();
      return legacy == null ? <Uint8List>[] : <Uint8List>[legacy];
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
      final uploadBytes = compressToJpeg(imageBytes, maxWidth: 1280, quality: 72);

      final activityStatus = activityDetection.analyzeScreenshot(imageBytes);
      if (activityStatus['is_idle'] == true) {
        _isUserActive = false;
      } else {
        _isUserActive = true;
      }

      final result = await apiService.uploadScreenshot(
        uploadBytes,
        isIdle: activityStatus['is_idle'] == true,
        idleDuration: activityStatus['idle_duration'] as int? ?? 0,
        lastActivityAt: activityStatus['last_activity_at']?.toString(),
        screenIndex: screenIndex,
      );

      if (result['success'] == true) {
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
