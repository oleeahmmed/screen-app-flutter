import '../app_session.dart';
import 'attendance_cache.dart';
import 'attendance_work_time.dart';
import 'api_service.dart';

/// Clock in / clock out — server totals are the source of truth.
/// Local tick only adds elapsed seconds since the last good snapshot.
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

  int get liveWorkSeconds {
    if (!isClockedIn || isOnBreak || workTickAt == null) {
      return workSeconds.clamp(0, _max);
    }
    final extra = DateTime.now().difference(workTickAt!).inSeconds;
    if (extra <= 0) return workSeconds.clamp(0, _max);
    return (workSeconds + extra).clamp(0, _max);
  }

  int get liveBreakSeconds {
    if (!isOnBreak || breakTickAt == null) return breakSeconds.clamp(0, _max);
    final extra = DateTime.now().difference(breakTickAt!).inSeconds;
    if (extra <= 0) return breakSeconds.clamp(0, _max);
    return (breakSeconds + extra).clamp(0, _max);
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
    }
  }

  /// Net worked seconds already counted on the server (check-in/out − breaks).
  int _serverNetSeconds(Map<String, dynamic> data) {
    final direct = data['today_work_seconds'];
    if (direct is num && direct.round() >= 0) {
      final n = direct.round();
      if (n > 0 || data['today_work_duration'] == null) return n;
    }

    final fromDur = parseDuration(data['today_work_duration']);
    if (fromDur > 0) return fromDur;

    final shiftStart = AttendanceWorkTime.shiftStart(shiftWindow, effectiveSchedule);
    final shiftEnd = AttendanceWorkTime.shiftEnd(shiftWindow, effectiveSchedule);
    if (sessionsToday.isNotEmpty && shiftStart != null && shiftEnd != null) {
      return AttendanceWorkTime.netWorkSeconds(
        sessions: sessionsToday,
        breakSeconds: breakSeconds,
        shiftStart: shiftStart,
        shiftEnd: shiftEnd,
        now: DateTime.now(),
      );
    }

    var fromSessions = 0;
    for (final s in sessionsToday) {
      final secs = s['shift_seconds'] ?? s['gross_seconds'];
      if (secs is num) fromSessions += secs.round();
    }
    return fromSessions > 0 ? (fromSessions - breakSeconds).clamp(0, _max) : 0;
  }

  DateTime _tickOrigin(Map<String, dynamic> data) {
    final localNow = DateTime.now();
    final parsed = parseDt(data['server_now']);
    // A future server_now freezes the UI timer until the device clock catches up.
    if (parsed == null || parsed.isAfter(localNow)) return localNow;
    return parsed;
  }

  /// Apply server payload from check-in, check-out, break, or status.
  void apply(Map<String, dynamic> data) {
    final prevLive = liveWorkSeconds;
    final wasWorking = isClockedIn && !isOnBreak;
    final wasOnBreak = isOnBreak;

    isClockedIn = data['is_clocked_in'] == true;
    isOnBreak = data['on_break'] == true;
    AppSession.setOnBreak(isOnBreak);
    workingDate = data['working_date']?.toString();

    final sched = data['schedule'] ?? data['effective_schedule'];
    if (sched is Map) {
      effectiveSchedule = Map<String, dynamic>.from(sched);
    }

    _applyShiftAndSessions(data);
    breakSeconds = parseDuration(
      data['today_break_duration'] ?? data['today_break_seconds'],
    );

    final serverNet = _serverNetSeconds(data);
    final tickAt = _tickOrigin(data);

    if (isClockedIn && !isOnBreak) {
      breakTickAt = null;
      breakExpectedBackAt = null;

      // Status polls / home revisits must not reset a running timer to 0.
      if (wasWorking && workTickAt != null && (serverNet - prevLive).abs() <= 8) {
        return;
      }

      if (serverNet <= 0 && prevLive > 2 && (wasWorking || wasOnBreak)) {
        workSeconds = prevLive;
        workTickAt = DateTime.now();
      } else {
        workSeconds = serverNet;
        workTickAt = tickAt;
      }
      return;
    }

    if (isOnBreak) {
      workSeconds = serverNet > 0 ? serverNet : (prevLive > 0 ? prevLive : 0);
      workTickAt = null;
      final brk = data['active_break'] ?? data['break'];
      breakTickAt =
          brk is Map ? parseDt(brk['break_start']) ?? DateTime.now() : DateTime.now();
      breakExpectedBackAt = brk is Map ? parseDt(brk['expected_back']) : null;
      return;
    }

    workSeconds = serverNet;
    workTickAt = null;
    breakTickAt = null;
    breakExpectedBackAt = null;
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
