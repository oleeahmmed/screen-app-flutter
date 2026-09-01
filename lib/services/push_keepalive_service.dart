import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../utils/ws_connect.dart';
import 'local_notification_service.dart';

/// Keeps the chat WebSocket alive after login so Android can show system
/// notifications when Aims is not on screen.
///
/// Android requires a persistent "Aims is connected" notification for this.
/// True killed-state delivery (no persistent notice) needs Firebase FCM.
class PushKeepAlive {
  static const _channelId = 'aims_keepalive';

  static bool get _android => !kIsWeb && Platform.isAndroid;

  static Future<void> configure() async {
    if (!_android) return;

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: pushKeepAliveOnStart,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Aims',
        initialNotificationContent: 'Connected — calls and alerts',
        foregroundServiceNotificationId: 8801,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: pushKeepAliveOnStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  static Future<void> start() async {
    if (!_android) return;
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    }
    service.invoke('ui_state', {'foreground': true});
  }

  static Future<void> stop() async {
    if (!_android) return;
    final service = FlutterBackgroundService();
    service.invoke('stop');
  }

  static void setUiForeground(bool foreground) {
    if (!_android) return;
    FlutterBackgroundService().invoke('ui_state', {'foreground': foreground});
  }
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void pushKeepAliveOnStart(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_PushKeepAliveIsolate(service).run());
}

class _PushKeepAliveIsolate {
  _PushKeepAliveIsolate(this.service);

  final ServiceInstance service;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  int _delayMs = 3000;
  bool _running = true;
  bool _connecting = false;
  bool _uiForeground = false;

  Future<void> run() async {
    service.on('stop').listen((_) async {
      _running = false;
      _reconnectTimer?.cancel();
      await _disconnect();
      service.stopSelf();
    });
    service.on('ui_state').listen((event) {
      _uiForeground = event?['foreground'] == true;
    });

    await LocalNotificationService.initialize();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_running || _connecting) return;
    _connecting = true;
    await _disconnect();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        _running = false;
        service.stopSelf();
        return;
      }

      final url = AppConfig.chatWsUrl(token);
      _channel = connectWs(url);
      _wsSub = _channel!.stream.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (Object error, StackTrace stack) => _onClosed(),
        cancelOnError: true,
      );
      await _channel!.ready.timeout(const Duration(seconds: 12));
      _delayMs = 3000;
    } catch (_) {
      _onClosed();
    } finally {
      _connecting = false;
    }
  }

  Future<void> _disconnect() async {
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _onClosed() {
    unawaited(_disconnect());
    if (!_running) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _delayMs), () {
      _delayMs = (_delayMs * 1.5).round().clamp(3000, 30000);
      unawaited(_connect());
    });
  }

  Future<void> _onMessage(dynamic raw) async {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map) return;
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    if (_uiForeground) return;

    final type = data['type']?.toString() ?? '';
    if (type.startsWith('call_')) {
      if (type == 'call_invite') {
        final name = (data['sender_name'] ?? data['sender_username'] ?? 'Someone')
            .toString();
        final video = (data['call_type']?.toString() ?? 'audio') == 'video';
        final callId = data['call_id']?.toString() ?? 'call';
        await LocalNotificationService.showCall(
          id: callId.hashCode & 0x7fffffff,
          title: video ? 'Incoming video call' : 'Incoming call',
          body: name,
          payload: 'call:$callId',
        );
      }
      return;
    }

    if (type != 'notification' && type != 'task_notification') return;

    var title = data['title']?.toString() ?? 'Aims';
    var body = data['message']?.toString() ?? '';
    if (type == 'task_notification') {
      title = 'New task: ${data['task_name'] ?? 'Task'}';
      body = data['task_description']?.toString() ??
          'Assigned by ${data['assigned_by'] ?? 'Admin'}';
    }
    if (body.isEmpty) body = 'Tap to open Aims';

    final rawId = data['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? title.hashCode;
    await LocalNotificationService.show(
      id: id & 0x7fffffff,
      title: title,
      body: body,
      payload: 'alerts',
    );
  }
}
