import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';

class NotificationsPage extends StatefulWidget {
  final ApiService apiService;
  const NotificationsPage({required this.apiService});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<dynamic> _notifs = [];
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() { super.initState(); _load(); _pollTimer = Timer.periodic(Duration(seconds: 30), (_) => _load()); }
  @override
  void dispose() { _pollTimer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final r = await widget.apiService.getNotifications();
    if (r['success'] && mounted) setState(() { _notifs = r['data'] ?? []; _isLoading = false; });
    else if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _markAllRead() async {
    await widget.apiService.markAllNotificationsRead();
    _load();
  }

  int get _unread => _notifs.where((n) => n['is_read'] != true).length;

  IconData _typeIcon(String type) {
    switch (type) {
      case 'task_assigned': return Icons.assignment_ind;
      case 'task_completed': return Icons.check_circle;
      case 'task_updated': return Icons.edit_note;
      case 'message_received': return Icons.chat_bubble;
      case 'team_created': return Icons.group_add;
      case 'invitation_received': return Icons.mail;
      case 'employee_joined': return Icons.person_add;
      default: return Icons.notifications;
    }
  }
  Color _typeColor(String type) {
    switch (type) {
      case 'task_assigned': return Color(0xFF8B5CF6);
      case 'task_completed': return Color(0xFF10B981);
      case 'task_updated': return Color(0xFF3B82F6);
      case 'message_received': return Color(0xFF06B6D4);
      case 'team_created': return Color(0xFFF59E0B);
      case 'invitation_received': return Color(0xFFEC4899);
      case 'employee_joined': return Color(0xFF10B981);
      default: return Color(0xFF64748B);
    }
  }

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
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2563eb), Color(0xFF1e40af), Color(0xFF1e3a5f), Color(0xFF0f172a)])),
      child: SafeArea(child: Column(children: [
        // Header
        Padding(padding: EdgeInsets.fromLTRB(24, 20, 24, 12), child: Row(children: [
          Icon(Icons.notifications, color: Color(0xFFF59E0B), size: 28), SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Notifications', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('$_unread unread', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ])),
          if (_unread > 0) GestureDetector(onTap: _markAllRead, child: Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Color(0xFF8B5CF6).withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: Color(0xFF8B5CF6).withOpacity(0.3))),
            child: Text('Mark all read', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.w600)))),
          SizedBox(width: 8),
          GestureDetector(onTap: _load, child: Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.refresh, color: Colors.white54, size: 20))),
        ])),
        // List
        Expanded(child: _isLoading ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)))
          : _notifs.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.notifications_none, size: 64, color: Colors.white24), SizedBox(height: 12),
              Text('No Notifications', style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.bold))]))
          : ListView.builder(padding: EdgeInsets.symmetric(horizontal: 16), itemCount: _notifs.length, itemBuilder: (ctx, i) => _card(_notifs[i]))),
      ])),
    );
  }
  Widget _card(dynamic n) {
    final isRead = n['is_read'] == true;
    final type = n['notification_type'] ?? '';
    final color = _typeColor(type);
    return Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRead ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isRead ? Colors.white.withOpacity(0.05) : color.withOpacity(0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(_typeIcon(type), color: color, size: 20)),
        SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(n['title'] ?? '', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: isRead ? FontWeight.w500 : FontWeight.w700))),
            if (!isRead) Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          ]),
          SizedBox(height: 4),
          Text(n['message'] ?? '', style: TextStyle(color: Colors.white54, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          SizedBox(height: 6),
          Row(children: [
            if (n['sender_name'] != null && (n['sender_name'] as String).isNotEmpty) ...[
              CircleAvatar(radius: 8, backgroundColor: Color(0xFF334155), child: Text((n['sender_name'] ?? '?')[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: 8))),
              SizedBox(width: 4), Text(n['sender_name'] ?? '', style: TextStyle(color: Colors.white38, fontSize: 10)),
              SizedBox(width: 8),
            ],
            Text(_timeAgo(n['created_at']), style: TextStyle(color: Colors.white24, fontSize: 10)),
          ]),
        ])),
      ]),
    );
  }
}
