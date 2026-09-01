import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'notification_service.dart';

class CallInvite {
  const CallInvite({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.video,
  });

  final String callId;
  final int peerId;
  final String peerName;
  final bool video;
}

/// Relays 1:1 call signaling over the chat WebSocket, with HTTP poll fallback.
class CallService {
  CallService(this._api, this._notifications);

  final ApiService _api;
  final NotificationService _notifications;

  StreamSubscription<Map<String, dynamic>>? _wsSub;
  Timer? _pollTimer;
  bool _running = false;
  bool inCall = false;

  CallInvite? incoming;

  final _incomingController = StreamController<CallInvite?>.broadcast();
  final _signalController = StreamController<Map<String, dynamic>>.broadcast();
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();

  Stream<CallInvite?> get incomingStream => _incomingController.stream;
  Stream<Map<String, dynamic>> get signalStream => _signalController.stream;

  static String newCallId() {
    final n = Random().nextInt(0x7fffffff);
    return '${DateTime.now().millisecondsSinceEpoch}-$n';
  }

  static int asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  void start() {
    if (_running) return;
    _running = true;
    _wsSub = _notifications.callSignalStream.listen(_onSignal);
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollPending());
    });
    unawaited(_pollPending());
  }

  void stop() {
    _running = false;
    _wsSub?.cancel();
    _wsSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    incoming = null;
    inCall = false;
  }

  Future<void> send(Map<String, dynamic> payload) async {
    _notifications.sendJson(payload);
    await _api.sendCallSignal(payload);
  }

  Future<void> invite({
    required int calleeId,
    required String callId,
    required bool video,
  }) {
    return send({
      'type': 'call_invite',
      'callee_id': calleeId,
      'call_id': callId,
      'call_type': video ? 'video' : 'audio',
    });
  }

  Future<void> accept({required int callerId, required String callId}) {
    return send({
      'type': 'call_accept',
      'caller_id': callerId,
      'call_id': callId,
    });
  }

  Future<void> reject({required int callerId, required String callId}) {
    return send({
      'type': 'call_reject',
      'caller_id': callerId,
      'call_id': callId,
    });
  }

  Future<void> hangup({required int peerId, required String callId}) {
    return send({
      'type': 'call_hangup',
      'peer_id': peerId,
      'call_id': callId,
    });
  }

  void clearIncoming() {
    incoming = null;
    _incomingController.add(null);
  }

  Future<void> _pollPending() async {
    if (!_running) return;
    final r = await _api.pollCallSignals();
    if (r['success'] != true) return;
    final list = r['signals'] as List? ?? [];
    for (final item in list) {
      if (item is Map) {
        _onSignal(Map<String, dynamic>.from(item));
      }
    }
  }

  void _onSignal(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    if (!type.startsWith('call_')) return;
    if (_isDuplicate(data)) return;

    if (kDebugMode) {
      debugPrint('[CallService] $type call_id=${data['call_id']}');
    }

    if (type == 'call_invite') {
      _handleInvite(data);
      return;
    }

    _signalController.add(data);
  }

  void _handleInvite(Map<String, dynamic> data) {
    final callId = data['call_id']?.toString() ?? '';
    final peerId = asInt(data['sender_id']);
    if (callId.isEmpty || peerId <= 0) return;

    if (inCall || incoming != null) {
      unawaited(reject(callerId: peerId, callId: callId));
      return;
    }

    final name = (data['sender_name'] ?? data['sender_username'] ?? 'Incoming call')
        .toString();
    final video = (data['call_type']?.toString() ?? 'audio') == 'video';
    incoming = CallInvite(
      callId: callId,
      peerId: peerId,
      peerName: name,
      video: video,
    );
    _incomingController.add(incoming);
    _signalController.add(data);
  }

  bool _isDuplicate(Map<String, dynamic> data) {
    final key = jsonEncode({
      't': data['type'],
      'id': data['call_id'],
      's': data['sender_id'],
      'sdp': data['sdp'],
      'c': data['candidate'],
    });
    if (_seen.contains(key)) return true;
    _seen.add(key);
    while (_seen.length > 64) {
      _seen.remove(_seen.first);
    }
    return false;
  }

  void dispose() {
    stop();
    _incomingController.close();
    _signalController.close();
  }
}
