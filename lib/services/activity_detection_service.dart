// activity_detection_service.dart - Client-side activity detection via screenshot comparison

import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class ActivityDetectionService {
  // Configuration
  static const int idleThresholdCount = 4; // 4 consecutive same screenshots = idle
  static const bool enableDebugLogs = true;

  // Per-screen state (multi-monitor safe)
  final Map<int, String> _previousHashByScreen = {};
  final Map<int, int> _sameCountByScreen = {};
  bool _isIdle = false;
  DateTime _lastActivityTime = DateTime.now();
  DateTime _idleStartTime = DateTime.now();

  // Statistics
  int _totalScreenshots = 0;
  int _activityChanges = 0;

  void _debugLog(String message) {
    if (enableDebugLogs) {
      print('[ActivityDetection] $message');
    }
  }

  /// SHA-256 of raw capture bytes (before JPEG compress).
  String hashBytes(Uint8List screenshotBytes) =>
      sha256.convert(screenshotBytes).toString();

  /// Analyze screenshot and detect if user is active or idle.
  ///
  /// [screenIndex] keeps multi-monitor hashes independent.
  Map<String, dynamic> analyzeScreenshot(
    Uint8List screenshotBytes, {
    int screenIndex = 1,
  }) {
    _totalScreenshots++;
    final currentHash = hashBytes(screenshotBytes);
    final short = currentHash.length > 16 ? currentHash.substring(0, 16) : currentHash;
    _debugLog('Screenshot #$_totalScreenshots screen=$screenIndex hash=$short…');

    final previous = _previousHashByScreen[screenIndex];
    if (previous == null) {
      _previousHashByScreen[screenIndex] = currentHash;
      _sameCountByScreen[screenIndex] = 0;
      _lastActivityTime = DateTime.now();
      _debugLog('  First frame for screen $screenIndex — ACTIVE');
      return _buildResponse(
        isIdle: false,
        idleDuration: 0,
        unchanged: false,
        contentHash: currentHash,
        reason: 'First screenshot',
      );
    }

    final unchanged = currentHash == previous;
    if (unchanged) {
      final count = (_sameCountByScreen[screenIndex] ?? 0) + 1;
      _sameCountByScreen[screenIndex] = count;
      _debugLog('  Same as previous (count: $count/$idleThresholdCount)');

      if (count >= idleThresholdCount && !_isIdle) {
        _isIdle = true;
        _idleStartTime = DateTime.now();
        _activityChanges++;
        _debugLog('  User marked IDLE ($count consecutive same frames)');
      }
    } else {
      _debugLog('  Screen CHANGED — activity detected');
      if (_isIdle) {
        final idleMinutes = DateTime.now().difference(_idleStartTime).inMinutes;
        _debugLog('  User ACTIVE again after ${idleMinutes}m idle');
        _activityChanges++;
      }
      _sameCountByScreen[screenIndex] = 0;
      // Any screen change clears global idle.
      _isIdle = false;
      _lastActivityTime = DateTime.now();
      _previousHashByScreen[screenIndex] = currentHash;
    }

    // Keep previous hash when unchanged so we keep comparing to the last unique frame.
    if (!unchanged) {
      _previousHashByScreen[screenIndex] = currentHash;
    }

    var idleDuration = 0;
    if (_isIdle) {
      idleDuration = DateTime.now().difference(_idleStartTime).inMinutes;
    }

    return _buildResponse(
      isIdle: _isIdle,
      idleDuration: idleDuration,
      unchanged: unchanged,
      contentHash: currentHash,
      reason: unchanged ? 'No screen changes detected' : 'Screen activity detected',
    );
  }

  Map<String, dynamic> _buildResponse({
    required bool isIdle,
    required int idleDuration,
    required bool unchanged,
    required String contentHash,
    required String reason,
  }) {
    return {
      'is_idle': isIdle,
      'idle_duration': idleDuration,
      'unchanged': unchanged,
      'content_hash': contentHash,
      'last_activity_at': _lastActivityTime.toIso8601String(),
      'reason': reason,
      'statistics': {
        'total_screenshots': _totalScreenshots,
        'activity_changes': _activityChanges,
        'current_status': isIdle ? 'IDLE' : 'ACTIVE',
      },
    };
  }

  void reset() {
    _previousHashByScreen.clear();
    _sameCountByScreen.clear();
    _isIdle = false;
    _lastActivityTime = DateTime.now();
    _idleStartTime = DateTime.now();
    _totalScreenshots = 0;
    _activityChanges = 0;
    _debugLog('Activity detection state reset');
  }

  bool get isIdle => _isIdle;
  DateTime get lastActivityTime => _lastActivityTime;
  int get totalScreenshots => _totalScreenshots;
  int get activityChanges => _activityChanges;
}
