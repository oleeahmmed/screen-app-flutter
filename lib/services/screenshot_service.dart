// screenshot_service.dart - Win32 API Silent Multi-Monitor Screenshot Service

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import 'api_service.dart';
import 'activity_detection_service.dart';
import '../config.dart';
import '../app_session.dart';

class ScreenshotService {
  final ApiService apiService;
  final ActivityDetectionService activityDetection = ActivityDetectionService();
  Timer? _screenshotTimer;
  Timer? _activityCheckTimer;
  bool _isRunning = false;
  int _captureCount = 0;
  DateTime _lastActivityTime = DateTime.now();
  bool _isUserActive = true;
  int _displayCount = 1;
  static const int IDLE_THRESHOLD_SECONDS = 60; // 1 minute
  static const bool ENABLE_DEBUG_LOGS = true; // Set to true for debugging

  ScreenshotService(this.apiService);

  void _debugLog(String message) {
    if (ENABLE_DEBUG_LOGS) {
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
    _isRunning = true;
    
    _debugLog('🚀 Win32 API Silent Screenshot service started');
    _debugLog('📸 Will capture all displays every 30 seconds using PowerShell');

    final interval = AppConfig.screenshotInterval.clamp(15, 600);
    _screenshotTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      _debugLog('⏰ Timer triggered - capturing with PowerShell...');
      await _captureWithPowerShell();
    });

    // Activity check every 10 seconds
    _activityCheckTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _checkActivityStatus();
    });
    
    // Capture immediately on start
    _debugLog('📸 Capturing first screenshot immediately...');
    await _captureWithPowerShell();
  }

  Future<void> _captureWithPowerShell() async {
    if (!_isRunning) return;
    if (!AppSession.mayCaptureScreenshots) {
      _debugLog('⏸️ Screenshot capture skipped (no user consent)');
      return;
    }

    try {
      _captureCount++;
      _debugLog('📸 Capture #$_captureCount - Using PowerShell silent capture...');
      
      Uint8List? capturedImage;
      
      if (Platform.isWindows) {
        capturedImage = await _captureWindowsPowerShell();
      } else {
        // Fallback for other platforms
        capturedImage = await _captureFallback();
      }
      
      if (capturedImage != null) {
        _debugLog('✅ Capture #$_captureCount - Got ${capturedImage.length} bytes');
        await _uploadImage(capturedImage);
      } else {
        _debugLog('❌ Capture #$_captureCount - No image captured');
      }
    } catch (e) {
      _debugLog('❌ Capture #$_captureCount - Error: $e');
    }
  }

  Future<Uint8List?> _captureWindowsPowerShell() async {
    try {
      _debugLog('🪟 PowerShell screen capture (completely silent)...');
      
      final tempDir = await getTemporaryDirectory();
      final tempFile = '${tempDir.path}\\silent_capture_${DateTime.now().millisecondsSinceEpoch}.png';
      
      // Use PowerShell with System.Windows.Forms for direct screen capture
      final psScript = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
  # Get virtual screen bounds (all monitors)
  \$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
  
  # Create bitmap with exact dimensions
  \$bitmap = New-Object System.Drawing.Bitmap(\$bounds.Width, \$bounds.Height)
  \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
  
  # Copy screen content (silent - no flash)
  \$graphics.CopyFromScreen(\$bounds.Location, [System.Drawing.Point]::Empty, \$bounds.Size)
  
  # Save as PNG
  \$bitmap.Save('$tempFile', [System.Drawing.Imaging.ImageFormat]::Png)
  
  # Cleanup
  \$graphics.Dispose()
  \$bitmap.Dispose()
  
  # Verify file
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
      
      final result = await Process.run('powershell', [
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-Command', psScript
      ], runInShell: false);
      
      _debugLog('  📋 PowerShell result: ${result.stdout}');
      
      if (result.exitCode == 0 && result.stdout.toString().startsWith('SUCCESS:')) {
        final file = File(tempFile);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          _debugLog('  ✅ PowerShell PNG capture: ${bytes.length} bytes');
          await file.delete().catchError((_) {});
          return bytes;
        }
      }
      
      _debugLog('  ❌ PowerShell capture failed: ${result.stdout}');
      return null;
    } catch (e) {
      _debugLog('  ❌ PowerShell capture error: $e');
      return null;
    }
  }

  Future<Uint8List?> _captureFallback() async {
    try {
      _debugLog('🔄 Using fallback capture method...');
      
      if (Platform.isMacOS) {
        return await _captureMacNative();
      } else if (Platform.isLinux) {
        return await _captureLinuxNative();
      }
      
      return null;
    } catch (e) {
      _debugLog('❌ Fallback capture error: $e');
      return null;
    }
  }

  Future<Uint8List?> _captureMacNative() async {
    try {
      _debugLog('🍎 macOS native capture...');
      final tempFile = '/tmp/mac_capture_${DateTime.now().millisecondsSinceEpoch}.png';
      
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

  Future<Uint8List?> _captureLinuxNative() async {
    try {
      _debugLog('🐧 Linux native capture...');
      final tempFile = '/tmp/linux_capture_${DateTime.now().millisecondsSinceEpoch}.png';
      
      final tools = [
        ['gnome-screenshot', '-f', tempFile],
        ['scrot', tempFile],
        ['import', '-window', 'root', tempFile],
        ['maim', tempFile],
      ];
      
      for (final tool in tools) {
        try {
          final result = await Process.run(tool[0], tool.sublist(1));
          if (result.exitCode == 0) {
            final file = File(tempFile);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              await file.delete().catchError((_) {});
              return bytes;
            }
          }
        } catch (e) {
          // Try next tool
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _uploadImage(Uint8List imageBytes) async {
    try {
      _debugLog('📤 Processing captured image (${imageBytes.length} bytes)...');
      
      // Validate that we have a proper PNG file
      if (imageBytes.length < 8) {
        _debugLog('  ❌ Image too small to be valid PNG');
        return;
      }
      
      // Check PNG signature (first 8 bytes should be PNG header)
      final pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      bool isPng = true;
      for (int i = 0; i < 8 && i < imageBytes.length; i++) {
        if (imageBytes[i] != pngSignature[i]) {
          isPng = false;
          break;
        }
      }
      
      if (!isPng) {
        _debugLog('  ⚠️ Warning: File does not have PNG signature');
      } else {
        _debugLog('  ✅ Valid PNG signature detected');
      }
      
      // Always compress before upload - resize to 360px width, JPEG 50%
      _debugLog('  🗜️ Compressing ${(imageBytes.length / 1024).toStringAsFixed(0)}KB...');
      Uint8List uploadBytes = await _compressImage(imageBytes);
      _debugLog('  ✅ ${(imageBytes.length / 1024).toStringAsFixed(0)}KB → ${(uploadBytes.length / 1024).toStringAsFixed(0)}KB');
      
      // Analyze screenshot for activity detection
      final activityStatus = activityDetection.analyzeScreenshot(imageBytes);
      
      _debugLog('  📊 Activity: ${activityStatus['is_idle'] == true ? "IDLE" : "ACTIVE"}');
      
      if (activityStatus['is_idle'] == true) {
        _debugLog('  ⏸️ User is IDLE - uploading with idle flag');
        _isUserActive = false;
      } else {
        _isUserActive = true;
      }
      
      // Upload
      final result = await apiService.uploadScreenshot(
        uploadBytes,
        isIdle: activityStatus['is_idle'],
        idleDuration: activityStatus['idle_duration'],
        lastActivityAt: activityStatus['last_activity_at'],
      );
      
      if (result['success']) {
        _debugLog('  ✅ Uploaded successfully');
      } else {
        _debugLog('  ❌ Upload failed: ${result['error']}');
      }
    } catch (e) {
      _debugLog('❌ Upload error: $e');
    }
  }

  Future<Uint8List> _compressImage(Uint8List imageBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final inputFile = '${tempDir.path}\\cap_in_$ts.png';
      final outputFile = '${tempDir.path}\\cap_out_$ts.jpg';
      
      await File(inputFile).writeAsBytes(imageBytes);
      
      // Resize to 360px width and save as JPEG 50% quality
      final psScript = '''
Add-Type -AssemblyName System.Drawing
try {
  \$img = [System.Drawing.Image]::FromFile('$inputFile')
  \$ratio = 720 / \$img.Width
  \$w = 720
  \$h = [int](\$img.Height * \$ratio)
  \$bmp = New-Object System.Drawing.Bitmap(\$w, \$h)
  \$g = [System.Drawing.Graphics]::FromImage(\$bmp)
  \$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  \$g.DrawImage(\$img, 0, 0, \$w, \$h)
  \$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { \$_.MimeType -eq 'image/jpeg' }
  \$ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
  \$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]70)
  \$bmp.Save('$outputFile', \$codec, \$ep)
  \$g.Dispose(); \$bmp.Dispose(); \$img.Dispose()
  Write-Output "OK"
} catch { Write-Output "ERR:\$(\$_.Exception.Message)" }
''';
      
      final result = await Process.run('powershell', ['-ExecutionPolicy', 'Bypass', '-NoProfile', '-WindowStyle', 'Hidden', '-Command', psScript], runInShell: false);
      
      final outFile = File(outputFile);
      if (result.stdout.toString().trim() == 'OK' && await outFile.exists()) {
        final compressed = await outFile.readAsBytes();
        await File(inputFile).delete().catchError((_) {});
        await outFile.delete().catchError((_) {});
        return Uint8List.fromList(compressed);
      }
      
      await File(inputFile).delete().catchError((_) {});
      await File(outputFile).delete().catchError((_) {});
    } catch (e) {
      _debugLog('  ⚠️ Compression failed: $e');
    }
    return imageBytes;
  }

  void stopCapture() {
    _isRunning = false;
    _screenshotTimer?.cancel();
    _activityCheckTimer?.cancel();
    _debugLog('🛑 Silent Screenshot service stopped');
  }

  void _checkActivityStatus() {
    final now = DateTime.now();
    final secondsSinceLastActivity = now.difference(_lastActivityTime).inSeconds;

    if (secondsSinceLastActivity > IDLE_THRESHOLD_SECONDS && _isUserActive) {
      _isUserActive = false;
      _updateActivityStatus(false);
      _debugLog('⏸️ User marked as IDLE');
    } else if (secondsSinceLastActivity <= IDLE_THRESHOLD_SECONDS && !_isUserActive) {
      _isUserActive = true;
      _updateActivityStatus(true);
      _debugLog('✅ User marked as ACTIVE');
    }
  }

  Future<void> _updateActivityStatus(bool isActive) async {
    try {
      await apiService.updateActivityStatus(isActive);
    } catch (e) {
      // Silent error - no logging
    }
  }

  bool get isRunning => _isRunning;
  bool get isUserActive => _isUserActive;
  int get displayCount => _displayCount;
}