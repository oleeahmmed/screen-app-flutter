import 'attendance_cache.dart';

/// Net work time inside the expected shift window (sessions − breaks).
class AttendanceWorkTime {
  static DateTime? parseDt(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  static DateTime? shiftStart(
    Map<String, dynamic>? shiftWindow,
    Map<String, dynamic>? schedule,
  ) {
    return parseDt(
      shiftWindow?['start'] ?? schedule?['shift_window_start'],
    );
  }

  static DateTime? shiftEnd(
    Map<String, dynamic>? shiftWindow,
    Map<String, dynamic>? schedule,
  ) {
    return parseDt(
      shiftWindow?['end'] ?? schedule?['shift_window_end'],
    );
  }

  static int overlapSeconds(
    DateTime rangeStart,
    DateTime rangeEnd,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final start = rangeStart.isAfter(windowStart) ? rangeStart : windowStart;
    final end = rangeEnd.isBefore(windowEnd) ? rangeEnd : windowEnd;
    if (!end.isAfter(start)) return 0;
    return end.difference(start).inSeconds;
  }

  /// Sum check-in/out sessions clipped to [shiftStart, shiftEnd).
  static int grossSecondsFromSessions({
    required List<dynamic> sessions,
    required DateTime shiftStart,
    required DateTime shiftEnd,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    var total = 0;
    for (final raw in sessions) {
      if (raw is! Map) continue;
      final checkIn = parseDt(raw['check_in']);
      if (checkIn == null) continue;
      final checkOut = parseDt(raw['check_out']);
      final end = checkOut ?? at;
      final secs = raw['shift_seconds'] ?? raw['gross_seconds'];
      if (secs is num && (raw['check_out'] != null || raw['is_open'] != true)) {
        total += secs.round();
      } else {
        total += overlapSeconds(checkIn, end, shiftStart, shiftEnd);
      }
    }
    return total;
  }

  /// Gross work inside shift minus break seconds (server break total preferred).
  static int netWorkSeconds({
    required List<dynamic> sessions,
    required int breakSeconds,
    required DateTime shiftStart,
    required DateTime shiftEnd,
    DateTime? now,
  }) {
    final gross = grossSecondsFromSessions(
      sessions: sessions,
      shiftStart: shiftStart,
      shiftEnd: shiftEnd,
      now: now,
    );
    return (gross - breakSeconds).clamp(0, 86400 * 2);
  }

  /// Seconds to add after [tickAt] while clocked in, capped to the shift window.
  static int elapsedInShift({
    required DateTime tickAt,
    required DateTime? shiftStart,
    required DateTime? shiftEnd,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    if (shiftEnd != null && tickAt.isAfter(shiftEnd)) return 0;
    if (shiftStart != null && at.isBefore(shiftStart)) return 0;

    var from = tickAt;
    if (shiftStart != null && from.isBefore(shiftStart)) {
      from = shiftStart;
    }
    var until = at;
    if (shiftEnd != null && until.isAfter(shiftEnd)) {
      until = shiftEnd;
    }
    if (!until.isAfter(from)) return 0;
    return until.difference(from).inSeconds;
  }

  static int parseServerDuration(dynamic v) => parseDurationSeconds(v);
}
