// dashboard_page.dart — Home / time tracking hub (aims-webapps glass style)

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_session.dart';
import '../services/api_service.dart';
import '../services/attendance_cache.dart';
import '../services/attendance_local_store.dart';
import '../services/attendance_timer_state.dart';
import '../services/screenshot_service.dart';
import '../utils/app_toast.dart';
import '../utils/platform_capabilities.dart';
import '../utils/responsive.dart';
import '../services/user_data_service.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_dialog.dart';
import '../widgets/break_panel.dart';
import '../widgets/closing_report_panel.dart';
import '../widgets/glass_card.dart';

class DashboardPage extends StatefulWidget {
  final ApiService apiService;
  final String username;
  final ScreenshotService? screenshotService;
  final int refreshToken;
  final VoidCallback? onLogout;

  const DashboardPage({
    super.key,
    required this.apiService,
    required this.username,
    this.screenshotService,
    this.refreshToken = 0,
    this.onLogout,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isClockedIn = false;
  bool _onBreak = false;
  Duration _todayWorkDuration = Duration.zero;
  late DateTime _clockInTime;
  late DateTime _now;
  String _companyName = '';
  String _fullName = '';
  String _designation = '';
  String _department = '';
  bool _isProcessing = false;
  bool _isBreakBusy = false;
  DateTime? _breakStartTime;
  int _completedBreakSeconds = 0;
  List<Map<String, dynamic>> _todayBreaks = [];
  int _breakRefresh = 0;
  int _reportRefresh = 0;
  String? _workingDate;
  Map<String, dynamic>? _effectiveSchedule;
  Timer? _attendancePollTimer;
  final AttendanceTimerState _timer = AttendanceTimerState();
  DateTime? _lastLocalPersist;

  bool get _effectiveOnBreak => _timer.isOnBreak || _onBreak;

  /// Clocked in (break included) — used for break button and session UI.
  bool get _isWorkingSession => _isClockedIn || _effectiveOnBreak;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockInTime = _now;
    _loadUserData();
    _bootstrapAttendance();
    _startClock();
  }

  Future<void> _bootstrapAttendance() async {
    await _restoreLocalState();
    final cached = await AttendanceCache.load();
    if (cached != null && mounted) {
      setState(() => _applyServerAttendanceData(cached, fromServer: true));
    }
    await _loadAttendance();
  }

  Future<void> _restoreLocalState() async {
    final raw = await AttendanceLocalStore.load(widget.username);
    if (raw == null || !mounted) return;
    setState(() {
      _timer.restoreFromJson(raw);
      _onBreak = raw['ui_on_break'] == true || _timer.isOnBreak;
      _isClockedIn = raw['ui_clocked_in'] == true || _timer.isClockedIn || _onBreak;
      _workingDate = raw['working_date']?.toString();
      _breakStartTime = _parseApiDateTime(raw['break_start_time']);
      if (_onBreak && _breakStartTime != null && !_timer.isOnBreak) {
        _timer.onBreakStart(at: _breakStartTime);
      }
      _todayWorkDuration = Duration(seconds: _timer.liveWorkSeconds);
      _completedBreakSeconds = _timer.completedBreakSeconds;
    });
    _syncAttendancePolling();
  }

  Future<void> _persistLocalState() async {
    await AttendanceLocalStore.save(
      username: widget.username,
      timer: _timer,
      uiOnBreak: _effectiveOnBreak,
      uiClockedIn: _isClockedIn || _effectiveOnBreak,
      workingDate: _workingDate,
      breakStartTime: _breakStartTime,
    );
    _lastLocalPersist = DateTime.now();
  }

  void _maybePersistLocalState() {
    final now = DateTime.now();
    if (_lastLocalPersist != null &&
        now.difference(_lastLocalPersist!).inSeconds < 5) {
      return;
    }
    unawaited(_persistLocalState());
  }

  @override
  void dispose() {
    _attendancePollTimer?.cancel();
    unawaited(_persistLocalState());
    super.dispose();
  }

  void _syncAttendancePolling() {
    _attendancePollTimer?.cancel();
    if (!_timer.isClockedIn && !_timer.isOnBreak) return;
    _attendancePollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _loadAttendance();
    });
  }

  int get _liveWorkSeconds => _timer.liveWorkSeconds;

  int get _liveBreakSeconds => _timer.liveBreakSeconds;

  Duration get _todayNetWork => Duration(seconds: _liveWorkSeconds);
  Duration get _todayBreakDuration => Duration(seconds: _liveBreakSeconds);

  Future<void> _mergeBreakStatus() async {
    if (!_isClockedIn && !_effectiveOnBreak) {
      return;
    }

    final r = await widget.apiService.getBreakStatus();
    if (!mounted || r['success'] != true) return;

    final st = r['data'] as Map<String, dynamic>? ?? {};
    final onBreak = st['on_break'] == true;
    DateTime? breakStart;
    if (onBreak && st['break'] is Map) {
      breakStart = _parseApiDateTime((st['break'] as Map)['break_start']);
    }

    setState(() {
      _onBreak = onBreak;
      _breakStartTime = onBreak ? breakStart : null;
      if (onBreak) {
        _isClockedIn = true;
        if (!_timer.isOnBreak) {
          _timer.onBreakStart(at: breakStart);
        }
      } else if (_timer.isOnBreak) {
        _timer.onBreakEnd();
      }
    });
    unawaited(_persistLocalState());
  }

  Future<void> _loadBreakInfo() async {
    final myR = await widget.apiService.getMyBreaks(date: _workingDate);
    if (!mounted) return;

    var completedSecs = _completedBreakSeconds;
    var breaks = _todayBreaks;

    if (myR['success'] == true) {
      final data = myR['data'] as Map<String, dynamic>? ?? {};
      final summary = data['summary'] as Map<String, dynamic>?;
      final totalSecs = summary?['total_break_seconds'];
      if (totalSecs != null) {
        completedSecs = totalSecs is int ? totalSecs : int.tryParse('$totalSecs') ?? 0;
      } else {
        final totalMin = summary?['total_break_minutes'];
        completedSecs = (totalMin is int ? totalMin : int.tryParse('$totalMin') ?? 0) * 60;
      }
      final rawBreaks = data['breaks'];
      if (rawBreaks is List) {
        breaks = rawBreaks
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }

    if (mounted) {
      setState(() {
        _completedBreakSeconds = completedSecs;
        _todayBreaks = breaks;
      });
    }
  }

  int _allTodayBreakSeconds([DateTime? at]) {
    final now = at ?? _now;
    var total = 0;
    for (final b in _todayBreaks) {
      final start = _parseApiDateTime(b['break_start']);
      if (start == null) continue;
      final actualBack = _parseApiDateTime(b['actual_back']);
      if (actualBack != null) {
        total += actualBack.difference(start).inSeconds.clamp(0, 86400 * 2);
      } else if (_onBreak && _breakStartTime != null && start.isAtSameMomentAs(_breakStartTime!)) {
        total += now.difference(_breakStartTime!).inSeconds.clamp(0, 86400 * 2);
      }
    }
    if (total == 0 && _completedBreakSeconds > 0) {
      return _completedBreakSeconds;
    }
    return total;
  }

  int _sessionBreakSeconds([DateTime? at]) {
    if (!_isClockedIn) return 0;
    final now = at ?? _now;
    var total = 0;
    for (final b in _todayBreaks) {
      final start = _parseApiDateTime(b['break_start']);
      if (start == null || start.isBefore(_clockInTime)) continue;
      final actualBack = _parseApiDateTime(b['actual_back']);
      if (actualBack != null) {
        total += actualBack.difference(start).inSeconds.clamp(0, 86400 * 2);
      } else if (_onBreak && _breakStartTime != null && start.isAtSameMomentAs(_breakStartTime!)) {
        total += now.difference(_breakStartTime!).inSeconds.clamp(0, 86400 * 2);
      }
    }
    return total;
  }

  Duration get _sessionNetDuration {
    if (!_isClockedIn) return Duration.zero;
    final gross = _now.difference(_clockInTime);
    final net = gross - Duration(seconds: _sessionBreakSeconds());
    return net.isNegative ? Duration.zero : net;
  }

  bool _attendanceIsOpen(Map<String, dynamic>? att) {
    if (att == null) return false;
    final checkOut = att['check_out'];
    if (checkOut == null) return true;
    if (checkOut is String && checkOut.trim().isEmpty) return true;
    return false;
  }

  DateTime? _parseApiDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  int _parseSeconds(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  int _parseDurationSeconds(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is Map) {
      final secs = value['total_seconds'];
      if (secs != null) return _parseSeconds(secs);
      final hours = value['hours'];
      final minutes = value['minutes'];
      final h = hours is int ? hours : int.tryParse('$hours') ?? 0;
      final m = minutes is int ? minutes : int.tryParse('$minutes') ?? 0;
      return h * 3600 + m * 60;
    }
    return int.tryParse('$value') ?? 0;
  }

  Map<String, dynamic>? _attendanceFromActionResult(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in ['attendance', 'current_attendance']) {
      final raw = data[key];
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  void _applyOpenSession(Map<String, dynamic>? current) {
    final checkIn = _parseApiDateTime(current?['check_in']) ?? _clockInTime;
    _isClockedIn = true;
    _clockInTime = checkIn;
    _now = DateTime.now();
  }

  void _applyClosedSession(int totalSeconds, {int? breakSeconds}) {
    _isClockedIn = false;
    _onBreak = false;
    _breakStartTime = null;
    _timer.isClockedIn = false;
    _timer.isOnBreak = false;
    _timer.completedWorkSeconds = totalSeconds;
    _todayWorkDuration = Duration(seconds: totalSeconds);
    if (breakSeconds != null) {
      _timer.completedBreakSeconds = breakSeconds;
      if (breakSeconds > 0) _completedBreakSeconds = breakSeconds;
    }
    unawaited(_persistLocalState());
  }

  bool _readClockedInFlag(Map<String, dynamic> data, Map<String, dynamic>? current) {
    final flag = data['is_clocked_in'];
    if (flag == true) return true;
    if (flag is String && flag.toLowerCase() == 'true') return true;
    return _attendanceIsOpen(current);
  }

  void _applyServerAttendanceData(
    Map<String, dynamic> data, {
    Map<String, dynamic>? fallbackOpen,
    bool fromServer = false,
  }) {
    Map<String, dynamic>? current = data['current_attendance'] is Map
        ? Map<String, dynamic>.from(data['current_attendance'] as Map)
        : null;
    if (!_attendanceIsOpen(current) && _attendanceIsOpen(fallbackOpen)) {
      current = Map<String, dynamic>.from(fallbackOpen!);
    }

    final totalSeconds = _parseDurationSeconds(data['today_work_duration']);
    final breakSeconds = _parseDurationSeconds(data['today_break_duration']);
    final serverNow = _parseApiDateTime(data['server_now']) ?? DateTime.now();

    DateTime? breakStart;
    var onBreakFlag = data['on_break'] == true;
    if (onBreakFlag && data['active_break'] is Map) {
      final ab = Map<String, dynamic>.from(data['active_break'] as Map);
      breakStart = _parseApiDateTime(ab['break_start']);
    }

    // Local break wins until server explicitly confirms end break.
    final localOnBreak = _effectiveOnBreak;
    if (localOnBreak && !onBreakFlag) {
      onBreakFlag = true;
      breakStart ??= _breakStartTime;
    }

    var clockedIn = _readClockedInFlag(data, current) || _attendanceIsOpen(fallbackOpen);
    if (onBreakFlag || localOnBreak) clockedIn = true;

    _timer.applyServerSnapshot(
      workSeconds: totalSeconds,
      breakSeconds: breakSeconds,
      clockedIn: clockedIn,
      onBreak: onBreakFlag,
      breakStartedAt: breakStart,
      serverNow: serverNow,
      preserveLocalOnBreak: localOnBreak,
    );

    _onBreak = onBreakFlag;
    _breakStartTime = onBreakFlag ? (breakStart ?? _breakStartTime) : null;
    _workingDate = data['working_date']?.toString();
    if (data['effective_schedule'] is Map) {
      _effectiveSchedule = Map<String, dynamic>.from(data['effective_schedule'] as Map);
    }
    if (breakSeconds > 0) {
      _completedBreakSeconds = breakSeconds;
    }
    _todayWorkDuration = Duration(seconds: _timer.liveWorkSeconds);

    if (clockedIn) {
      _applyOpenSession(current ?? fallbackOpen);
    } else if (!localOnBreak) {
      _applyClosedSession(totalSeconds, breakSeconds: breakSeconds);
    }

    if (fromServer) {
      unawaited(_persistLocalState());
    }
  }

  /// Sync UI to clocked-out when server session is already closed.
  Future<void> _forceClosedSession() async {
    final result = await widget.apiService.getCurrentAttendance();
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'] as Map)
          : <String, dynamic>{};
      setState(() => _applyServerAttendanceData(data));
      _syncAttendancePolling();
      return;
    }
    setState(() => _applyClosedSession(_todayWorkDuration.inSeconds));
  }

  Future<void> _loadAttendance({Map<String, dynamic>? fallbackOpen}) async {
    final result = await widget.apiService.getCurrentAttendance();
    if (!mounted) return;
    if (result['success'] != true) {
      // Keep optimistic state from check-in/out response if server summary fails.
      if (fallbackOpen != null && _attendanceIsOpen(fallbackOpen)) {
        setState(() {
          _applyOpenSession(fallbackOpen);
          _syncAttendancePolling();
        });
        await _loadBreakInfo();
      }
      return;
    }

    final data = result['data'] is Map
        ? Map<String, dynamic>.from(result['data'] as Map)
        : <String, dynamic>{};

    final wasClockedIn = _isClockedIn;
    setState(() => _applyServerAttendanceData(data, fallbackOpen: fallbackOpen, fromServer: true));
    await _mergeBreakStatus();
    _syncAttendancePolling();
    unawaited(_persistLocalState());

    // Break list for panel only — main counters come from attendance/current.
    if (_isClockedIn || _onBreak) {
      await _loadBreakInfo();
    }

    if (_isClockedIn) {
      if (AppSession.mayCaptureScreenshots && widget.screenshotService?.isRunning != true) {
        widget.screenshotService?.startCapture();
      }
    } else {
      if (wasClockedIn && widget.screenshotService?.isRunning == true) {
        widget.screenshotService?.stopCapture();
      }
    }
  }

  Future<void> _loadUserData() async {
    final userData = await UserDataService.getUserData();
    if (!mounted) return;
    setState(() {
      _companyName = userData['company_name'] ?? '';
      _fullName = userData['full_name'] ?? widget.username;
      _designation = userData['designation'] ?? '';
      _department = userData['department'] ?? '';
    });
  }

  void _startClock() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      if (_timer.isClockedIn || _timer.isOnBreak) {
        _maybePersistLocalState();
      }
      _startClock();
    });
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _syncConsentFromPrefs();
      _loadAttendance().then((_) {
        if (mounted) setState(() => _breakRefresh++);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recordUserActivity();
    _syncConsentFromPrefs();
  }

  Future<void> _syncConsentFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    AppSession.setConsent(p.getBool('screenshot_monitoring_consent') ?? false);
    if (mounted) setState(() {});
  }

  void _recordUserActivity() {
    widget.screenshotService?.recordActivity();
  }

  Future<void> _toggleClock() async {
    if (_isProcessing) return;
    if (_effectiveOnBreak) {
      _showSnackBar('End break first, then clock out', AppTheme.warning);
      return;
    }
    _recordUserActivity();
    setState(() => _isProcessing = true);

    try {
      if (_isClockedIn) {
        // Re-sync before checkout — local timer can drift if server session already ended.
        await _loadAttendance();
        if (!mounted) return;
        if (_effectiveOnBreak) {
          _showSnackBar('End break first, then clock out', AppTheme.warning);
          return;
        }
        if (!_isClockedIn) {
          await _loadBreakInfo();
          _showSnackBar('Session already ended — status updated', AppTheme.warning);
          return;
        }

        final result = await widget.apiService.checkOut();
        if (!mounted) return;
        if (result['success'] == true) {
          final actionData = result['data'] is Map
              ? Map<String, dynamic>.from(result['data'] as Map)
              : null;
          if (actionData != null) {
            setState(() => _applyServerAttendanceData(actionData));
            _syncAttendancePolling();
          } else {
            await _loadAttendance();
          }
          if (mounted && _isClockedIn) {
            setState(() {
              _applyClosedSession(_liveWorkSeconds, breakSeconds: _liveBreakSeconds);
            });
            _attendancePollTimer?.cancel();
          }
          if (mounted) setState(() => _breakRefresh++);
          widget.screenshotService?.stopCapture();
          unawaited(_persistLocalState());
          _showSnackBar('Checked out successfully', AppTheme.success);
        } else {
          final err = result['error']?.toString() ?? 'Unknown error';
          final errLower = err.toLowerCase();
          final alreadyOut = errLower.contains('no active check-in') ||
              errLower.contains('attendance state did not update');
          if (alreadyOut) {
            await _forceClosedSession();
            widget.screenshotService?.stopCapture();
            if (mounted) setState(() => _breakRefresh++);
            _showSnackBar('Checked out successfully', AppTheme.success);
            return;
          }
          await AppDialog.alert(
            context: context,
            title: 'Check-out failed',
            message: err,
          );
        }
      } else {
        final result = await widget.apiService.checkIn();
        if (!mounted) return;
        if (result['success'] == true) {
          final actionData = result['data'] is Map
              ? Map<String, dynamic>.from(result['data'] as Map)
              : null;
          final att = _attendanceFromActionResult(actionData);
          if (actionData != null && actionData['today_work_duration'] != null) {
            setState(() => _applyServerAttendanceData(actionData, fallbackOpen: att));
            _syncAttendancePolling();
          } else if (att != null && _attendanceIsOpen(att)) {
            setState(() {
              _applyOpenSession(att);
              _timer.onClockIn(
                priorWorkSeconds: _liveWorkSeconds,
                priorBreakSeconds: _liveBreakSeconds,
              );
              _syncAttendancePolling();
            });
            await _loadAttendance(fallbackOpen: att);
          } else {
            await _loadAttendance(fallbackOpen: att);
          }
          if (mounted) setState(() => _breakRefresh++);
          unawaited(_persistLocalState());
          if (AppSession.mayCaptureScreenshots) {
            unawaited(widget.screenshotService?.startCapture());
            if (Platform.isLinux || Platform.isMacOS) {
              _showSnackBar(
                'Checked in — screen capture runs in background',
                AppTheme.success,
              );
            } else {
              _showSnackBar('Checked in — monitoring active', AppTheme.success);
            }
          } else if (PlatformCapabilities.screenshotMonitoring) {
            _showSnackBar(
              'Checked in — enable screenshots under Me → Profile',
              AppTheme.warning,
            );
          } else {
            _showSnackBar('Checked in successfully', AppTheme.success);
          }
        } else {
          await AppDialog.alert(
            context: context,
            title: 'Check-in failed',
            message: result['error']?.toString() ?? 'Unknown error',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    final type = color == AppTheme.success
        ? AppToastType.success
        : color == AppTheme.warning
            ? AppToastType.warning
            : color == AppTheme.danger
                ? AppToastType.error
                : AppToastType.info;
    AppToast.show(context, message: message, type: type, duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final todayTotal = _todayNetWork;
    final todayBreak = _todayBreakDuration;
    final pad = Responsive.pagePadding(context);
    final displayName =
        _fullName.trim().isNotEmpty ? _fullName.trim() : widget.username;

    return GestureDetector(
      onTap: _recordUserActivity,
      onPanDown: (_) => _recordUserActivity(),
      child: AppTheme.homeGlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(pad, 12, pad, 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              'Aims',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _buildQuickActionButtons(),
                          const SizedBox(height: 14),
                          _buildTimeHubCard(todayTotal, todayBreak, displayName),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeHubCard(
    Duration todayTotal,
    Duration todayBreak,
    String displayName,
  ) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _workingDate != null
                          ? 'Work day · ${DateFormat('dd MMM yyyy').format(DateTime.parse(_workingDate!))}'
                          : DateFormat('EEEE, dd MMM yyyy').format(_now),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _scheduleSubtitle(displayName),
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _liveStatusPill(),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _timeStat(
                  label: 'Work Time',
                  value: _formatDuration(todayTotal),
                  color: AppTheme.success,
                  live: _isClockedIn && !_effectiveOnBreak,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timeStat(
                  label: 'Break Time',
                  value: _formatDuration(todayBreak),
                  color: AppTheme.warning,
                  live: _effectiveOnBreak,
                ),
              ),
            ],
          ),
          if (_isWorkingSession) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: AppTheme.taskFieldDecoration(borderRadius: 10),
              child: Text(
                _effectiveOnBreak
                    ? 'On break · work ${_formatDuration(_todayNetWork)} · end break to clock out'
                    : 'Clocked in · today ${_formatDuration(_todayNetWork)} total',
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _buildClockButton(),
        ],
      ),
    );
  }

  Widget _timeStat({
    required String label,
    required String value,
    required Color color,
    bool live = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: AppTheme.taskFieldDecoration(borderRadius: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: live
                      ? color
                      : AppTheme.textMuted.withValues(alpha: 0.85),
                  letterSpacing: 1.2,
                ),
              ),
              if (live) ...[
                const SizedBox(width: 6),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
              letterSpacing: 1,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveStatusPill() {
    Color color;
    String label;
    if (_effectiveOnBreak) {
      color = AppTheme.warning;
      label = 'ON BREAK';
    } else if (_isClockedIn) {
      color = AppTheme.success;
      label = 'CLOCKED IN';
    } else {
      color = AppTheme.textMuted;
      label = 'CLOCKED OUT';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isClockedIn || _effectiveOnBreak ? 0.18 : 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildClockButton() {
    final onBreak = _effectiveOnBreak;
    final clockOutBlocked = onBreak;
    final canTakeBreak = _isClockedIn && !onBreak;
    final canEndBreak = onBreak;
    return Row(
      children: [
        Expanded(
          child: _buildPremiumActionButton(
            label: (_isClockedIn || onBreak) ? 'Clock Out' : 'Clock In',
            icon: (_isClockedIn || onBreak) ? Icons.logout_rounded : Icons.login_rounded,
            isPrimary: !_isClockedIn && !onBreak,
            isDanger: (_isClockedIn || onBreak) && !clockOutBlocked,
            onTap: (_isProcessing || clockOutBlocked) ? null : _toggleClock,
            isProcessing: _isProcessing,
            disabled: clockOutBlocked && (_isClockedIn || onBreak),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildPremiumActionButton(
            label: canEndBreak ? 'End Break' : 'Take Break',
            icon: canEndBreak ? Icons.play_arrow_rounded : Icons.coffee_rounded,
            isPrimary: false,
            isBreak: canTakeBreak || canEndBreak,
            isOnBreak: canEndBreak,
            onTap: _isBreakBusy
                ? null
                : (canEndBreak
                    ? _quickEndBreak
                    : (canTakeBreak ? () => _showBreakDialog() : null)),
            disabled: !canTakeBreak && !canEndBreak,
            isProcessing: _isBreakBusy,
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool isPrimary = false,
    bool isDanger = false,
    bool isBreak = false,
    bool isOnBreak = false,
    bool isProcessing = false,
    bool disabled = false,
  }) {
    final accent = isDanger
        ? AppTheme.danger
        : isPrimary
            ? AppTheme.primary
            : isOnBreak
                ? const Color(0xFF78350F)
                : isBreak
                    ? AppTheme.warning
                    : AppTheme.primaryBright;

    final highlighted = !disabled && (isPrimary || isDanger || isBreak || isOnBreak);
    final breakEndActive = !disabled && isOnBreak;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            gradient: highlighted
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: (isBreak || isOnBreak)
                        ? [
                            AppTheme.warning.withValues(alpha: breakEndActive ? 0.72 : 0.55),
                            const Color(0xFFD97706).withValues(alpha: breakEndActive ? 0.55 : 0.38),
                          ]
                        : [
                            accent.withValues(alpha: 0.95),
                            accent.withValues(alpha: 0.72),
                          ],
                  )
                : null,
            color: disabled
                ? Colors.white.withValues(alpha: 0.06)
                : (!highlighted)
                    ? Colors.white.withValues(alpha: 0.06)
                    : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: disabled
                  ? Colors.white.withValues(alpha: 0.1)
                  : (isBreak || isOnBreak)
                      ? AppTheme.warning.withValues(alpha: breakEndActive ? 0.85 : 0.65)
                      : (isPrimary || isDanger)
                          ? Colors.white.withValues(alpha: 0.28)
                          : Colors.white.withValues(alpha: 0.12),
              width: (isBreak || isOnBreak) ? 1.5 : 1,
            ),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: (isBreak || isOnBreak ? AppTheme.warning : accent)
                          .withValues(alpha: breakEndActive ? 0.5 : 0.35),
                      blurRadius: breakEndActive ? 22 : 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isProcessing
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        color: disabled
                            ? AppTheme.textMuted
                            : (isBreak || isOnBreak)
                                ? const Color(0xFFFFF7ED)
                                : (isPrimary || isDanger)
                                    ? Colors.white
                                    : AppTheme.primaryBright,
                        size: 22,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: disabled
                              ? AppTheme.textMuted
                              : (isBreak || isOnBreak)
                                  ? const Color(0xFFFFF7ED)
                                  : (isPrimary || isDanger)
                                      ? Colors.white
                                      : AppTheme.primaryBright,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  String _scheduleSubtitle(String displayName) {
    final sched = _effectiveSchedule;
    if (sched == null) return 'Welcome back, $displayName';
    final inT = sched['expected_check_in']?.toString() ?? '';
    final outT = sched['expected_check_out']?.toString() ?? '';
    if (inT.isEmpty || outT.isEmpty) return 'Welcome back, $displayName';
    final overnight = sched['is_overnight'] == true;
    final hours = overnight ? 'Expected $inT → $outT' : 'Expected $inT – $outT';
    return '$hours · $displayName';
  }

  Future<void> _quickEndBreak() async {
    if (!_effectiveOnBreak || _isBreakBusy) return;
    setState(() => _isBreakBusy = true);
    try {
      final r = await widget.apiService.endBreak();
      if (!mounted) return;
      if (r['success'] == true) {
        setState(() {
          _timer.onBreakEnd();
          _onBreak = false;
          _breakStartTime = null;
          _isClockedIn = true;
        });
        await _loadAttendance();
        if (mounted) setState(() => _breakRefresh++);
        unawaited(_persistLocalState());
        if (AppSession.mayCaptureScreenshots) {
          unawaited(widget.screenshotService?.startCapture());
        }
        _showSnackBar('Welcome back — work timer resumed', AppTheme.success);
      } else {
        _showSnackBar(r['error']?.toString() ?? 'Could not end break', AppTheme.danger);
      }
    } finally {
      if (mounted) setState(() => _isBreakBusy = false);
    }
  }

  Future<void> _showBreakDialog() async {
    await AppBottomSheet.show(
      context: context,
      title: 'Break Management',
      child: BreakPanel(
        apiService: widget.apiService,
        screenshotService: widget.screenshotService,
        isClockedIn: _isWorkingSession,
        refreshToken: _breakRefresh,
        alwaysVisible: true,
        compact: false,
        onBreakChanged: (onBreak, {breakStart}) {
          setState(() {
            _onBreak = onBreak;
            _breakStartTime = onBreak ? breakStart : null;
            if (onBreak) {
              _isClockedIn = true;
              _timer.onBreakStart(at: breakStart);
            } else {
              _timer.onBreakEnd();
            }
          });
          unawaited(_persistLocalState());
          _loadAttendance();
          if (mounted) setState(() => _breakRefresh++);
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }

  // Quick action row — same card family as Daily Report
  Widget _buildQuickActionButtons() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: _buildActionButton(
              'Activity',
              Icons.timeline_rounded,
              AppTheme.featureChat,
              () => AppNavigation.instance.openActivity(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: _buildActionButton(
              'Report',
              Icons.assignment_outlined,
              AppTheme.featureReport,
              () => _showReportDialog(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: _buildActionButton(
              'Logout',
              Icons.logout_rounded,
              AppTheme.danger,
              () => _confirmLogout(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: AppTheme.taskCardDecoration(borderRadius: 16).copyWith(
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReportDialog() async {
    await AppBottomSheet.show(
      context: context,
      title: 'Daily Report',
      child: ClosingReportPanel(
        apiService: widget.apiService,
        refreshToken: _reportRefresh,
        onSubmitted: () {
          if (mounted) setState(() => _reportRefresh++);
        },
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirm = await AppDialog.confirm(
      context: context,
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      confirmLabel: 'Logout',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (confirm == true && widget.onLogout != null) {
      widget.onLogout!();
    }
  }
}
