import 'package:flutter/material.dart';
import 'dart:async';

import '../services/api_service.dart';
import '../services/app_navigation.dart';
import '../services/chat_notification.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/notification_ui.dart';
import '../utils/responsive.dart';
import '../utils/whatsapp_avatar.dart';
import 'task_detail_page.dart';

class NotificationsPage extends StatefulWidget {
  final ApiService apiService;
  final int refreshToken;
  final Future<void> Function()? onNotificationsChanged;

  const NotificationsPage({
    super.key,
    required this.apiService,
    this.refreshToken = 0,
    this.onNotificationsChanged,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<dynamic> _notifs = [];
  bool _isLoading = true;
  bool _actionBusy = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) => _load(silent: true));
  }

  @override
  void didUpdateWidget(covariant NotificationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load(silent: true);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    final r = await widget.apiService.getNotifications();
    if (r['success'] && mounted) {
      setState(() {
        _notifs = r['data'] ?? [];
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _afterListMutation() async {
    await widget.onNotificationsChanged?.call();
    await _load(silent: true);
  }

  Future<void> _markAllRead() async {
    if (_actionBusy || _unread == 0) return;
    setState(() => _actionBusy = true);
    final r = await widget.apiService.markAllNotificationsRead();
    if (!mounted) return;
    setState(() => _actionBusy = false);
    if (r['success'] == true) {
      AppToast.success(context, 'All marked as read');
      await _afterListMutation();
    } else {
      AppToast.updateFailed(context, r['error']?.toString() ?? 'Could not mark all read');
    }
  }

  Future<void> _clearAll() async {
    if (_actionBusy || _notifs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: const Text('Clear all?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This permanently removes every notification.',
          style: TextStyle(color: AppTheme.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _actionBusy = true);
    final r = await widget.apiService.clearAllNotifications();
    if (!mounted) return;
    setState(() => _actionBusy = false);
    if (r['success'] == true) {
      AppToast.success(context, 'Notifications cleared');
      await _afterListMutation();
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Could not clear');
    }
  }

  int get _unread => _notifs.where((n) => n['is_read'] != true).length;

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = Responsive.pagePadding(context);
    final bottom = Responsive.bottomNavInset(context) + 16;

    return SafeArea(
      top: false,
      bottom: false,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
              child: _header(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBright))
                  : _notifs.isEmpty
                      ? _emptyState()
                      : RefreshIndicator(
                          color: const Color(0xFF00A884),
                          backgroundColor: AppTheme.surface,
                          onRefresh: () => _load(),
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(0, 0, 0, bottom),
                            itemCount: _notifs.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              thickness: 0.4,
                              color: Colors.white.withValues(alpha: 0.06),
                              indent: 78,
                            ),
                            itemBuilder: (_, i) => _card(_notifs[i]),
                          ),
                        ),
            ),
          ],
        ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _unread == 0 ? 'All caught up' : '$_unread unread',
                style: TextStyle(
                  color: _unread > 0 ? AppTheme.accent : AppTheme.textMuted.withValues(alpha: 0.9),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (_unread > 0)
          _iconAction(
            tooltip: 'Mark all read',
            icon: Icons.done_all_rounded,
            color: AppTheme.primaryBright,
            onTap: _actionBusy ? null : _markAllRead,
          ),
        if (_notifs.isNotEmpty)
          _iconAction(
            tooltip: 'Clear all',
            icon: Icons.delete_outline_rounded,
            color: AppTheme.danger,
            onTap: _actionBusy ? null : _clearAll,
          ),
      ],
    );
  }

  Widget _iconAction({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              width: 40,
              height: 40,
              decoration: AppTheme.loginInsetDecoration(borderRadius: 12),
              child: _actionBusy
                  ? Padding(
                      padding: const EdgeInsets.all(11),
                      child: CircularProgressIndicator(strokeWidth: 2, color: color),
                    )
                  : Icon(icon, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: AppTheme.loginInsetDecoration(borderRadius: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.9),
                      AppTheme.accent.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'No notifications',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Updates will appear here when something needs you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.9),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markOneRead(dynamic n) async {
    if (n is! Map || n['is_read'] == true) return;
    final id = n['id'];
    if (id == null) return;
    await widget.apiService.markNotificationRead(id is int ? id : int.parse('$id'));
    await _afterListMutation();
  }

  int? _taskIdFromNotification(dynamic n) {
    if (n is! Map) return null;
    for (final key in ['task_id', 'task']) {
      final parsed = _positiveInt(n[key]);
      if (parsed != null) return parsed;
    }
    final objectType = n['object_type']?.toString().toLowerCase() ?? '';
    if (objectType == 'task') {
      final parsed = _positiveInt(n['object_id']);
      if (parsed != null) return parsed;
    }
    final link = n['link']?.toString() ?? '';
    final match = RegExp(r'tasks?/(\d+)', caseSensitive: false).firstMatch(link);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  int? _positiveInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v > 0 ? v : null;
    if (v is num) {
      final n = v.round();
      return n > 0 ? n : null;
    }
    final n = int.tryParse('$v');
    return n != null && n > 0 ? n : null;
  }

  bool _isChatNotification(String type) {
    switch (type) {
      case 'new_message':
      case 'new_group_message':
      case 'mention':
      case 'group_added':
      case 'group_removed':
        return true;
      default:
        return false;
    }
  }

  Future<void> _onNotificationTap(dynamic n) async {
    unawaited(_markOneRead(n));
    final taskId = _taskIdFromNotification(n);
    if (taskId != null) {
      if (!mounted) return;
      openTaskDetailPage(
        context,
        apiService: widget.apiService,
        taskId: taskId,
      );
      return;
    }
    final type = n is Map ? n['notification_type']?.toString() ?? '' : '';
    if (_isChatNotification(type)) {
      final chat = n is Map ? ChatNotification.fromData(Map<String, dynamic>.from(n)) : null;
      AppNavigation.instance.goChatWithPeer(userId: chat?.peerId, groupId: chat?.groupId);
    }
  }

  Widget _card(dynamic n) {
    if (n is! Map) return const SizedBox.shrink();
    final map = Map<String, dynamic>.from(n);
    final isRead = map['is_read'] == true;
    final type = map['notification_type']?.toString() ?? '';
    final isChat = _isChatNotification(type);
    final color = isChat ? const Color(0xFF00A884) : NotificationUi.colorFor(type);
    final title = map['title']?.toString() ?? '';
    final message = map['message']?.toString() ?? '';
    final displayName = isChat ? ChatNotification.fromData(map).name : title;

    return Material(
      color: isRead ? Colors.transparent : const Color(0xFF0B141A).withValues(alpha: 0.55),
      child: InkWell(
        onTap: () => _onNotificationTap(n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color,
                child: isChat
                    ? Text(
                        WhatsAppAvatar.initials(displayName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      )
                    : Icon(NotificationUi.iconFor(type), color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isChat ? displayName : title,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeAgo(map['created_at']?.toString()),
                          style: TextStyle(
                            color: isRead ? AppTheme.textMuted.withValues(alpha: 0.75) : const Color(0xFF00A884),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        message,
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.95),
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: isRead ? FontWeight.w400 : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (!isRead) ...[
                const SizedBox(width: 10),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
