import 'attendance_cache.dart';
import 'attendance_work_time.dart';
import 'api_service.dart';

/// Clock in / clock out — server is the only source of truth.
/// Work time is counted only inside the expected shift window.
class AttendanceService {
  bool isClockedIn = false;
  bool isOnBreak = false;
  int workSeconds = 0;
  int breakSeconds = 0;
  DateTime? workTickAt;
  DateTime? breakTickAt;
  String? workingDate;
  DateTime? breakExpectedBackAt;
  Map<String, dynamic>? effectiveSchedule;
  Map<String, dynamic>? shiftWindow;
  List<Map<String, dynamic>> sessionsToday = [];

  static const int _max = 86400 * 2;

  DateTime? get _shiftStart =>
      AttendanceWorkTime.shiftStart(shiftWindow, effectiveSchedule);

  DateTime? get _shiftEnd =>
      AttendanceWorkTime.shiftEnd(shiftWindow, effectiveSchedule);

  int get liveWorkSeconds {
    if (!isClockedIn || isOnBreak) return workSeconds.clamp(0, _max);
    if (workTickAt == null) return workSeconds.clamp(0, _max);
    final extra = AttendanceWorkTime.elapsedInShift(
      tickAt: workTickAt!,
      shiftStart: _shiftStart,
      shiftEnd: _shiftEnd,
    );
    return (workSeconds + extra).clamp(0, _max);
  }

  int get liveBreakSeconds {
    if (!isOnBreak || breakTickAt == null) return breakSeconds.clamp(0, _max);
    return (breakSeconds + DateTime.now().difference(breakTickAt!).inSeconds)
        .clamp(0, _max);
  }

  static int parseDuration(dynamic v) => parseDurationSeconds(v);

  static DateTime? parseDt(dynamic v) => AttendanceWorkTime.parseDt(v);

  void _applyShiftAndSessions(Map<String, dynamic> data) {
    final win = data['shift_window'];
    if (win is Map) {
      shiftWindow = Map<String, dynamic>.from(win);
    }

    final rawSessions = data['sessions_today'];
    if (rawSessions is List) {
      sessionsToday = rawSessions
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else {
      sessionsToday = [];
    }
  }

  void _resolveWorkSeconds(Map<String, dynamic> data, DateTime serverNow) {
    breakSeconds = parseDuration(data['today_break_duration']);

    final shiftStart = _shiftStart;
    final shiftEnd = _shiftEnd;
    if (sessionsToday.isNotEmpty && shiftStart != null && shiftEnd != null) {
      workSeconds = AttendanceWorkTime.netWorkSeconds(
        sessions: sessionsToday,
        breakSeconds: breakSeconds,
        shiftStart: shiftStart,
        shiftEnd: shiftEnd,
        now: serverNow,
      );
      return;
    }

    workSeconds = parseDuration(
      data['today_work_duration'] ?? data['today_work_seconds'],
    );
  }

  /// Apply server payload from check-in, check-out, or status.
  void apply(Map<String, dynamic> data) {
    isClockedIn = data['is_clocked_in'] == true;
    isOnBreak = data['on_break'] == true;
    workingDate = data['working_date']?.toString();

    final sched = data['schedule'] ?? data['effective_schedule'];
    if (sched is Map) {
      effectiveSchedule = Map<String, dynamic>.from(sched);
    }

    _applyShiftAndSessions(data);

    final serverNow = parseDt(data['server_now']) ?? DateTime.now();
    _resolveWorkSeconds(data, serverNow);

    if (isClockedIn && !isOnBreak) {
      workTickAt = serverNow;
      breakTickAt = null;
      breakExpectedBackAt = null;
    } else if (isOnBreak) {
      workTickAt = null;
      final brk = data['active_break'];
      breakTickAt =
          brk is Map ? parseDt(brk['break_start']) ?? serverNow : serverNow;
      breakExpectedBackAt = brk is Map ? parseDt(brk['expected_back']) : null;
    } else {
      workTickAt = null;
      breakTickAt = null;
      breakExpectedBackAt = null;
    }
  }

  Future<bool> loadStatus(ApiService api) async {
    final r = await api.getClockStatus();
    if (r['success'] == true && r['data'] is Map) {
      apply(Map<String, dynamic>.from(r['data'] as Map));
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> clockIn(ApiService api) async {
    final r = await api.checkIn();
    if (r['success'] == true && r['data'] is Map) {
      apply(Map<String, dynamic>.from(r['data'] as Map));
    }
    return r;
  }

  Future<Map<String, dynamic>> clockOut(ApiService api) async {
    final r = await api.checkOut();
    if (r['success'] == true && r['data'] is Map) {
      apply(Map<String, dynamic>.from(r['data'] as Map));
    }
    return r;
  }

  Future<Map<String, dynamic>> startBreak(
    ApiService api, {
    DateTime? expectedBack,
  }) async {
    final r = await api.startBreak(expectedBack: expectedBack);
    if (r['success'] == true && r['data'] is Map) {
      apply(Map<String, dynamic>.from(r['data'] as Map));
    }
    return r;
  }

  Future<Map<String, dynamic>> endBreak(ApiService api) async {
    final r = await api.endBreak();
    if (r['success'] == true && r['data'] is Map) {
      apply(Map<String, dynamic>.from(r['data'] as Map));
    }
    return r;
  }
}
