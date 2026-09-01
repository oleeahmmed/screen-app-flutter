import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../utils/ws_connect.dart';
import 'api_service.dart';
import 'call_tokens.dart';
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

  final _presenceController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;

  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;

  final _messagesReadController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messagesReadStream => _messagesReadController.stream;

  final _callController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callStream => _callController.stream;

  final _chatMessageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get chatMessageStream => _chatMessageController.stream;

  static const _callTypes = {
    'call_invite',
    'call_accept',
    'call_reject',
    'call_hangup',
    'call_offer',
    'call_answer',
    'call_ice',
    'call_error',
  };

  final List<Map<String, dynamic>> _pendingCallSignals = [];

  void Function(int count)? onUnreadCountChanged;

  bool get isWsConnected => _channel != null;

  /// Wait until the shared chat WebSocket is up (needed before call signaling).
  Future<bool> waitForConnection({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_channel != null) return true;
    if (!_running) await start();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_channel != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return _channel != null;
  }

  /// Subscribe to call signaling; replays signals received before bind.
  StreamSubscription<Map<String, dynamic>> listenCalls(
    void Function(Map<String, dynamic> event) onData,
  ) {
    for (final event in _pendingCallSignals) {
      onData(event);
    }
    _pendingCallSignals.clear();
    return callStream.listen(onData);
  }

  void _emitCallSignal(Map<String, dynamic> data) {
    if (!_callController.hasListener) {
      _pendingCallSignals.add(data);
      if (_pendingCallSignals.length > 8) {
        _pendingCallSignals.removeAt(0);
      }
      return;
    }
    _callController.add(data);
  }

  /// Send a chat signaling payload on the shared `/ws/chat/` socket.
  bool sendChatPayload(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return false;
    try {
      ch.sink.add(jsonEncode(payload));
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[NotificationService] sendChatPayload: $e');
      return false;
    }
  }

  void sendTyping({required int receiverId, required bool isTyping}) {
    sendChatPayload({
      'type': 'typing',
      'receiver_id': receiverId,
      'is_typing': isTyping,
    });
  }

  void sendGroupTyping({required int groupId, required bool isTyping}) {
    sendChatPayload({
      'type': 'group_typing',
      'group_id': groupId,
      'is_typing': isTyping,
    });
  }

  Duration get _pollInterval {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return const Duration(seconds: 15);
    }
    return const Duration(seconds: 30);
  }

  Duration _activePollInterval = const Duration(seconds: 30);

  /// Faster polling while Android/iOS is backgrounded (WS often dies).
  void setAppInBackground(bool background) {
    if (!_running) return;
    final next = (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && background)
        ? const Duration(seconds: 6)
        : _pollInterval;
    if (next == _activePollInterval) return;
    _activePollInterval = next;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_activePollInterval, (_) {
      refreshUnreadCount(playSoundOnIncrease: true);
    });
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _activePollInterval = _pollInterval;
    await refreshUnreadCount();
    unawaited(_connectWebSocket());
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_activePollInterval, (_) {
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
    _pendingCallSignals.clear();
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
    if (type == 'user_status') {
      _presenceController.add(data);
      return;
    }
    if (type == 'typing_indicator' || type == 'group_typing') {
      _typingController.add(data);
      return;
    }
    if (type == 'messages_read') {
      _messagesReadController.add(data);
      return;
    }
    if (_callTypes.contains(type)) {
      _emitCallSignal(data);
      return;
    }
    if (type == 'chat_message') {
      final call = CallTokens.chatMessageToCallSignal(data);
      if (call != null) {
        _emitCallSignal(call);
      } else {
        _chatMessageController.add(data);
      }
      return;
    }
    if (type == 'notification') {
      final notifType = data['notification_type']?.toString() ?? '';
      if (notifType == 'call_invite') {
        final msg = data['message']?.toString() ?? '';
        final call = CallTokens.chatMessageToCallSignal({
          'message': msg,
          'sender_id': _notifInt(data['sender_id']) ?? _notifInt(data['sender']),
          'sender_username': data['sender_username'],
          'sender_name': data['title']?.toString().replaceFirst('Incoming call from ', ''),
        });
        if (call != null) {
          _emitCallSignal(call);
          return;
        }
      }
    }
    if (type != 'notification' && type != 'task_notification') return;

    await refreshUnreadCount();
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      await NotificationSound.playNotification();
    }

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

  int? _notifInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse('${v ?? ''}');
  }

  void dispose() {
    stop();
    _typingController.close();
    _messagesReadController.close();
    _callController.close();
    _chatMessageController.close();
    _pushController.close();
    _presenceController.close();
  }
}
