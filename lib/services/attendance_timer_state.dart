/// Local work / break counters for the dashboard.
///
/// Work time ticks only while clocked in and not on break.
/// Break time ticks only while on break.
/// Clock-in/out and break transitions flush the active segment into totals.
class AttendanceTimerState {
  int completedWorkSeconds = 0;
  int completedBreakSeconds = 0;

  bool isClockedIn = false;
  bool isOnBreak = false;

  DateTime? _workTickStart;
  DateTime? _breakTickStart;

  static const int _maxDaySeconds = 86400 * 2;

  int get liveWorkSeconds {
    var total = completedWorkSeconds;
    if (isClockedIn && !isOnBreak && _workTickStart != null) {
      total += _elapsedSince(_workTickStart!);
    }
    return total.clamp(0, _maxDaySeconds);
  }

  int get liveBreakSeconds {
    var total = completedBreakSeconds;
    if (isOnBreak && _breakTickStart != null) {
      total += _elapsedSince(_breakTickStart!);
    }
    return total.clamp(0, _maxDaySeconds);
  }

  int _elapsedSince(DateTime start) =>
      DateTime.now().difference(start).inSeconds.clamp(0, _maxDaySeconds);

  void _flushWork() {
    if (_workTickStart == null) return;
    completedWorkSeconds =
        (completedWorkSeconds + _elapsedSince(_workTickStart!)).clamp(0, _maxDaySeconds);
    _workTickStart = null;
  }

  void _flushBreak() {
    if (_breakTickStart == null) return;
    completedBreakSeconds =
        (completedBreakSeconds + _elapsedSince(_breakTickStart!)).clamp(0, _maxDaySeconds);
    _breakTickStart = null;
  }

  void reset() {
    completedWorkSeconds = 0;
    completedBreakSeconds = 0;
    isClockedIn = false;
    isOnBreak = false;
    _workTickStart = null;
    _breakTickStart = null;
  }

  Map<String, dynamic> toJson() => {
        'completed_work_seconds': completedWorkSeconds,
        'completed_break_seconds': completedBreakSeconds,
        'is_clocked_in': isClockedIn,
        'is_on_break': isOnBreak,
        'work_tick_start': _workTickStart?.toIso8601String(),
        'break_tick_start': _breakTickStart?.toIso8601String(),
      };

  void restoreFromJson(Map<String, dynamic> json) {
    completedWorkSeconds = _readInt(json['completed_work_seconds']);
    completedBreakSeconds = _readInt(json['completed_break_seconds']);
    isClockedIn = json['is_clocked_in'] == true;
    isOnBreak = json['is_on_break'] == true;
    _workTickStart = _readDate(json['work_tick_start']);
    _breakTickStart = _readDate(json['break_tick_start']);
  }

  int _readInt(dynamic v) {
    if (v is int) return v.clamp(0, _maxDaySeconds);
    return (int.tryParse('$v') ?? 0).clamp(0, _maxDaySeconds);
  }

  DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  /// Sync bases from server without breaking local tick rules.
  void applyServerSnapshot({
    required int workSeconds,
    required int breakSeconds,
    required bool clockedIn,
    required bool onBreak,
    DateTime? breakStartedAt,
    DateTime? serverNow,
    bool preserveLocalOnBreak = false,
  }) {
    final anchor = serverNow ?? DateTime.now();
    final prevWork = liveWorkSeconds;
    final prevBreak = liveBreakSeconds;
    final wasOnBreak = isOnBreak;

    final effectiveOnBreak = onBreak || (preserveLocalOnBreak && wasOnBreak);

    isClockedIn = clockedIn || effectiveOnBreak;
    isOnBreak = effectiveOnBreak;
    _workTickStart = null;
    _breakTickStart = null;

    if (!isClockedIn) {
      completedWorkSeconds = workSeconds.clamp(0, _maxDaySeconds);
      completedBreakSeconds = breakSeconds.clamp(0, _maxDaySeconds);
      return;
    }

    if (effectiveOnBreak) {
      final breakStart = breakStartedAt ?? _breakTickStart ?? anchor;
      final activeBreakSecs =
          anchor.difference(breakStart).inSeconds.clamp(0, _maxDaySeconds);
      completedWorkSeconds = prevWork.clamp(0, _maxDaySeconds);
      if (workSeconds > completedWorkSeconds) {
        completedWorkSeconds = workSeconds.clamp(0, _maxDaySeconds);
      }
      final serverCompletedBreak =
          (breakSeconds - activeBreakSecs).clamp(0, _maxDaySeconds);
      final localCompletedBreak =
          (prevBreak - activeBreakSecs).clamp(0, _maxDaySeconds);
      completedBreakSeconds = serverCompletedBreak > localCompletedBreak
          ? serverCompletedBreak
          : localCompletedBreak;
      if (completedBreakSeconds < 0) completedBreakSeconds = 0;
      _breakTickStart = breakStart;
      return;
    }

    completedWorkSeconds = workSeconds.clamp(0, _maxDaySeconds);
    if (completedWorkSeconds < prevWork && prevWork > 0 && wasOnBreak) {
      completedWorkSeconds = prevWork;
    }
    completedBreakSeconds = breakSeconds.clamp(0, _maxDaySeconds);
    if (completedBreakSeconds < prevBreak) {
      completedBreakSeconds = prevBreak;
    }
    _workTickStart = anchor;
  }

  void onClockIn({
    int priorWorkSeconds = 0,
    int priorBreakSeconds = 0,
    DateTime? at,
  }) {
    isClockedIn = true;
    isOnBreak = false;
    completedWorkSeconds = priorWorkSeconds.clamp(0, _maxDaySeconds);
    completedBreakSeconds = priorBreakSeconds.clamp(0, _maxDaySeconds);
    _breakTickStart = null;
    _workTickStart = at ?? DateTime.now();
  }

  void onClockOut() {
    if (isOnBreak) onBreakEnd();
    _flushWork();
    isClockedIn = false;
    isOnBreak = false;
    _workTickStart = null;
    _breakTickStart = null;
  }

  void onBreakStart({DateTime? at}) {
    isClockedIn = true;
    _flushWork();
    isOnBreak = true;
    _workTickStart = null;
    _breakTickStart = at ?? DateTime.now();
  }

  void onBreakEnd({DateTime? at}) {
    if (!isOnBreak) return;
    if (at != null && _breakTickStart != null) {
      completedBreakSeconds = (completedBreakSeconds +
              at.difference(_breakTickStart!).inSeconds.clamp(0, _maxDaySeconds))
          .clamp(0, _maxDaySeconds);
      _breakTickStart = null;
    } else {
      _flushBreak();
    }
    isOnBreak = false;
    _breakTickStart = null;
    if (isClockedIn) {
      _workTickStart = at ?? DateTime.now();
    }
  }
}
