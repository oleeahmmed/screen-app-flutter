/// Parse API / WebSocket timestamps and display them in the device timezone.
///
/// Django/DRF usually sends UTC (`…Z` or `+00:00`). Naive ISO strings without
/// an offset are treated as UTC. Display always uses [DateTime.toLocal] so
/// Bangladesh (Asia/Dhaka) and any other device timezone work automatically.
library;

final RegExp _tzSuffix = RegExp(r'([zZ]|[+-]\d{2}:?\d{2})$');

bool _hasTimezone(String value) => _tzSuffix.hasMatch(value.trim());

/// Parse an API timestamp into local device time.
DateTime? parseApiDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toLocal();

  final s = raw.toString().trim();
  if (s.isEmpty) return null;

  DateTime? dt;
  if (_hasTimezone(s)) {
    dt = DateTime.tryParse(s);
  } else {
    // Naive ISO from some endpoints — assume UTC.
    dt = DateTime.tryParse(s.contains('T') ? '${s}Z' : s);
  }
  return dt?.toLocal();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Bubble footer time, e.g. `19:42`.
String formatChatBubbleTime(dynamic raw) {
  final local = parseApiDateTime(raw);
  if (local == null || local.year < 2000) return '';
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// Chat list / inbox time: today time, Yesterday, weekday, or short date.
String formatChatListTime(dynamic raw) {
  final local = parseApiDateTime(raw);
  if (local == null || local.year < 2000) return '';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final t = '${_two(local.hour)}:${_two(local.minute)}';

  if (day == today) return t;
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  if (now.difference(local).inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[local.weekday - 1];
  }
  return '${local.day}/${local.month}/${local.year % 100}';
}

/// Presence line, e.g. `last seen today at 19:42`.
String formatLastSeen(dynamic raw) {
  final local = parseApiDateTime(raw);
  if (local == null) return 'offline';

  final now = DateTime.now();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return 'last seen just now';
  if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes} min ago';

  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final t = '${_two(local.hour)}:${_two(local.minute)}';

  if (day == today) return 'last seen today at $t';
  if (day == today.subtract(const Duration(days: 1))) return 'last seen yesterday at $t';
  return 'last seen ${local.day}/${local.month} at $t';
}

/// Message info / details, e.g. `8 Sep 2026, 19:42`.
String formatChatDetailTime(dynamic raw) {
  final local = parseApiDateTime(raw);
  if (local == null || local.year < 2000) return raw?.toString() ?? '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${local.day} ${months[local.month - 1]} ${local.year}, ${_two(local.hour)}:${_two(local.minute)}';
}
