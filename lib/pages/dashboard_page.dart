// dashboard_page.dart — Home / time tracking hub (aims-webapps glass style)

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_session.dart';
import '../services/api_service.dart';
import '../services/attendance_service.dart';
import '../services/attendance_work_time.dart';
import '../services/screenshot_service.dart';
import '../services/app_filter_prefs.dart';
import '../services/windows_app_capture.dart';
import '../utils/app_toast.dart';
import '../utils/platform_capabilities.dart';
import '../utils/responsive.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_filter_picker_sheet.dart';
import '../widgets/break_panel.dart';
import '../widgets/animated_glow_border.dart';

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
  final AttendanceService _attendance = AttendanceService();
  late DateTime _now;
  String _companyName = '';
  String _fullName = '';
  String _designation = '';
  String _department = '';
  bool _isProcessing = false;
  bool _isBreakBusy = false;
  bool _appFilterBusy = false;
  List<WindowsAppInfo> _allowedApps = const [];
  List<Map<String, dynamic>> _todayBreaks = [];
  Timer? _uiTickTimer;

  bool get _isClockedIn => _attendance.isClockedIn;
  bool get _onBreak => _attendance.isOnBreak;
  Duration get _todayNetWork => Duration(seconds: _attendance.liveWorkSeconds);
  Duration get _todayBreakDuration =>
      Duration(seconds: _attendance.liveBreakSeconds);
  String? get _workingDate => _attendance.workingDate;
  Map<String, dynamic>? get _effectiveSchedule => _attendance.effectiveSchedule;
  int get _breakCountToday => _todayBreaks.length;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _loadUserData();
    _loadAppFilterPrefs();
    _loadInitialStatus();
    _startUiTick();
    AppSession.setOpenSelectApps(_openAppPicker);
  }

  @override
  void dispose() {
    if (AppSession.openSelectApps == _openAppPicker) {
      AppSession.setOpenSelectApps(null);
    }
    _uiTickTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAppFilterPrefs() async {
    final apps = await AppFilterPrefs.loadAllowedApps();
    final mode = await AppFilterPrefs.loadCaptureMode();
    if (!mounted) return;
    AppSession.setCaptureMode(mode);
    AppSession.setSelectedAppsCount(apps.length);
    setState(() => _allowedApps = apps);
  }

  /// Start the correct capture path from employee.screenshot_capture_mode.
  Future<void> _resumeCaptureIfNeeded({bool promptForApps = false}) async {
    if (!AppSession.mayCaptureScreenshots) return;
    if (AppSession.usesAppWindowCapture) {
      if (_allowedApps.isEmpty) {
        widget.screenshotService?.stopCapture();
        if (promptForApps) {
          _showAttendanceToast(
            title: 'Select apps',
            message: 'Pick apps from the top bar, then capture starts automatically',
            type: AppToastType.warning,
            icon: Icons.apps_rounded,
          );
          unawaited(_openAppPicker());
        }
        return;
      }
      await widget.screenshotService?.startAppFilterCapture(_allowedApps);
      return;
    }
    await widget.screenshotService?.startCapture();
  }

  Future<void> _loadInitialStatus() async {
    await _attendance.loadStatus(widget.apiService);
    if (mounted) {
      setState(() {});
      await _loadBreakInfo();
      if (_isClockedIn) {
        if (_onBreak) {
          widget.screenshotService?.stopCapture();
        } else {
          await _resumeCaptureIfNeeded();
        }
      }
    }
  }

  Future<void> _loadBreakInfo() async {
    final myR = await widget.apiService.getMyBreaks(date: _workingDate);
    if (!mounted || myR['success'] != true) return;

    final data = myR['data'] as Map<String, dynamic>? ?? {};
    final rawBreaks = data['breaks'];
    if (rawBreaks is! List) return;

    setState(() {
      _todayBreaks = rawBreaks
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
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

  void _startUiTick() {
    _uiTickTimer?.cancel();
    _uiTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_isClockedIn) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _syncConsentFromPrefs();
      _loadAppFilterPrefs();
      _loadInitialStatus().then((_) {
        if (mounted) setState(() {});
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
    if (_onBreak) {
      _showAttendanceToast(
        title: 'End break first',
        message: 'Finish your break before clocking out',
        type: AppToastType.warning,
        icon: Icons.warning_amber_rounded,
      );
      return;
    }
    _recordUserActivity();
    setState(() => _isProcessing = true);

    try {
      if (_isClockedIn) {
        final result = await _attendance.clockOut(widget.apiService);
        if (!mounted) return;
        if (result['success'] == true) {
          setState(() {});
          widget.screenshotService?.stopCapture();
          _showAttendanceToast(
            title: 'Clocked Out',
            message: 'Work session ended successfully',
            type: AppToastType.success,
            icon: Icons.power_rounded,
          );
        } else {
          await AppDialog.alert(
            context: context,
            title: 'Check-out failed',
            message: result['error']?.toString() ?? 'Unknown error',
          );
        }
      } else {
        final result = await _attendance.clockIn(widget.apiService);
        if (!mounted) return;
        if (result['success'] == true) {
          setState(() {});
          await _loadBreakInfo();
          if (AppSession.mayCaptureScreenshots) {
            // Start screen capture immediately so live monitor shows online.
            unawaited(_resumeCaptureIfNeeded(promptForApps: true));
            final usingAppFilter = AppSession.usesAppWindowCapture;
            _showAttendanceToast(
              title: 'Clocked In',
              message: usingAppFilter
                  ? (_allowedApps.isEmpty
                      ? 'Work timer started · select apps to begin capture'
                      : 'Work timer started · app window monitoring')
                  : 'Work timer started · screen monitoring active',
              type: AppToastType.success,
              icon: Icons.how_to_reg_rounded,
            );
          } else if (PlatformCapabilities.screenshotMonitoring) {
            _showAttendanceToast(
              title: 'Clocked In',
              message: 'Enable screenshots under Me → Profile',
              type: AppToastType.warning,
              icon: Icons.how_to_reg_rounded,
            );
          } else {
            _showAttendanceToast(
              title: 'Clocked In',
              message: 'Work timer started',
              type: AppToastType.success,
              icon: Icons.how_to_reg_rounded,
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

  void _showAttendanceToast({
    required String title,
    required String message,
    required AppToastType type,
    IconData? icon,
  }) {
    AppToast.show(
      context,
      title: title,
      message: message,
      type: type,
      icon: icon,
      placement: AppToastPlacement.top,
      duration: const Duration(seconds: 3),
    );
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
    );
  }

  Widget _buildTimeHubCard(
    Duration todayTotal,
    Duration todayBreak,
    String displayName,
  ) {
    return Container(
      decoration: AppTheme.loginShell().copyWith(
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isClockedIn)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _workDayLabel(),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _shiftInfoLabel(displayName),
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.9),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              _liveStatusPill(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _timeStat(
                  label: 'Work Time',
                  value: _formatDuration(todayTotal),
                  statusText: _workStatusLabel(),
                  statusColor: _workStatusColor(),
                  live: _isClockedIn && !_onBreak,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timeStat(
                  label: 'Break Time',
                  value: _formatDuration(todayBreak),
                  statusText: _breakStatusLabel(),
                  statusColor: _onBreak ? AppTheme.warning : const Color(0xFFF59E0B),
                  live: _onBreak,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildActionArea(),
          if (Platform.isWindows &&
              PlatformCapabilities.screenshotMonitoring &&
              AppSession.usesAppWindowCapture) ...[
            const SizedBox(height: 14),
            _buildCaptureModeHint(),
          ],
        ],
      ),
    );
  }

  String _workStatusLabel() {
    if (_onBreak) return 'Paused';
    if (_isClockedIn) return 'Active';
    return 'Idle';
  }

  Color _workStatusColor() {
    if (_onBreak) return AppTheme.warning;
    if (_isClockedIn) return AppTheme.success;
    return AppTheme.textMuted;
  }

  String _breakStatusLabel() {
    final count = _breakCountToday;
    if (count == 0) return 'No breaks';
    final label = count == 1 ? '1 Break' : '$count Breaks';
    if (_onBreak) return '$label · Now';
    return label;
  }

  Widget _timeStat({
    required String label,
    required String value,
    required String statusText,
    required Color statusColor,
    bool live = false,
  }) {
    final card = Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: AppTheme.loginInsetDecoration(
        borderRadius: 12,
        emphasized: live,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: live
                  ? AppTheme.accent
                  : AppTheme.textMuted.withValues(alpha: 0.85),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
              letterSpacing: 0.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );

    return AnimatedGlowBorder(
      active: live,
      color: statusColor,
      borderRadius: 12,
      child: card,
    );
  }

  Widget _liveStatusPill() {
    Color color;
    String label;
    final monitoring = !_onBreak &&
        _isClockedIn &&
        (widget.screenshotService?.isRunning == true);
    if (_onBreak) {
      color = AppTheme.warning;
      label = 'ON BREAK';
    } else if (monitoring) {
      color = AppTheme.success;
      label = 'MONITORING';
    } else if (_isClockedIn) {
      color = AppTheme.accent;
      label = 'CLOCKED IN';
    } else {
      color = AppTheme.danger;
      label = 'CLOCKED OUT';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.14),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.55)),
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

  static const Color _clockInGreen = Color(0xFF059669);
  static const Color _clockInGreenDark = Color(0xFF047857);
  static const Color _clockInGreenBorder = Color(0xFF34D399);
  static const Color _clockOutRed = Color(0xFFDC2626);
  static const Color _clockOutRedDark = Color(0xFF991B1B);
  static const Color _coffeeBrown = Color(0xFF92400E);
  static const Color _coffeeBrownDark = Color(0xFF5C3D1E);

  Widget _buildActionArea() {
    if (_onBreak) {
      return _EndBreakBlinkButton(
        isProcessing: _isBreakBusy,
        onTap: _isBreakBusy ? null : _quickEndBreak,
      );
    }
    if (_isClockedIn) {
      return Row(
        children: [
          Expanded(
            child: _buildSecondaryActionButton(
              label: 'CLOCK OUT',
              icon: Icons.power_rounded,
              accent: AppTheme.danger,
              enabled: !_isProcessing,
              isProcessing: _isProcessing,
              onTap: _toggleClock,
              powerStyle: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildSecondaryActionButton(
              label: 'TAKE BREAK',
              icon: Icons.local_cafe_rounded,
              accent: AppTheme.primary,
              enabled: !_isBreakBusy,
              onTap: _showBreakPicker,
            ),
          ),
        ],
      );
    }
    return _buildClockInButton();
  }

  Widget _buildCaptureModeHint() {
    final n = _allowedApps.length;
    final running = widget.screenshotService?.isAppFilterMode == true &&
        widget.screenshotService?.isRunning == true;
    final text = !AppSession.mayCaptureScreenshots
        ? 'Enable screenshots under Me → Profile'
        : n == 0
            ? 'App window mode · use Select Apps in the top bar'
            : running
                ? 'Capturing $n selected app${n == 1 ? '' : 's'} when on top'
                : '$n app${n == 1 ? '' : 's'} selected · Clock In to monitor';
    return Row(
      children: [
        Icon(
          Icons.filter_center_focus_rounded,
          size: 16,
          color: running ? AppTheme.success : AppTheme.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppTheme.textMuted.withValues(alpha: 0.95),
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openAppPicker() async {
    if (_appFilterBusy) return;
    setState(() => _appFilterBusy = true);
    try {
      final picked = await AppFilterPickerSheet.show(
        context,
        initialSelectedApps: _allowedApps,
      );
      if (!mounted || picked == null) return;
      await AppFilterPrefs.saveAllowedApps(picked);
      setState(() => _allowedApps = picked);
      if (_isClockedIn && !_onBreak && AppSession.mayCaptureScreenshots) {
        await _resumeCaptureIfNeeded();
      }
    } finally {
      if (mounted) setState(() => _appFilterBusy = false);
    }
  }

  Widget _buildClockInButton() {
    final canClockIn = !_isProcessing;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canClockIn ? _toggleClock : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _clockInGreenBorder,
              width: canClockIn ? 2 : 1,
            ),
            boxShadow: [
              if (canClockIn)
                BoxShadow(
                  color: AppTheme.success.withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_clockInGreen, _clockInGreenDark],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: const Icon(
                          Icons.how_to_reg_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _isProcessing
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation(Colors.white),
                                  ),
                                ),
                              )
                            : const Text(
                                'CLOCK IN',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryActionButton({
    required String label,
    required IconData icon,
    required Color accent,
    required bool enabled,
    required VoidCallback? onTap,
    bool isProcessing = false,
    bool powerStyle = false,
  }) {
    final useLoginInset = !enabled && (label == 'TAKE BREAK' || label == 'END BREAK');
    final foreground = _actionForeground(label, enabled);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          height: 72,
          decoration: enabled
              ? _enabledActionDecoration(label)
              : useLoginInset
                  ? AppTheme.loginInsetDecoration(borderRadius: 12)
                  : AppTheme.glassPanel(darker: true, borderRadius: 12),
          child: isProcessing
              ? Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(
                        enabled ? foreground : AppTheme.textMuted,
                      ),
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (powerStyle)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: enabled
                              ? Colors.white.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            color: enabled
                                ? Colors.white.withValues(alpha: 0.55)
                                : AppTheme.textMuted.withValues(alpha: 0.25),
                            width: 2,
                          ),
                          boxShadow: enabled
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: foreground,
                        ),
                      )
                    else
                      Icon(
                        icon,
                        size: 22,
                        color: foreground,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Color _actionForeground(String label, bool enabled) {
    if (!enabled) return AppTheme.textMuted.withValues(alpha: 0.55);
    return Colors.white;
  }

  BoxDecoration _enabledActionDecoration(String label) {
    switch (label) {
      case 'CLOCK OUT':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_clockOutRed, _clockOutRedDark],
          ),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.danger.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        );
      case 'TAKE BREAK':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_coffeeBrown, _coffeeBrownDark],
          ),
          border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: _coffeeBrown.withValues(alpha: 0.32),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        );
      case 'END BREAK':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_clockOutRed, _clockOutRedDark],
          ),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.danger.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        );
      default:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primaryBright, AppTheme.primary],
          ),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.32),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        );
    }
  }

  String _workDayLabel() {
    if (_workingDate != null) {
      return 'Work day - ${DateFormat('dd MMM yyyy').format(DateTime.parse(_workingDate!))}';
    }
    return 'Work day - ${DateFormat('dd MMM yyyy').format(_now)}';
  }

  String _shiftInfoLabel(String displayName) {
    final sched = _effectiveSchedule;
    if (sched == null) return 'Welcome back, $displayName';
    final inT = sched['expected_check_in']?.toString() ?? '';
    final outT = sched['expected_check_out']?.toString() ?? '';
    if (inT.isEmpty || outT.isEmpty) return 'Welcome back, $displayName';
    final overnight = sched['is_overnight'] == true;
    final hours = overnight ? 'Shift $inT → $outT' : 'Shift $inT – $outT';
    final win = _attendance.shiftWindow ?? sched;
    final winStart = AttendanceWorkTime.parseDt(win['start'] ?? win['shift_window_start']);
    final winEnd = AttendanceWorkTime.parseDt(win['end'] ?? win['shift_window_end']);
    if (winStart != null && winEnd != null && overnight) {
      final fmt = (DateTime d) =>
          '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      return '$hours (${fmt(winStart)} → ${fmt(winEnd)}) · $displayName';
    }
    return '$hours · $displayName';
  }

  String _scheduleSubtitle(String displayName) => _shiftInfoLabel(displayName);

  Future<void> _quickEndBreak() async {
    if (!_onBreak || _isBreakBusy) return;
    setState(() => _isBreakBusy = true);
    try {
      final r = await _attendance.endBreak(widget.apiService);
      if (!mounted) return;
      if (r['success'] == true) {
        setState(() {});
        await _loadBreakInfo();
        if (AppSession.mayCaptureScreenshots) {
          unawaited(_resumeCaptureIfNeeded());
        }
        _showAttendanceToast(
          title: 'Back to Work',
          message: 'Break ended · work timer resumed',
          type: AppToastType.success,
          icon: Icons.work_rounded,
        );
      } else {
        _showAttendanceToast(
          title: 'Could not end break',
          message: r['error']?.toString() ?? 'Please try again',
          type: AppToastType.error,
          icon: Icons.work_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _isBreakBusy = false);
    }
  }

  Future<void> _showBreakPicker() async {
    if (!_isClockedIn || _onBreak) return;
    await showBreakStartSheet(
      context: context,
      apiService: widget.apiService,
      screenshotService: widget.screenshotService,
      onStarted: () async {
        if (!mounted) return;
        await _attendance.loadStatus(widget.apiService);
        if (!mounted) return;
        setState(() {});
        await _loadBreakInfo();
        if (AppSession.mayCaptureScreenshots) {
          widget.screenshotService?.stopCapture();
        }
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }
}

/// Full-width red END BREAK button with pulsing blink while on break.
class _EndBreakBlinkButton extends StatefulWidget {
  final bool isProcessing;
  final VoidCallback? onTap;

  const _EndBreakBlinkButton({
    required this.isProcessing,
    this.onTap,
  });

  @override
  State<_EndBreakBlinkButton> createState() => _EndBreakBlinkButtonState();
}

class _EndBreakBlinkButtonState extends State<_EndBreakBlinkButton>
    with SingleTickerProviderStateMixin {
  static const Color _red = Color(0xFFDC2626);
  static const Color _redDark = Color(0xFF991B1B);

  late final AnimationController _blink;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _blink, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = _pulse.value;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isProcessing ? null : widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              height: 78,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(_red, const Color(0xFFEF4444), glow * 0.35)!,
                    Color.lerp(_redDark, _red, glow * 0.25)!,
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22 + 0.38 * glow),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.danger.withValues(alpha: 0.18 + 0.42 * glow),
                    blurRadius: 10 + 18 * glow,
                    spreadRadius: 1.5 * glow,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
      child: widget.isProcessing
          ? const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 2),
                  ),
                  child: const Icon(Icons.work_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                const Text(
                  'END BREAK',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
    );
  }
}
