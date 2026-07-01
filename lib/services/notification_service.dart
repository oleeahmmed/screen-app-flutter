import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../utils/ws_connect.dart';
import 'api_service.dart';
import 'notification_sound.dart';

/// Real-time notifications via WebSocket (`/ws/chat/`) with polling fallback.
class NotificationService {
  NotificationService(this._api);

  final ApiService _api;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  int _reconnectDelayMs = 3000;
  bool _running = false;
  bool _connecting = false;
  int? _lastPushedNotificationId;

  int unreadCount = 0;

  final _pushController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get pushStream => _pushController.stream;

  void Function(int count)? onUnreadCountChanged;

  Duration get _pollInterval {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return const Duration(seconds: 15);
    }
    return const Duration(seconds: 30);
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await refreshUnreadCount();
    unawaited(_connectWebSocket());
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      refreshUnreadCount(playSoundOnIncrease: true);
    });
  }

  /// Reconnect WebSocket after app returns to foreground (mobile).
  Future<void> reconnect() async {
    if (!_running) return;
    await refreshUnreadCount(playSoundOnIncrease: true);
    unawaited(_connectWebSocket());
  }

  void stop() {
    _running = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _disconnectWebSocket();
    unreadCount = 0;
    onUnreadCountChanged?.call(0);
  }

  Future<void> refreshUnreadCount({bool playSoundOnIncrease = false}) async {
    if (!_running) return;
    final r = await _api.getNotificationUnreadCount();
    if (r['success'] != true) return;

    final n = (r['data']?['unread_count'] as num?)?.toInt() ?? 0;
    final increased = n > unreadCount;

    if (playSoundOnIncrease && increased) {
      await NotificationSound.playNotification();
      await _pushLatestUnreadIfNew();
    }

    unreadCount = n;
    onUnreadCountChanged?.call(unreadCount);
  }

  Future<void> _pushLatestUnreadIfNew() async {
    final r = await _api.getNotifications();
    if (r['success'] != true) return;
    final list = (r['data'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (list.isEmpty) return;

    final latest = list.first;
    final rawId = latest['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    if (id != null && id == _lastPushedNotificationId) return;
    _lastPushedNotificationId = id;
    _pushController.add(latest);
  }

  void _trackPushedId(Map<String, dynamic> data) {
    final rawId = data['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    if (id != null) _lastPushedNotificationId = id;
  }

  /// Refresh badge after mark-read / clear from the Alerts screen.
  Future<void> syncUnreadCount() async {
    final r = await _api.getNotificationUnreadCount();
    if (r['success'] != true) return;
    unreadCount = (r['data']?['unread_count'] as num?)?.toInt() ?? 0;
    onUnreadCountChanged?.call(unreadCount);
  }

  Future<void> _connectWebSocket() async {
    if (!_running || _connecting) return;
    _connecting = true;
    _disconnectWebSocket();

    try {
      await _api.ensureAuth();
      final token = _api.token;
      if (token == null || token.isEmpty) {
        _scheduleReconnect();
        return;
      }

      final url = AppConfig.chatWsUrl(token);
      if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
        if (kDebugMode) {
          debugPrint('[NotificationService] Invalid WS URL: $url');
        }
        _scheduleReconnect();
        return;
      }

      if (kDebugMode) {
        debugPrint('[NotificationService] Connecting $url');
      }

      _channel = connectWs(url);
      _wsSub = _channel!.stream.listen(
        _onWsMessage,
        onDone: _onWsClosed,
        onError: (Object error, StackTrace _) {
          if (kDebugMode) {
            debugPrint('[NotificationService] WebSocket stream error: $error');
          }
          _onWsClosed();
        },
        cancelOnError: true,
      );

      await _channel!.ready.timeout(const Duration(seconds: 12));
      _reconnectDelayMs = 3000;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[NotificationService] WebSocket failed: $e');
        debugPrint('$st');
      }
      _onWsClosed();
    } finally {
      _connecting = false;
    }
  }

  void _disconnectWebSocket() {
    _wsSub?.cancel();
    _wsSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _scheduleReconnect() {
    if (!_running) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _reconnectDelayMs), () {
      _reconnectDelayMs = (_reconnectDelayMs * 1.5).round().clamp(3000, 30000);
      unawaited(_connectWebSocket());
    });
  }

  void _onWsClosed() {
    _disconnectWebSocket();
    if (_running) _scheduleReconnect();
  }

  Future<void> _onWsMessage(dynamic raw) async {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map) return;
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final type = data['type']?.toString() ?? '';
    if (type != 'notification' && type != 'task_notification') return;

    await refreshUnreadCount();
    await NotificationSound.playNotification();

    if (type == 'task_notification') {
      data = {
        ...data,
        'type': 'notification',
        'notification_type': 'task_assigned',
        'title': 'New task: ${data['task_name'] ?? 'Task'}',
        'message': data['task_description']?.toString() ??
            'Assigned by ${data['assigned_by'] ?? 'Admin'}',
      };
    }

    _trackPushedId(data);
    _pushController.add(data);
  }

  void dispose() {
    stop();
    _pushController.close();
  }
}
