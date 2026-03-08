// activity_detection_service.dart - Client-side activity detection via screenshot comparison

import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class ActivityDetectionService {
  // Configuration
  static const int IDLE_THRESHOLD_COUNT = 4; // 4 consecutive same screenshots = idle
  static const int IDLE_TIME_MINUTES = 2; // 2 minutes = idle
  static const bool ENABLE_DEBUG_LOGS = true;
  
  // State
  String? _previousScreenshotHash;
  int _sameScreenshotCount = 0;
  bool _isIdle = false;
  DateTime _lastActivityTime = DateTime.now();
  DateTime _idleStartTime = DateTime.now();
  
  // Statistics
  int _totalScreenshots = 0;
  int _activityChanges = 0;

  void _debugLog(String message) {
    if (ENABLE_DEBUG_LOGS) {
      print('[ActivityDetection] $message');
    }
  }

  /// Analyze screenshot and detect if user is active or idle
  /// Returns: Map with activity status and metadata
  Map<String, dynamic> analyzeScreenshot(Uint8List screenshotBytes) {
    _totalScreenshots++;
    
    // Calculate hash of current screenshot
    String currentHash = _calculateScreenshotHash(screenshotBytes);
    
    _debugLog('📊 Screenshot #$_totalScreenshots - Hash: ${currentHash.substring(0, 16)}...');
    
    // First screenshot - always active
    if (_previousScreenshotHash == null) {
      _previousScreenshotHash = currentHash;
      _lastActivityTime = DateTime.now();
      _debugLog('  ✅ First screenshot - marked as ACTIVE');
      
      return _buildResponse(
        isIdle: false,
        idleDuration: 0,
        reason: 'First screenshot',
      );
    }
    
    // Compare with previous screenshot
    bool screenshotsAreSame = currentHash == _previousScreenshotHash;
    
    if (screenshotsAreSame) {
      // Same screenshot - increment counter
      _sameScreenshotCount++;
      _debugLog('  🔄 Same as previous (count: $_sameScreenshotCount/$IDLE_THRESHOLD_COUNT)');
      
      // Check if reached idle threshold
      if (_sameScreenshotCount >= IDLE_THRESHOLD_COUNT && !_isIdle) {
        // User is now idle
        _isIdle = true;
        _idleStartTime = DateTime.now();
        _activityChanges++;
        _debugLog('  ⏸️ User marked as IDLE (${_sameScreenshotCount} consecutive same screenshots)');
      }
      
    } else {
      // Screenshot changed - activity detected!
      _debugLog('  ✅ Screenshot CHANGED - Activity detected!');
      
      if (_isIdle) {
        // User was idle, now active again
        int idleMinutes = DateTime.now().difference(_idleStartTime).inMinutes;
        _debugLog('  🎉 User ACTIVE again after ${idleMinutes}m idle');
        _activityChanges++;
      }
      
      // Reset idle state
      _sameScreenshotCount = 0;
      _isIdle = false;
      _lastActivityTime = DateTime.now();
    }
    
    // Update previous hash
    _previousScreenshotHash = currentHash;
    
    // Calculate idle duration
    int idleDuration = 0;
    if (_isIdle) {
      idleDuration = DateTime.now().difference(_idleStartTime).inMinutes;
    }
    
    return _buildResponse(
      isIdle: _isIdle,
      idleDuration: idleDuration,
      reason: screenshotsAreSame 
          ? 'No screen changes detected' 
          : 'Screen activity detected',
    );
  }

  /// Calculate SHA-256 hash of screenshot for comparison
  String _calculateScreenshotHash(Uint8List imageBytes) {
    // Use SHA-256 for fast and reliable comparison
    var digest = sha256.convert(imageBytes);
    return digest.toString();
  }

  /// Build response with activity status
  Map<String, dynamic> _buildResponse({
    required bool isIdle,
    required int idleDuration,
    required String reason,
  }) {
    return {
      'is_idle': isIdle,
      'idle_duration': idleDuration,
      'last_activity_at': _lastActivityTime.toIso8601String(),
      'same_screenshot_count': _sameScreenshotCount,
      'reason': reason,
      'statistics': {
        'total_screenshots': _totalScreenshots,
        'activity_changes': _activityChanges,
        'current_status': isIdle ? 'IDLE' : 'ACTIVE',
      }
    };
  }

  /// Get current activity status without analyzing new screenshot
  Map<String, dynamic> getCurrentStatus() {
    int idleDuration = 0;
    if (_isIdle) {
      idleDuration = DateTime.now().difference(_idleStartTime).inMinutes;
    }
    
    return {
      'is_idle': _isIdle,
      'idle_duration': idleDuration,
      'last_activity_at': _lastActivityTime.toIso8601String(),
      'same_screenshot_count': _sameScreenshotCount,
      'statistics': {
        'total_screenshots': _totalScreenshots,
        'activity_changes': _activityChanges,
        'current_status': _isIdle ? 'IDLE' : 'ACTIVE',
      }
    };
  }

  /// Reset detection state (useful for testing or manual reset)
  void reset() {
    _previousScreenshotHash = null;
    _sameScreenshotCount = 0;
    _isIdle = false;
    _lastActivityTime = DateTime.now();
    _idleStartTime = DateTime.now();
    _totalScreenshots = 0;
    _activityChanges = 0;
    _debugLog('🔄 Activity detection state reset');
  }

  // Getters
  bool get isIdle => _isIdle;
  int get sameScreenshotCount => _sameScreenshotCount;
  DateTime get lastActivityTime => _lastActivityTime;
  int get totalScreenshots => _totalScreenshots;
  int get activityChanges => _activityChanges;
}
