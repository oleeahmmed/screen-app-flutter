import '../config.dart';

/// Resolve monitor screenshot / video URLs from API (relative or absolute).
String? monitorMediaUrl(dynamic raw) {
  if (raw == null) return null;
  final url = raw.toString().trim();
  if (url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('//')) return 'https:$url';
  final origin = AppConfig.apiOrigin;
  if (url.startsWith('/')) return '$origin$url';
  if (url.startsWith('videos/')) return '$origin/media/$url';
  return '$origin/media/$url';
}
