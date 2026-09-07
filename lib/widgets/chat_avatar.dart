import 'package:flutter/material.dart';

import '../config.dart';
import '../theme/app_theme.dart';

String resolveChatPhotoUrl(String? raw) {
  final path = raw?.trim() ?? '';
  if (path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  final origin = AppConfig.apiOrigin;
  if (path.startsWith('/')) return '$origin$path';
  return '$origin/$path';
}

/// Avatar for chat list rows and conversation headers (photo or initials fallback).
class ChatAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final String initials;
  final Color backgroundColor;
  final bool isGroup;
  final double radius;
  final bool showOnlineIndicator;
  final bool isOnline;
  final double? onlineIndicatorSize;
  final Color onlineBorderColor;

  const ChatAvatar({
    super.key,
    this.photoUrl,
    required this.name,
    required this.initials,
    required this.backgroundColor,
    this.isGroup = false,
    this.radius = 20,
    this.showOnlineIndicator = false,
    this.isOnline = false,
    this.onlineIndicatorSize,
    this.onlineBorderColor = AppTheme.bgDeep,
  });

  double get _size => radius * 2;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveChatPhotoUrl(photoUrl);
    final avatar = resolved.isNotEmpty ? _photoAvatar(resolved) : _fallbackAvatar();

    if (!showOnlineIndicator || isGroup) return avatar;

    final dot = onlineIndicatorSize ?? 12.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: isOnline ? AppTheme.success : const Color(0xFF6B7280),
              shape: BoxShape.circle,
              border: Border.all(color: onlineBorderColor, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _photoAvatar(String url) {
    return ClipOval(
      child: Image.network(
        url,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackAvatar(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallbackAvatar(loading: true);
        },
      ),
    );
  }

  Widget _fallbackAvatar({bool loading = false}) {
    if (isGroup) {
      return Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Center(
          child: Icon(
            Icons.group_rounded,
            color: Colors.white.withValues(alpha: loading ? 0.5 : 1),
            size: radius * 0.95,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white.withValues(alpha: loading ? 0.5 : 1),
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.65,
        ),
      ),
    );
  }
}
