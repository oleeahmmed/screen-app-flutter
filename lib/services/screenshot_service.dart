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

class ScreenshotService {
  final ApiService apiService;
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

    // Screenshot capture every 30 seconds
    _screenshotTimer = Timer.periodic(Duration(seconds: 30), (_) async {
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
      _debugLog('📤 Uploading captured image (${imageBytes.length} bytes)...');
      
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
      
      final result = await apiService.uploadScreenshot(imageBytes);
      if (result['success']) {
        _debugLog('  ✅ Image uploaded successfully');
      } else {
        _debugLog('  ❌ Image upload failed: ${result['error']}');
        
        // Log additional details for debugging
        if (result['error'].toString().contains('400')) {
          _debugLog('  📋 400 Error - likely invalid image format or missing fields');
        }
      }
    } catch (e) {
      _debugLog('❌ Upload error: $e');
    }
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