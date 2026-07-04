// screenshot_service.dart — periodic screenshot upload (Windows, Linux, macOS)

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';
import 'activity_detection_service.dart';
import 'image_compress_util.dart';
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
    _lastActivityTime = DateTime.now();
    if (!_isUserActive) {
      _isUserActive = true;
      _updateActivityStatus(true);
    }
  }

  Future<void> startCapture() async {
    if (_isRunning) return;
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
    _debugLog('Screenshot service started ($platformLabel)');
    _debugLog('Capture interval: ${interval}s');

    _screenshotTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      await _captureOnce();
    });

    _activityCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkActivityStatus();
    });

    // First capture runs in background — must not block clock-in UI.
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
      Uint8List? captured;

      if (Platform.isWindows) {
        captured = await _captureWindowsPowerShell();
      } else if (Platform.isLinux) {
        captured = await _captureLinuxNative();
      } else if (Platform.isMacOS) {
        captured = await _captureMacOS();
      }

      if (captured != null && captured.isNotEmpty) {
        _debugLog('Capture #$_captureCount: ${captured.length} bytes');
        await _uploadImage(captured);
      } else {
        _debugLog('Capture #$_captureCount failed');
      }
    } catch (e) {
      _debugLog('Capture error: $e');
    }
  }

  Future<Uint8List?> _captureWindowsPowerShell() async {
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
          await file.delete().catchError((_) {});
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
        await file.delete().catchError((_) {});
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
      final tools = <List<String>>[
        ['grim', tempFile],
        ['gnome-screenshot', '-f', tempFile],
        ['spectacle', '-b', '-n', '-o', tempFile],
        ['scrot', tempFile],
        ['import', '-window', 'root', tempFile],
        ['maim', tempFile],
        ['xwd', '-root', '-out', tempFile.replaceAll('.png', '.xwd')],
      ];
      for (final tool in tools) {
        try {
          final exe = tool[0];
          final resolved = await _resolveCommand(exe);
          if (resolved == null) continue;
          final args = tool.sublist(1);
          ProcessResult result;
          try {
            result = await Process.run(resolved, args, runInShell: false)
                .timeout(const Duration(seconds: 12));
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
                await File(readPath).delete().catchError((_) {});
                readPath = pngPath;
              }
            }
          }

          final file = File(readPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            await file.delete().catchError((_) {});
            if (bytes.isNotEmpty) return bytes;
          }
        } catch (_) {}
      }
      _debugLog('Linux: install grim, gnome-screenshot, scrot, or maim for capture');
      return null;
    } catch (e) {
      _debugLog('Linux capture error: $e');
      return null;
    }
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

  Future<void> _uploadImage(Uint8List imageBytes) async {
    try {
      final uploadBytes = compressToJpeg(imageBytes, maxWidth: 720, quality: 70);

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
      );

      if (result['success'] == true) {
        _debugLog('Uploaded ${(uploadBytes.length / 1024).toStringAsFixed(0)}KB');
      } else {
        _debugLog('Upload failed: ${result['error']}');
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
  bool get isUserActive => _isUserActive;
  int get displayCount => 1;
}
