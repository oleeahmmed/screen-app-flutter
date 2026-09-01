import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../utils/ws_connect.dart';
import 'api_service.dart';
import 'call_navigation.dart';
import 'call_tokens.dart';
import 'local_notification_service.dart';
import 'notification_service.dart';

enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

enum CallKind { audio, video }

class CallSession {
  final String callId;
  final int peerId;
  final String peerName;
  final CallKind kind;
  final bool isOutgoing;

  const CallSession({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.kind,
    required this.isOutgoing,
  });
}

/// P2P audio/video — invite via chat message + signaling on `/ws/p2p/{session}/`.
/// Works on production without the dedicated call-signal REST endpoints.
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  static const invitePrefix = CallTokens.invitePrefix;
  static const acceptPrefix = CallTokens.acceptPrefix;
  static const rejectPrefix = CallTokens.rejectPrefix;
  static const endPrefix = CallTokens.endPrefix;

  static Map<String, dynamic>? chatMessageToCallSignal(Map<String, dynamic> data) =>
      CallTokens.chatMessageToCallSignal(data);

  static bool isHiddenCallChatMessage(String? message) =>
      CallTokens.isHiddenCallChatMessage(message);

  NotificationService? _notif;
  ApiService? _api;
  int? _myUserId;
  StreamSubscription<Map<String, dynamic>>? _signalSub;

  CallSession? _session;
  CallPhase _phase = CallPhase.idle;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  List<Map<String, dynamic>> _iceServers = const [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];
  final List<Map<String, dynamic>> _pendingIce = [];
  bool _remoteReady = false;
  bool _negotiating = false;
  Timer? _ringTimer;
  Timer? _invitePollTimer;
  Timer? _negotiationTimer;
  Timer? _connectTimeoutTimer;
  final Set<String> _seenInviteIds = {};
  final Set<String> _outgoingSessionIds = {};

  WebSocketChannel? _p2pWs;
  StreamSubscription<dynamic>? _p2pSub;
  String? _p2pSessionId;
  String? _p2pRole;
  bool _p2pPeerJoined = false;

  final _phaseController = StreamController<CallPhase>.broadcast();
  final _sessionController = StreamController<CallSession?>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _endedReasonController = StreamController<String>.broadcast();

  Stream<CallPhase> get phaseStream => _phaseController.stream;
  Stream<CallSession?> get sessionStream => _sessionController.stream;
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  Stream<String> get endedReasonStream => _endedReasonController.stream;

  CallPhase get phase => _phase;
  CallSession? get session => _session;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isInCall => _phase != CallPhase.idle && _phase != CallPhase.ended;

  void Function(CallSession session)? onIncomingCall;

  Future<void> handleRemoteSignal(Map<String, dynamic> data) => _onSignal(data);

  void bind({
    required NotificationService notificationService,
    required ApiService apiService,
    required int myUserId,
  }) {
    _signalSub?.cancel();
    _notif = notificationService;
    _api = apiService;
    _myUserId = myUserId;
    _signalSub = notificationService.listenCalls(_onSignal);
    _invitePollTimer?.cancel();
    _invitePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollChatInvites());
    });
    unawaited(_pollChatInvites());
    unawaited(_loadIceServers());
    if (kDebugMode) debugPrint('[CallService] bound userId=$myUserId');
  }

  void unbind() {
    _signalSub?.cancel();
    _signalSub = null;
    _invitePollTimer?.cancel();
    _invitePollTimer = null;
  }

  Future<void> _pollChatInvites() async {
    if (isInCall || _api == null || _myUserId == null) return;
    final r = await _api!.getChatUsers();
    if (r['success'] != true) return;
    final list = r['data'];
    if (list is! List) return;
    for (final item in list) {
      if (item is! Map) continue;
      final last = (item['last_message_raw'] ?? item['last_message'])?.toString() ?? '';
      if (!last.startsWith(invitePrefix)) continue;

      // Poll cannot infer sender from chat partner id — require caller id embedded in token.
      final signal = CallTokens.chatMessageToCallSignal({'message': last});
      if (signal == null) continue;

      final callerId = _asInt(signal['caller_id']) ?? _asInt(signal['sender_id']);
      if (callerId == null || callerId == _myUserId) continue;

      final sid = signal['call_id']?.toString() ?? '';
      if (sid.isEmpty || _seenInviteIds.contains(sid) || _outgoingSessionIds.contains(sid)) {
        continue;
      }
      _seenInviteIds.add(sid);

      signal['sender_id'] = callerId;
      signal['caller_id'] = callerId;
      signal['sender_name'] = item['full_name'] ?? item['username'];
      signal['sender_username'] = item['username'];
      signal['receiver_id'] = _myUserId;
      await _onSignal(signal);
    }
  }

  Future<void> _loadIceServers() async {
    final api = _api;
    if (api == null) return;
    final r = await api.p2pGetIceServers();
    if (r['success'] == true) {
      final data = r['data'];
      if (data is Map && data['ice_servers'] is List) {
        _iceServers = (data['ice_servers'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
  }

  String _newCallId() {
    final uid = _myUserId ?? 0;
    return '${uid}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
  }

  void _setPhase(CallPhase p) {
    _phase = p;
    if (!_phaseController.isClosed) _phaseController.add(p);
  }

  Future<bool> startOutgoing({
    required int peerId,
    required String peerName,
    required CallKind kind,
  }) async {
    if (isInCall) return false;
    if (_myUserId == null || _api == null) return false;

    final ok = await _ensurePermissions(kind);
    if (!ok) return false;

    final callId = _newCallId();
    _session = CallSession(
      callId: callId,
      peerId: peerId,
      peerName: peerName,
      kind: kind,
      isOutgoing: true,
    );
    _sessionController.add(_session);
    _setPhase(CallPhase.outgoing);

    if (kind == CallKind.video) {
      try {
        await _ensureLocalMedia(kind);
      } catch (e) {
        if (kDebugMode) debugPrint('[CallService] video preview: $e');
        _endCall('Camera unavailable');
        return false;
      }
    }

    final api = _api!;
    final createR = await api.p2pCreateSession(
      receiverId: peerId,
      fileName: '__CALL__|${kind == CallKind.video ? 'video' : 'audio'}|$callId',
    );
    if (createR['success'] != true) {
      _endCall(createR['error']?.toString() ?? 'Could not start call');
      return false;
    }

    final sessionId = createR['data']?['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      _endCall('Could not start call');
      return false;
    }

    _p2pSessionId = sessionId;
    _outgoingSessionIds.add(sessionId);
    _seenInviteIds.add(sessionId);
    _session = CallSession(
      callId: sessionId,
      peerId: peerId,
      peerName: peerName,
      kind: kind,
      isOutgoing: true,
    );
    _sessionController.add(_session);

    final inviteMsg = CallTokens.buildInvite(
      sessionId: sessionId,
      callType: kind == CallKind.video ? 'video' : 'audio',
      callerId: _myUserId!,
    );
    final sendR = await api.sendMessage(peerId, inviteMsg);
    if (sendR['success'] != true) {
      await api.p2pCancelSession(sessionId);
      _endCall('Could not reach user');
      return false;
    }

    await _connectP2p(sessionId);

    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 45), () {
      if (_phase == CallPhase.outgoing && _session?.callId == sessionId) {
        hangUp(reason: 'No answer');
      }
    });
    return true;
  }

  Future<bool> acceptIncoming() async {
    final s = _session;
    if (s == null || _phase != CallPhase.incoming) return false;

    final ok = await _ensurePermissions(s.kind);
    if (!ok) {
      rejectIncoming(reason: 'Permission denied');
      return false;
    }

    _ringTimer?.cancel();
    _setPhase(CallPhase.connecting);

    try {
      await _ensureLocalMedia(s.kind);
    } catch (e) {
      rejectIncoming(
        reason: s.kind == CallKind.video ? 'Camera unavailable' : 'Microphone unavailable',
      );
      return false;
    }

    final api = _api;
    if (api == null) {
      _endCall('Call unavailable');
      return false;
    }

    final joinR = await api.p2pJoinSession(s.callId);
    if (joinR['success'] != true) {
      _endCall(joinR['error']?.toString() ?? 'Could not join call');
      return false;
    }

    await _sendChatControl('$acceptPrefix${s.callId}');

    _p2pSessionId = s.callId;
    await _connectP2p(s.callId);
    _startConnectTimeout();
    return true;
  }

  void rejectIncoming({String reason = 'Declined'}) {
    final s = _session;
    if (s == null) return;
    _ringTimer?.cancel();
    unawaited(_sendChatControl('$rejectPrefix${s.callId}'));
    _endCall(reason);
  }

  void hangUp({String reason = 'Call ended'}) {
    final s = _session;
    if (s != null && _phase != CallPhase.ended && _phase != CallPhase.idle) {
      unawaited(_sendChatControl('$endPrefix${s.callId}'));
      if (s.isOutgoing) {
        unawaited(_api?.p2pCancelSession(s.callId));
      }
    }
    _endCall(reason);
  }

  Future<void> _sendChatControl(String message) async {
    final s = _session;
    final api = _api;
    if (s == null || api == null) return;
    await api.sendMessage(s.peerId, message);
  }

  Future<void> toggleMute(bool muted) async {
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  Future<void> toggleCamera(bool enabled) async {
    for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  Future<bool> _ensurePermissions(CallKind kind) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (kind == CallKind.video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  Future<void> _onSignal(Map<String, dynamic> data) async {
    final type = data['type']?.toString() ?? '';
    final callId = data['call_id']?.toString() ?? '';

    switch (type) {
      case 'call_invite':
        await _handleInvite(data);
        break;
      case 'call_accept':
        if (_session?.callId == callId) await _handleAccept(data);
        break;
      case 'call_reject':
        if (_session?.callId == callId) _endCall(data['reason']?.toString() ?? 'Declined');
        break;
      case 'call_hangup':
        if (_session?.callId == callId) _endCall('Call ended');
        break;
      case 'call_offer':
      case 'call_answer':
      case 'call_ice':
        break;
      case 'call_error':
        if (_phase == CallPhase.outgoing &&
            (_session?.callId == callId || callId.isEmpty)) {
          _endCall(data['message']?.toString() ?? 'Call failed');
        }
        break;
    }
  }

  Future<void> _handleInvite(Map<String, dynamic> data) async {
    final callId = data['call_id']?.toString() ?? data['session_id']?.toString() ?? '';
    if (callId.isEmpty) return;

    if (_outgoingSessionIds.contains(callId)) return;
    if (_p2pSessionId == callId && (_phase == CallPhase.outgoing || _phase == CallPhase.connecting)) {
      return;
    }

    if (isInCall) {
      final callerId = _asInt(data['sender_id']) ?? _asInt(data['caller_id']);
      if (callerId != null) {
        unawaited(_api?.sendMessage(callerId, '$rejectPrefix$callId'));
      }
      return;
    }

    final callerId = _asInt(data['sender_id']) ?? _asInt(data['caller_id']);
    if (callerId == null) return;
    if (callerId == _myUserId) return;

    final receiverId = _asInt(data['receiver_id']);
    if (receiverId != null && receiverId != _myUserId) return;

    final kind = data['call_type']?.toString() == 'video' ? CallKind.video : CallKind.audio;
    final name = data['sender_name']?.toString() ??
        data['sender_username']?.toString() ??
        'Incoming call';

    _seenInviteIds.add(callId);
    _session = CallSession(
      callId: callId,
      peerId: callerId,
      peerName: name,
      kind: kind,
      isOutgoing: false,
    );
    _p2pSessionId = callId;
    _sessionController.add(_session);
    _setPhase(CallPhase.incoming);
    onIncomingCall?.call(_session!);
    CallNavigation.openCallPageIfNeeded();

    unawaited(LocalNotificationService.show(
      id: callId.hashCode,
      title: kind == CallKind.video ? 'Incoming video call' : 'Incoming voice call',
      body: name,
      payload: 'call:$callId',
      channelId: 'aims_calls_v1',
    ));

    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 45), () {
      if (_phase == CallPhase.incoming && _session?.callId == callId) {
        rejectIncoming(reason: 'Missed call');
      }
    });
  }

  Future<void> _handleAccept(Map<String, dynamic> data) async {
    if (_session == null || !_session!.isOutgoing) return;
    if (_session!.callId != (data['call_id']?.toString() ?? '')) return;
    _ringTimer?.cancel();
    _setPhase(CallPhase.connecting);
    _startConnectTimeout();
  }

  void _startConnectTimeout() {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(const Duration(seconds: 35), () {
      if (_phase == CallPhase.connecting) {
        hangUp(reason: 'Could not connect');
      }
    });
  }

  void _clearConnectTimeout() {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
  }

  Future<void> _connectP2p(String sessionId) async {
    await _disconnectP2p();
    final token = _api?.token;
    if (token == null || token.isEmpty) return;

    final url = AppConfig.p2pWsUrl(sessionId, token);
    try {
      _p2pWs = connectWs(url);
      _p2pSub = _p2pWs!.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw as String);
            if (decoded is Map) {
              unawaited(_onP2pSignal(Map<String, dynamic>.from(decoded)));
            }
          } catch (e) {
            if (kDebugMode) debugPrint('[CallService] P2P parse: $e');
          }
        },
        onError: (_) {},
        onDone: () {
          if (_phase == CallPhase.active || _phase == CallPhase.connecting) {
            hangUp(reason: 'Connection lost');
          }
        },
      );
      await _p2pWs!.ready.timeout(const Duration(seconds: 12));
      _p2pSessionId = sessionId;
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] P2P connect failed: $e');
    }
  }

  Future<void> _disconnectP2p() async {
    await _p2pSub?.cancel();
    _p2pSub = null;
    try {
      await _p2pWs?.sink.close();
    } catch (_) {}
    _p2pWs = null;
    _p2pRole = null;
    _p2pPeerJoined = false;
  }

  void _p2pSend(Map<String, dynamic> payload) {
    final ws = _p2pWs;
    if (ws == null) return;
    try {
      ws.sink.add(jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] P2P send: $e');
    }
  }

  Future<void> _onP2pSignal(Map<String, dynamic> data) async {
    final type = data['type']?.toString() ?? '';
    switch (type) {
      case 'connected':
        _p2pSendHello();
        break;
      case 'peer_joined':
        _p2pPeerJoined = true;
        if (_phase == CallPhase.outgoing) {
          _setPhase(CallPhase.connecting);
          _startConnectTimeout();
        }
        _scheduleNegotiationFallback();
        await _maybeStartNegotiation();
        break;
      case 'role':
        _p2pRole = data['role']?.toString();
        _scheduleNegotiationFallback();
        await _maybeStartNegotiation();
        break;
      case 'hello':
        _p2pPeerJoined = true;
        _scheduleNegotiationFallback();
        await _maybeStartNegotiation();
        break;
      case 'offer':
        await _handleP2pOffer(data);
        break;
      case 'answer':
        await _handleP2pAnswer(data);
        break;
      case 'ice_candidate':
        await _handleP2pIce(data);
        break;
      case 'peer_left':
      case 'room_full':
        if (_phase != CallPhase.idle && _phase != CallPhase.ended) {
          _endCall('Call ended');
        }
        break;
    }
  }

  void _p2pSendHello() {
    _p2pSend({
      'type': 'hello',
      'platform': defaultTargetPlatform.name.toLowerCase(),
    });
  }

  void _scheduleNegotiationFallback() {
    _negotiationTimer?.cancel();
    _negotiationTimer = Timer(const Duration(milliseconds: 1500), () {
      unawaited(_maybeStartNegotiation(force: true));
    });
  }

  Future<void> _maybeStartNegotiation({bool force = false}) async {
    if (_p2pRole == 'initiator') {
      if (force || _p2pPeerJoined) {
        await _startCallerNegotiation();
      }
    }
  }

  Future<void> _startCallerNegotiation() async {
    if (_negotiating || _p2pRole != 'initiator') return;
    if (_session == null) return;
    _negotiating = true;
    try {
      await _ensureLocalMedia(_session!.kind);
      await _resetPcIfNeeded();
      await _initPc(asCaller: true);
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _session!.kind == CallKind.video,
      });
      await _pc!.setLocalDescription(offer);
      _p2pSend({'type': 'offer', 'sdp': {'type': offer.type, 'sdp': offer.sdp}});
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] caller negotiation: $e');
      hangUp(reason: 'Connection failed');
    } finally {
      _negotiating = false;
    }
  }

  Future<void> _resetPcIfNeeded() async {
    if (_pc == null || _remoteReady) return;
    try {
      await _pc!.close();
    } catch (_) {}
    _pc = null;
    _remoteReady = false;
    _pendingIce.clear();
  }

  Future<void> _handleP2pOffer(Map<String, dynamic> data) async {
    if (_session == null || _p2pRole == 'initiator') return;
    final sdp = data['sdp'];
    if (sdp is! Map) return;

    try {
      await _ensureLocalMedia(_session!.kind);
      await _resetPcIfNeeded();
      await _initPc(asCaller: false);
      await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()),
      );
      _remoteReady = true;
      await _flushIce();

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _session!.kind == CallKind.video,
      });
      await _pc!.setLocalDescription(answer);
      _p2pSend({'type': 'answer', 'sdp': {'type': answer.type, 'sdp': answer.sdp}});
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] handle offer: $e');
      hangUp(reason: 'Connection failed');
    }
  }

  Future<void> _handleP2pAnswer(Map<String, dynamic> data) async {
    final sdp = data['sdp'];
    if (sdp is! Map || _pc == null) return;
    try {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()),
      );
      _remoteReady = true;
      await _flushIce();
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] handle answer: $e');
    }
  }

  Future<void> _handleP2pIce(Map<String, dynamic> data) async {
    final cand = data['candidate'];
    if (cand is! Map || _pc == null) return;
    final c = cand['candidate']?.toString();
    if (c == null || c.isEmpty) return;
    if (_remoteReady) {
      try {
        await _pc!.addCandidate(RTCIceCandidate(
          c,
          cand['sdpMid']?.toString(),
          cand['sdpMLineIndex'] is int
              ? cand['sdpMLineIndex'] as int
              : int.tryParse('${cand['sdpMLineIndex']}'),
        ));
      } catch (e) {
        if (kDebugMode) debugPrint('[CallService] ICE: $e');
      }
    } else {
      _pendingIce.add(Map<String, dynamic>.from(cand));
    }
  }

  Future<void> _ensureLocalMedia(CallKind kind) async {
    if (_localStream != null) return;
    final constraints = <String, dynamic>{
      'audio': true,
      'video': kind == CallKind.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };
    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    _localStream = stream;
    _localStreamController.add(stream);
  }

  Future<void> _initPc({required bool asCaller}) async {
    if (_pc != null) return;
    _pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });

    _pc!.onIceCandidate = (c) {
      final cand = c.candidate;
      if (cand == null || cand.isEmpty) return;
      _p2pSend({
        'type': 'ice_candidate',
        'candidate': {
          'candidate': cand,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream);
      }
    };

    void markActive() {
      _clearConnectTimeout();
      _setPhase(CallPhase.active);
    }

    _pc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        markActive();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (_phase == CallPhase.active || _phase == CallPhase.connecting) {
          hangUp(reason: 'Connection lost');
        }
      }
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        markActive();
      }
    };

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
    }
  }

  Future<void> _flushIce() async {
    if (_pc == null) return;
    for (final c in List<Map<String, dynamic>>.from(_pendingIce)) {
      try {
        await _pc!.addCandidate(RTCIceCandidate(
          c['candidate']?.toString(),
          c['sdpMid']?.toString(),
          c['sdpMLineIndex'] is int
              ? c['sdpMLineIndex'] as int
              : int.tryParse('${c['sdpMLineIndex']}'),
        ));
      } catch (_) {}
    }
    _pendingIce.clear();
  }

  void _endCall(String reason) {
    _ringTimer?.cancel();
    _negotiationTimer?.cancel();
    _clearConnectTimeout();
    _negotiating = false;
    _remoteReady = false;
    _pendingIce.clear();
    if (_p2pSessionId != null) {
      _outgoingSessionIds.remove(_p2pSessionId);
    }
    unawaited(_disconnectP2p());

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    _localStream?.dispose();
    _localStream = null;
    _localStreamController.add(null);

    _remoteStream = null;
    _remoteStreamController.add(null);

    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;

    _p2pSessionId = null;
    _session = null;
    _sessionController.add(null);
    _setPhase(CallPhase.ended);
    _endedReasonController.add(reason);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (_phase == CallPhase.ended) _setPhase(CallPhase.idle);
    });
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse('${v ?? ''}');
  }

  void dispose() {
    _ringTimer?.cancel();
    _invitePollTimer?.cancel();
    _negotiationTimer?.cancel();
    _clearConnectTimeout();
    _signalSub?.cancel();
    _endCall('Closed');
    _phaseController.close();
    _sessionController.close();
    _localStreamController.close();
    _remoteStreamController.close();
    _endedReasonController.close();
  }
}
