import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

enum _EventKind { clockIn, clockOut, breakStart, breakEnd }

class _TimelineEvent {
  final DateTime at;
  final _EventKind kind;
  final String title;
  final String subtitle;
  final String? durationLabel;
  final bool isActive;
  final bool isLive;

  const _TimelineEvent({
    required this.at,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.durationLabel,
    this.isActive = false,
    this.isLive = false,
  });
}

/// Today's clock-in / break activity log for the Home screen.
class DayActivityTimeline extends StatefulWidget {
  final ApiService apiService;
  final int refreshToken;
  final bool isClockedIn;
  final DateTime? clockInTime;
  final bool onBreak;
  final bool collapsible;
  final bool initiallyExpanded;

  const DayActivityTimeline({
    super.key,
    required this.apiService,
    this.refreshToken = 0,
    this.isClockedIn = false,
    this.clockInTime,
    this.onBreak = false,
    this.collapsible = false,
    this.initiallyExpanded = false,
  });

  @override
  State<DayActivityTimeline> createState() => _DayActivityTimelineState();
}

class _DayActivityTimelineState extends State<DayActivityTimeline> {
  bool _loading = true;
  bool _initialLoad = true;
  List<_TimelineEvent> _events = [];
  Map<String, dynamic>? _breakSummary;
  int _sessionCount = 0;
  int _breakCount = 0;
  Timer? _liveTimer;
  int _loadGeneration = 0;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _load();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DayActivityTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load(silent: _events.isNotEmpty);
      return;
    }
    if (oldWidget.isClockedIn != widget.isClockedIn ||
        oldWidget.onBreak != widget.onBreak ||
        oldWidget.clockInTime != widget.clockInTime) {
      _syncLiveFlags();
    }
  }

  void _syncLiveFlags() {
    if (_events.isEmpty) return;
    setState(() {
      _events = _events.map((e) {
        if (e.kind == _EventKind.clockIn && e.isActive) {
          return _TimelineEvent(
            at: e.at,
            kind: e.kind,
            title: e.title,
            subtitle: e.subtitle,
            durationLabel: e.durationLabel,
            isActive: e.isActive,
            isLive: widget.isClockedIn,
          );
        }
        if (e.kind == _EventKind.breakStart && e.isActive) {
          return _TimelineEvent(
            at: e.at,
            kind: e.kind,
            title: e.title,
            subtitle: e.subtitle,
            durationLabel: e.durationLabel,
            isActive: e.isActive,
            isLive: widget.onBreak,
          );
        }
        return e;
      }).toList();
    });
    _updateLiveTimer();
  }

  void _updateLiveTimer() {
    _liveTimer?.cancel();
    if (_events.any((e) => e.isLive)) {
      _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  bool _attendanceIsOpen(Map raw) {
    final checkOut = raw['check_out'];
    if (checkOut == null) return true;
    if (checkOut is String && checkOut.trim().isEmpty) return true;
    return false;
  }

  DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  String _fmtTime(DateTime dt) => DateFormat('HH:mm').format(dt);

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  String _fmtDurationFromSeconds(int? secs) {
    if (secs == null || secs <= 0) return '—';
    return _fmtDuration(Duration(seconds: secs));
  }

  String _durationLabelFor(_TimelineEvent e) {
    if (!e.isLive) return e.durationLabel ?? '—';
    final dur = DateTime.now().difference(e.at);
    if (e.kind == _EventKind.breakStart) return '${_fmtDuration(dur)} · on break';
    if (e.kind == _EventKind.clockIn) return '${_fmtDuration(dur)} · live';
    return e.durationLabel ?? '—';
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    if (!silent && _initialLoad) {
      setState(() => _loading = true);
    }
    final now = DateTime.now();
    final events = <_TimelineEvent>[];

    final attResult = await widget.apiService.getAttendanceList();
    final breakResult = await widget.apiService.getMyBreaks();
    final breakStatus = await widget.apiService.getBreakStatus();

    if (!mounted || generation != _loadGeneration) return;

    var sessionsToday = 0;
    if (attResult['success'] == true) {
      final list = attResult['data'] as List<dynamic>? ?? [];
      for (final raw in list) {
        if (raw is! Map) continue;
        final checkIn = _parseDt(raw['check_in']);
        if (checkIn == null || !_isToday(checkIn)) continue;
        sessionsToday++;

        final checkOut = _parseDt(raw['check_out']);
        final isOpen = _attendanceIsOpen(raw);
        final durSecs = raw['duration_seconds'];
        final dur = durSecs is int
            ? Duration(seconds: durSecs)
            : (isOpen ? now.difference(checkIn) : checkOut!.difference(checkIn));

        events.add(_TimelineEvent(
          at: checkIn,
          kind: _EventKind.clockIn,
          title: 'Clock In',
          subtitle: DateFormat('EEEE, dd MMM').format(checkIn),
          durationLabel: isOpen ? '${_fmtDuration(dur)} · live' : _fmtDuration(dur),
          isActive: isOpen,
          isLive: isOpen && widget.isClockedIn,
        ));

        if (checkOut != null) {
          events.add(_TimelineEvent(
            at: checkOut,
            kind: _EventKind.clockOut,
            title: 'Clock Out',
            subtitle: 'Session ended',
            durationLabel: _fmtDurationFromSeconds(durSecs is int ? durSecs : dur.inSeconds),
          ));
        }
      }
    }

    var breaksToday = 0;
    Map<String, dynamic>? summary;
    if (breakResult['success'] == true) {
      final data = breakResult['data'] as Map<String, dynamic>? ?? {};
      summary = data['summary'] as Map<String, dynamic>?;
      final breaks = data['breaks'] as List<dynamic>? ?? [];
      for (final raw in breaks) {
        if (raw is! Map) continue;
        final start = _parseDt(raw['break_start']);
        if (start == null) continue;
        breaksToday++;

        final expected = _parseDt(raw['expected_back']);
        final back = _parseDt(raw['actual_back']);
        final isActive = raw['is_active'] == true;
        final totalMin = raw['total_break_minutes'];
        final durLabel = isActive
            ? '${_fmtDuration(now.difference(start))} · on break'
            : (totalMin != null ? '${totalMin}m' : (back != null ? _fmtDuration(back.difference(start)) : '—'));

        events.add(_TimelineEvent(
          at: start,
          kind: _EventKind.breakStart,
          title: isActive ? 'On Break' : 'Break',
          subtitle: [
            'Started ${_fmtTime(start)}',
            if (expected != null) 'Back by ${_fmtTime(expected)}',
          ].join(' · '),
          durationLabel: durLabel,
          isActive: isActive,
          isLive: isActive && widget.onBreak,
        ));

        if (back != null) {
          events.add(_TimelineEvent(
            at: back,
            kind: _EventKind.breakEnd,
            title: 'Back from Break',
            subtitle: 'Returned at ${_fmtTime(back)}',
            durationLabel: totalMin != null ? '${totalMin}m break' : _fmtDuration(back.difference(start)),
          ));
        }
      }
    }

    // Ensure active break from status if list lagged
    if (breakStatus['success'] == true) {
      final st = breakStatus['data'] as Map<String, dynamic>? ?? {};
      if (st['on_break'] == true && st['break'] is Map) {
        final b = st['break'] as Map<String, dynamic>;
        final start = _parseDt(b['break_start']);
        final hasStart = start != null && events.any((e) => e.kind == _EventKind.breakStart && e.isLive);
        if (start != null && !hasStart) {
          final expected = _parseDt(b['expected_back']);
          events.add(_TimelineEvent(
            at: start,
            kind: _EventKind.breakStart,
            title: 'On Break',
            subtitle: [
              'Started ${_fmtTime(start)}',
              if (expected != null) 'Back by ${_fmtTime(expected)}',
            ].join(' · '),
            durationLabel: '${_fmtDuration(now.difference(start))} · on break',
            isActive: true,
            isLive: true,
          ));
          breaksToday++;
        }
      }
    }

    if (!mounted || generation != _loadGeneration) return;

    events.sort((a, b) => b.at.compareTo(a.at));

    setState(() {
      _events = events;
      _breakSummary = summary;
      _sessionCount = sessionsToday;
      _breakCount = breaksToday;
      _loading = false;
      _initialLoad = false;
    });
    _updateLiveTimer();
  }

  Color _colorFor(_EventKind kind, {bool live = false}) {
    switch (kind) {
      case _EventKind.clockIn:
        return live ? AppTheme.success : AppTheme.success.withValues(alpha: 0.85);
      case _EventKind.clockOut:
        return AppTheme.danger;
      case _EventKind.breakStart:
        return live ? AppTheme.warning : const Color(0xFFF59E0B);
      case _EventKind.breakEnd:
        return AppTheme.primaryBright;
    }
  }

  IconData _iconFor(_EventKind kind) {
    switch (kind) {
      case _EventKind.clockIn:
        return Icons.login_rounded;
      case _EventKind.clockOut:
        return Icons.logout_rounded;
      case _EventKind.breakStart:
        return Icons.free_breakfast_rounded;
      case _EventKind.breakEnd:
        return Icons.check_circle_outline_rounded;
    }
  }

  Widget _buildHeader() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.collapsible ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.history_rounded, color: AppTheme.primaryBright, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Today's Activity",
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.collapsible && !_expanded
                          ? '$_sessionCount sessions · $_breakCount breaks · tap to expand'
                          : DateFormat('dd MMMM yyyy').format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_loading && widget.collapsible)
                Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppTheme.textMuted.withValues(alpha: 0.8),
                  size: 22,
                ),
              if (_expanded || !widget.collapsible)
                IconButton(
                  onPressed: _loading ? null : () => _load(silent: _events.isNotEmpty),
                  icon: Icon(Icons.refresh_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.8)),
                  tooltip: 'Refresh',
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showBody = !widget.collapsible || _expanded;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.glassPanel(borderRadius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (showBody) ...[
            const SizedBox(height: 14),
            Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryChip(Icons.play_circle_outline, 'Sessions', '$_sessionCount', AppTheme.success),
              _summaryChip(Icons.free_breakfast_outlined, 'Breaks', '$_breakCount', AppTheme.warning),
              _summaryChip(
                Icons.hourglass_bottom_rounded,
                'Break time',
                '${_breakSummary?['total_break_minutes'] ?? 0}m',
                AppTheme.primaryBright,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBright),
                ),
              ),
            )
          else if (_events.isEmpty)
            _emptyState()
          else
            ...List.generate(_events.length, (i) {
              final e = _events[i];
              final isLast = i == _events.length - 1;
              return _timelineRow(e, showLine: !isLast);
            }),
          ],
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 8, color: AppTheme.textMuted.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(Icons.timeline, size: 40, color: AppTheme.textMuted.withValues(alpha: 0.35)),
          const SizedBox(height: 10),
          const Text(
            'No activity yet today',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Clock in to start — breaks and sessions will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted.withValues(alpha: 0.8), height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(_TimelineEvent e, {required bool showLine}) {
    final color = _colorFor(e.kind, live: e.isLive);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: e.isLive ? 0.7 : 0.35), width: e.isLive ? 2 : 1),
                    boxShadow: e.isLive
                        ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, spreadRadius: 0)]
                        : null,
                  ),
                  child: Icon(_iconFor(e.kind), size: 16, color: color),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withValues(alpha: 0.4),
                            Colors.white.withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showLine ? 16 : 0, top: 2),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: e.isLive ? color.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: e.isLive ? color.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                e.title,
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (e.isLive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'LIVE',
                                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.subtitle,
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted.withValues(alpha: 0.9), height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _fmtTime(e.at),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (e.durationLabel != null || e.isLive) ...[
                          const SizedBox(height: 2),
                          Text(
                            _durationLabelFor(e),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
