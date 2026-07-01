// dashboard_page.dart — Home / time tracking hub (aims-webapps glass style)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_session.dart';
import '../services/api_service.dart';
import '../services/screenshot_service.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_shell.dart';
import '../widgets/break_panel.dart';
import '../widgets/closing_report_panel.dart';
import '../widgets/day_activity_timeline.dart';
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
  Duration _workDuration = Duration.zero;
  Duration _todayWorkDuration = Duration.zero;
  late DateTime _clockInTime;
  late DateTime _now;
  String _companyName = '';
  String _fullName = '';
  String _designation = '';
  String _department = '';
  bool _isProcessing = false;
  DateTime? _breakStartTime;
  int _completedBreakSeconds = 0;
  int _breakRefresh = 0;
  int _reportRefresh = 0;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockInTime = _now;
    _loadUserData();
    _loadAttendance().then((_) => _loadBreakInfo());
    _startClock();
  }

  Future<void> _loadBreakInfo() async {
    if (!_isClockedIn) {
      if (mounted) {
        setState(() {
          _onBreak = false;
          _breakStartTime = null;
          _completedBreakSeconds = 0;
        });
      }
      return;
    }

    final statusR = await widget.apiService.getBreakStatus();
    final myR = await widget.apiService.getMyBreaks();
    if (!mounted) return;

    var onBreak = _onBreak;
    DateTime? breakStart = _breakStartTime;
    var completedSecs = _completedBreakSeconds;

    if (myR['success'] == true) {
      final data = myR['data'] as Map<String, dynamic>? ?? {};
      final summary = data['summary'] as Map<String, dynamic>?;
      final totalMin = summary?['total_break_minutes'];
      completedSecs = (totalMin is int ? totalMin : int.tryParse('$totalMin') ?? 0) * 60;
    }

    if (statusR['success'] == true) {
      final st = statusR['data'] as Map<String, dynamic>? ?? {};
      onBreak = st['on_break'] == true;
      if (onBreak && st['break'] is Map) {
        final b = st['break'] as Map<String, dynamic>;
        breakStart = DateTime.tryParse(b['break_start']?.toString() ?? '')?.toLocal();
      } else if (!onBreak) {
        breakStart = null;
      }
    }

    if (mounted) {
      setState(() {
        _onBreak = onBreak;
        _breakStartTime = breakStart;
        _completedBreakSeconds = completedSecs;
      });
    }
  }

  Duration get _todayBreakDuration {
    var total = Duration(seconds: _completedBreakSeconds);
    if (_onBreak && _breakStartTime != null) {
      total += _now.difference(_breakStartTime!);
    }
    return total;
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

  Map<String, dynamic>? _attendanceFromActionResult(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in ['attendance', 'current_attendance']) {
      final raw = data[key];
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  void _applyOpenSession(Map<String, dynamic> current, {int? totalSeconds}) {
    final checkIn = _parseApiDateTime(current['check_in']) ?? DateTime.now();
    final now = DateTime.now();
    final sessionSeconds = now.difference(checkIn).inSeconds.clamp(0, 86400 * 2);
    final total = totalSeconds ?? sessionSeconds;
    final priorSeconds = (total - sessionSeconds).clamp(0, total);

    setState(() {
      _isClockedIn = true;
      _clockInTime = checkIn;
      _workDuration = Duration.zero;
      _todayWorkDuration = Duration(seconds: priorSeconds);
      _now = now;
    });
  }

  void _applyClosedSession(int totalSeconds) {
    setState(() {
      _isClockedIn = false;
      _onBreak = false;
      _workDuration = Duration.zero;
      _todayWorkDuration = Duration(seconds: totalSeconds);
    });
  }

  Future<void> _loadAttendance() async {
    final result = await widget.apiService.getCurrentAttendance();
    if (!mounted) return;
    if (result['success'] != true) return;

    final data = result['data'] is Map
        ? Map<String, dynamic>.from(result['data'] as Map)
        : <String, dynamic>{};
    final current = data['current_attendance'] is Map
        ? Map<String, dynamic>.from(data['current_attendance'] as Map)
        : null;
    final todayDuration = data['today_work_duration'] is Map
        ? Map<String, dynamic>.from(data['today_work_duration'] as Map)
        : null;
    final totalSeconds = _parseSeconds(todayDuration?['total_seconds']);

    if (_attendanceIsOpen(current)) {
      _applyOpenSession(current!, totalSeconds: totalSeconds);

      if (AppSession.mayCaptureScreenshots && widget.screenshotService?.isRunning != true) {
        widget.screenshotService?.startCapture();
      }
    } else {
      _applyClosedSession(totalSeconds);
      if (widget.screenshotService?.isRunning == true) {
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
    _recordUserActivity();
    setState(() => _isProcessing = true);

    try {
      if (_isClockedIn) {
        // Re-sync before checkout — local timer can drift if server session already ended.
        await _loadAttendance();
        if (!mounted) return;
        if (!_isClockedIn) {
          await _loadBreakInfo();
          _showSnackBar('Session already ended — status updated', AppTheme.warning);
          return;
        }

        final result = await widget.apiService.checkOut();
        if (!mounted) return;
        if (result['success'] == true) {
          await _loadAttendance();
          await _loadBreakInfo();
          if (mounted) setState(() => _breakRefresh++);
          widget.screenshotService?.stopCapture();
          _showSnackBar('Checked out successfully', AppTheme.success);
        } else {
          final err = result['error']?.toString() ?? 'Unknown error';
          final alreadyOut = err.toLowerCase().contains('no active check-in');
          if (alreadyOut) {
            await _loadAttendance();
            await _loadBreakInfo();
            widget.screenshotService?.stopCapture();
            if (mounted) setState(() => _breakRefresh++);
          }
          await AppDialog.alert(
            context: context,
            title: alreadyOut ? 'Already clocked out' : 'Check-out failed',
            message: alreadyOut
                ? 'Your session was already closed on the server. The dashboard has been updated.'
                : err,
          );
        }
      } else {
        final result = await widget.apiService.checkIn();
        if (!mounted) return;
        if (result['success'] == true) {
          final att = _attendanceFromActionResult(result['data'] as Map<String, dynamic>?);
          if (att != null && _attendanceIsOpen(att)) {
            _applyOpenSession(att);
          }
          await _loadAttendance();
          await _loadBreakInfo();
          if (mounted) setState(() => _breakRefresh++);
          if (AppSession.mayCaptureScreenshots) {
            widget.screenshotService?.startCapture();
            _showSnackBar('Checked in — monitoring active', AppTheme.success);
          } else {
            _showSnackBar(
              'Checked in — enable screenshots under Me → Profile',
              AppTheme.warning,
            );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  String _initials() {
    final name = _fullName.isNotEmpty ? _fullName : widget.username;
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    if (_isClockedIn) {
      _workDuration = _now.difference(_clockInTime);
    }

    final todayTotal = _todayWorkDuration + (_isClockedIn ? _workDuration : Duration.zero);
    final todayBreak = _todayBreakDuration;

    return GestureDetector(
      onTap: _recordUserActivity,
      onPanDown: (_) => _recordUserActivity(),
      child: AppShell(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
          child: _buildHeader(),
        ),
        scrollable: true,
        padding: EdgeInsets.zero,
        wide: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: LayoutBuilder(
            builder: (context, c) {
              final useTwoCol = c.maxWidth >= 980;
              final leftChildren = <Widget>[
                _buildTimeHubCard(todayTotal, todayBreak),
                const SizedBox(height: 12),
                BreakPanel(
                  apiService: widget.apiService,
                  screenshotService: widget.screenshotService,
                  isClockedIn: _isClockedIn,
                  refreshToken: _breakRefresh,
                  alwaysVisible: true,
                  compact: true,
                  onBreakChanged: (onBreak) {
                    setState(() => _onBreak = onBreak);
                    _loadBreakInfo();
                    if (mounted) setState(() => _breakRefresh++);
                  },
                ),
              ];
              final rightChildren = <Widget>[
                ClosingReportPanel(
                  apiService: widget.apiService,
                  refreshToken: _reportRefresh,
                  onSubmitted: () => setState(() => _reportRefresh++),
                ),
                const SizedBox(height: 12),
                DayActivityTimeline(
                  apiService: widget.apiService,
                  refreshToken: _breakRefresh,
                  isClockedIn: _isClockedIn,
                  clockInTime: _isClockedIn ? _clockInTime : null,
                  onBreak: _onBreak,
                  collapsible: true,
                  initiallyExpanded: false,
                ),
              ];

              if (useTwoCol) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 11,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: leftChildren,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 9,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: rightChildren,
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...leftChildren,
                  const SizedBox(height: 12),
                  ...rightChildren,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary.withValues(alpha: 0.9), AppTheme.accent.withValues(alpha: 0.7)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (b) => AppTheme.titleGradient().createShader(b),
                child: Text(
                  'Hi, ${_fullName.isNotEmpty ? _fullName : widget.username}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_designation.isNotEmpty || _department.isNotEmpty)
                Text(
                  [_designation, _department].where((s) => s.isNotEmpty).join(' · '),
                  style: AppTheme.caption.copyWith(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              if (_companyName.isNotEmpty)
                Text(
                  _companyName,
                  style: TextStyle(fontSize: 10, color: AppTheme.textMuted.withValues(alpha: 0.65)),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeHubCard(Duration todayTotal, Duration todayBreak) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, dd MMM yyyy').format(_now),
                  style: AppTheme.caption.copyWith(fontSize: 13),
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
                  label: "Today's Work",
                  value: _formatDuration(todayTotal),
                  color: AppTheme.success,
                  live: _isClockedIn && !_onBreak,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timeStat(
                  label: "Today's Break",
                  value: _formatDuration(todayBreak),
                  color: AppTheme.warning,
                  live: _onBreak,
                ),
              ),
            ],
          ),
          if (_isClockedIn) ...[
            const SizedBox(height: 14),
            Text(
              _onBreak
                  ? 'Session paused · clocked in at ${DateFormat('HH:mm').format(_clockInTime)}'
                  : 'Session · ${_formatDuration(_workDuration)} since ${DateFormat('HH:mm').format(_clockInTime)}',
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(fontSize: 11),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: live ? 0.45 : 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.6),
              ),
              if (live) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveStatusPill() {
    Color color;
    String label;
    if (_onBreak) {
      color = AppTheme.warning;
      label = 'On break';
    } else if (_isClockedIn) {
      color = AppTheme.success;
      label = 'Clocked in';
    } else {
      color = AppTheme.textMuted;
      label = 'Clocked out';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildClockButton() {
    final clockedIn = _isClockedIn;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isProcessing ? null : _toggleClock,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: clockedIn
                ? AppTheme.danger.withValues(alpha: 0.18)
                : AppTheme.success.withValues(alpha: 0.18),
            border: Border.all(
              color: clockedIn
                  ? AppTheme.danger.withValues(alpha: 0.4)
                  : AppTheme.success.withValues(alpha: 0.4),
            ),
          ),
          child: Center(
            child: _isProcessing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        clockedIn ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: clockedIn ? AppTheme.danger : AppTheme.success,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        clockedIn ? 'Clock Out' : 'Clock In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: clockedIn ? AppTheme.danger : AppTheme.success,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }
}
