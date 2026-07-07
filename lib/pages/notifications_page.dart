import 'package:flutter/material.dart';
import 'dart:async';

import '../services/api_service.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/notification_ui.dart';
import '../utils/platform_capabilities.dart';
import '../utils/responsive.dart';

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
      AppToast.success(context, 'All notifications marked as read');
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
        title: const Text('Clear all notifications?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This permanently removes all notifications from your list.',
          style: TextStyle(color: AppTheme.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Clear all'),
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
      AppToast.error(context, r['error']?.toString() ?? 'Could not clear notifications');
    }
  }

  int get _unread => _notifs.where((n) => n['is_read'] != true).length;

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  Widget _actionButtons() {
    if (_notifs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Responsive.pagePadding(context)),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_unread > 0)
            TextButton.icon(
              onPressed: _actionBusy ? null : _markAllRead,
              icon: _actionBusy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.done_all, size: 16, color: AppTheme.primaryBright),
              label: const Text('Mark all read', style: TextStyle(color: AppTheme.primaryBright, fontSize: 12)),
            ),
          TextButton.icon(
            onPressed: _actionBusy ? null : _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: AppTheme.danger),
            label: const Text('Clear all', style: TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);
    final pad = Responsive.pagePadding(context);

    return AppTheme.homeGlassBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 16, 8, 8),
              child: mobile ? _mobileHeader() : _desktopHeader(),
            ),
            _actionButtons(),
            const SizedBox(height: 4),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBright))
                  : _notifs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_none, size: 64, color: Colors.white.withValues(alpha: 0.15)),
                              const SizedBox(height: 12),
                              const Text(
                                'No notifications',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          color: AppTheme.primaryBright,
                          onRefresh: () => _load(),
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.symmetric(horizontal: pad),
                            itemCount: _notifs.length,
                            itemBuilder: (ctx, i) => _card(_notifs[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktopHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.notifications_rounded, color: AppTheme.warning, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              Text('$_unread unread', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _load(),
          icon: const Icon(Icons.refresh_rounded, color: AppTheme.textMuted),
          tooltip: 'Refresh',
        ),
        if (PlatformCapabilities.peerToPeerFileTransfer)
          IconButton(
            onPressed: () => AppNavigation.instance.openP2P(),
            icon: const Icon(Icons.swap_horiz_rounded, color: AppTheme.accent, size: 22),
            tooltip: 'Peer-to-peer file transfer',
          ),
      ],
    );
  }

  Widget _mobileHeader() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.notifications_rounded, color: AppTheme.warning, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Alerts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              Text('$_unread unread', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _load(),
          icon: const Icon(Icons.refresh_rounded, color: AppTheme.textMuted, size: 20),
          visualDensity: VisualDensity.compact,
        ),
        if (PlatformCapabilities.peerToPeerFileTransfer)
          IconButton(
            onPressed: () => AppNavigation.instance.openP2P(),
            icon: const Icon(Icons.swap_horiz_rounded, color: AppTheme.accent, size: 22),
            visualDensity: VisualDensity.compact,
            tooltip: 'Peer-to-peer file transfer',
          ),
      ],
    );
  }

  Future<void> _markOneRead(dynamic n) async {
    if (n['is_read'] == true) return;
    final id = n['id'];
    if (id == null) return;
    await widget.apiService.markNotificationRead(id is int ? id : int.parse('$id'));
    await _afterListMutation();
  }

  Widget _card(dynamic n) {
    final isRead = n['is_read'] == true;
    final type = n['notification_type']?.toString() ?? '';
    final color = NotificationUi.colorFor(type);

    return GestureDetector(
      onTap: () => _markOneRead(n),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white.withValues(alpha: 0.04) : const Color(0xFF3B82F6).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead ? Colors.white.withValues(alpha: 0.06) : const Color(0xFF3B82F6).withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(NotificationUi.iconFor(type), color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n['title'] ?? '',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n['message'] ?? '',
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _timeAgo(n['created_at']),
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.6), fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
