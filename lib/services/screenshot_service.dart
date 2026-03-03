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
  bool _hasCheckedTools = false;
  String? _workingTool;
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
    print('📸 Will capture every 30 seconds');
    print('🔍 Activity check every 10 seconds');

    // Check available tools once
    if (!_hasCheckedTools) {
      _checkAvailableTools();
    }

    // Screenshot capture every 30 seconds (in background)
    _screenshotTimer = Timer.periodic(Duration(seconds: 30), (_) async {
      print('⏰ Timer triggered - attempting capture...');
      // Run in isolate to not block UI
      await _captureInBackground();
    });

    // Activity check every 10 seconds
    _activityCheckTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _checkActivityStatus();
    });
    
    // Capture immediately on start for testing
    print('📸 Capturing first screenshot immediately...');
    _captureInBackground();
  }
  
  Future<void> _checkAvailableTools() async {
    _hasCheckedTools = true;
    
    if (Platform.isLinux) {
      print('🔧 Checking available screenshot tools on Linux...');
      
      final tools = ['gnome-screenshot', 'scrot', 'import', 'maim', 'spectacle'];
      
      for (final tool in tools) {
        try {
          final result = await Process.run('which', [tool]);
          if (result.exitCode == 0) {
            _workingTool = tool;
            print('  ✅ Found: $tool');
            break;
          }
        } catch (e) {
          // Tool not found
        }
      }
      
      if (_workingTool == null) {
        print('  ⚠️ No screenshot tool found!');
        print('  💡 Install one with:');
        print('     sudo apt install gnome-screenshot  # or');
        print('     sudo apt install scrot  # or');
        print('     sudo apt install imagemagick  # or');
        print('     sudo apt install maim');
      } else {
        print('  🎯 Will use: $_workingTool');
      }
    }
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
      print('📸 Capture #$_captureCount - Starting...');
      
      // Capture in background without blocking UI
      final imageBytes = await _captureFullMonitorSilent();
      
      if (imageBytes != null && imageBytes.isNotEmpty) {
        print('✅ Capture #$_captureCount - Got ${imageBytes.length} bytes');
        // Upload silently
        await _uploadSilent(imageBytes);
      } else {
        print('❌ Capture #$_captureCount - No image data captured');
      }
    } catch (e) {
      // Silent error - don't show to user
      print('❌ Capture #$_captureCount - Error: $e');
    }
  }

  Future<Uint8List?> _captureFullMonitorSilent() async {
    try {
      print('🖥️ Detecting platform...');
      if (Platform.isWindows) {
        print('🪟 Windows detected - using PowerShell capture');
        return await _captureWindowsMonitor();
      } else if (Platform.isMacOS) {
        print('🍎 macOS detected - using screencapture');
        return await _captureMacMonitor();
      } else if (Platform.isLinux) {
        print('🐧 Linux detected - trying capture tools');
        return await _captureLinuxMonitor();
      }
      print('❌ Unsupported platform');
      return null;
    } catch (e) {
      print('❌ Platform detection error: $e');
      return null;
    }
  }

  Future<void> _uploadSilent(Uint8List imageBytes) async {
    try {
      print('📤 Uploading ${imageBytes.length} bytes...');
      final result = await apiService.uploadScreenshot(imageBytes);
      if (result['success']) {
        print('✅ Screenshot #$_captureCount uploaded successfully');
      } else {
        print('❌ Upload failed: ${result['error']}');
      }
    } catch (e) {
      print('❌ Upload error: $e');
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
      print('🪟 Capturing Windows screenshot...');
      final tempDir = Directory.systemTemp;
      final tempFile = '${tempDir.path}\\ss_${DateTime.now().millisecondsSinceEpoch}.png';
      
      print('  📁 Temp file: $tempFile');
      
      final result = await Process.run('powershell', [
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-Command',
        '''
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
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
        \$bitmap.Save('$tempFile', [System.Drawing.Imaging.ImageFormat]::Png)
        \$graphics.Dispose()
        \$bitmap.Dispose()
        Write-Output "Success"
        '''
      ], runInShell: false);
      
      print('  📊 PowerShell exit code: ${result.exitCode}');
      
      if (result.exitCode == 0 && result.stdout.toString().contains('Success')) {
        final file = File(tempFile);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          print('  ✅ Screenshot captured: ${bytes.length} bytes');
          await file.delete().catchError((_) {});
          return bytes;
        } else {
          print('  ❌ File not created');
        }
      } else {
        print('  ❌ PowerShell error: ${result.stderr}');
      }
      return null;
    } catch (e) {
      print('  ❌ Windows capture error: $e');
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
      
      print('🐧 Trying Linux screenshot tools...');
      
      // Try gnome-screenshot first
      print('  Trying gnome-screenshot...');
      var result = await Process.run('gnome-screenshot', ['-f', tempFile]).catchError((_) => ProcessResult(1, 1, '', ''));
      
      if (result.exitCode == 0) {
        print('  ✅ gnome-screenshot worked');
        return await _readAndDeleteTempFile(tempFile);
      }
      
      // Try scrot
      print('  Trying scrot...');
      result = await Process.run('scrot', [tempFile]).catchError((_) => ProcessResult(1, 1, '', ''));
      
      if (result.exitCode == 0) {
        print('  ✅ scrot worked');
        return await _readAndDeleteTempFile(tempFile);
      }
      
      // Try import (ImageMagick)
      print('  Trying import (ImageMagick)...');
      result = await Process.run('import', ['-window', 'root', tempFile]).catchError((_) => ProcessResult(1, 1, '', ''));
      
      if (result.exitCode == 0) {
        print('  ✅ import worked');
        return await _readAndDeleteTempFile(tempFile);
      }
      
      // Try maim
      print('  Trying maim...');
      result = await Process.run('maim', [tempFile]).catchError((_) => ProcessResult(1, 1, '', ''));
      
      if (result.exitCode == 0) {
        print('  ✅ maim worked');
        return await _readAndDeleteTempFile(tempFile);
      }
      
      // Try spectacle (KDE)
      print('  Trying spectacle...');
      result = await Process.run('spectacle', ['-b', '-n', '-o', tempFile]).catchError((_) => ProcessResult(1, 1, '', ''));
      
      if (result.exitCode == 0) {
        print('  ✅ spectacle worked');
        return await _readAndDeleteTempFile(tempFile);
      }
      
      print('  ❌ All screenshot tools failed');
      print('  💡 Install one of: gnome-screenshot, scrot, imagemagick, maim, spectacle');
      return null;
    } catch (e) {
      print('  ❌ Linux capture error: $e');
      return null;
    }
  }
  
  Future<Uint8List?> _readAndDeleteTempFile(String tempFile) async {
    try {
      final file = File(tempFile);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await file.delete().catchError((_) {});
        return bytes;
      }
      return null;
    } catch (e) {
      print('  ❌ Error reading temp file: $e');
      return null;
    }
  }

  bool get isRunning => _isRunning;
  bool get isUserActive => _isUserActive;
}

