import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';

class CallPage extends StatefulWidget {
  const CallPage({
    super.key,
    required this.apiService,
    required this.callService,
    required this.peerId,
    required this.peerName,
    required this.callId,
    required this.isCaller,
    required this.video,
  });

  final ApiService apiService;
  final CallService callService;
  final int peerId;
  final String peerName;
  final String callId;
  final bool isCaller;
  final bool video;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<Map<String, dynamic>>? _sigSub;

  bool _micOn = true;
  bool _camOn = true;
  bool _speakerOn = true;
  bool _ending = false;
  bool _remoteDescSet = false;
  bool _peerAccepted = false;
  bool _offerSent = false;
  String _status = 'Connecting…';

  final List<RTCIceCandidate> _pendingIce = [];
  Map<String, dynamic>? _pendingOffer;
  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];

  @override
  void initState() {
    super.initState();
    widget.callService.inCall = true;
    widget.callService.clearIncoming();
    _sigSub = widget.callService.signalStream.listen(_onSignal);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        _fail('Microphone permission is required');
        return;
      }
      if (widget.video) {
        final cam = await Permission.camera.request();
        if (!cam.isGranted) {
          _fail('Camera permission is required for video call');
          return;
        }
      }

      await _loadIce();
      await _createPeer();

      if (widget.isCaller) {
        setState(() => _status = 'Calling ${widget.peerName}…');
        await widget.callService.invite(
          calleeId: widget.peerId,
          callId: widget.callId,
          video: widget.video,
        );
        if (_peerAccepted) await _createOffer();
      } else {
        setState(() => _status = 'Connecting…');
        await widget.callService.accept(
          callerId: widget.peerId,
          callId: widget.callId,
        );
        if (_pendingOffer != null) {
          final offer = _pendingOffer!;
          _pendingOffer = null;
          await _handleOffer(offer);
        }
      }
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> _loadIce() async {
    final r = await widget.apiService.p2pGetIceServers();
    if (r['success'] != true) return;
    final data = r['data'] as Map<String, dynamic>? ?? {};
    final servers = data['ice_servers'] as List? ?? [];
    if (servers.isEmpty) return;
    final out = <Map<String, dynamic>>[];
    for (final s in servers.whereType<Map>()) {
      final m = Map<String, dynamic>.from(s);
      if (m['urls'] == null) continue;
      out.add(m);
    }
    if (out.isNotEmpty) _iceServers = out;
  }

  Future<void> _createPeer() async {
    _pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      unawaited(widget.callService.send({
        'type': 'call_ice',
        'peer_id': widget.peerId,
        'call_id': widget.callId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      }));
    };

    _pc!.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remoteRenderer.srcObject = event.streams.first;
      if (mounted) setState(() => _status = '');
    };

    _pc!.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _status = '');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _fail('Call connection failed');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        setState(() => _status = 'Reconnecting…');
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
            }
          : false,
    });
    _localRenderer.srcObject = _localStream;
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    _camOn = widget.video;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _createOffer() async {
    final pc = _pc;
    if (pc == null || _offerSent) return;
    _offerSent = true;
    final offer = await pc.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.video ? 1 : 0,
    });
    await pc.setLocalDescription(offer);
    await widget.callService.send({
      'type': 'call_offer',
      'peer_id': widget.peerId,
      'call_id': widget.callId,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
    if (mounted) setState(() => _status = 'Ringing…');
  }

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    final pc = _pc;
    if (pc == null) {
      _pendingOffer = data;
      return;
    }
    final desc = _parseSdp(data);
    if (desc == null) return;
    await pc.setRemoteDescription(desc);
    _remoteDescSet = true;
    await _flushIce();
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await widget.callService.send({
      'type': 'call_answer',
      'peer_id': widget.peerId,
      'call_id': widget.callId,
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
    if (mounted) setState(() => _status = 'Connecting…');
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    final pc = _pc;
    if (pc == null) return;
    final desc = _parseSdp(data);
    if (desc == null) return;
    await pc.setRemoteDescription(desc);
    _remoteDescSet = true;
    await _flushIce();
  }

  Future<void> _handleIce(Map<String, dynamic> data) async {
    final raw = data['candidate'];
    Map<String, dynamic>? cand;
    if (raw is Map) {
      cand = Map<String, dynamic>.from(raw);
    }
    if (cand == null) return;
    final ice = RTCIceCandidate(
      cand['candidate']?.toString(),
      cand['sdpMid']?.toString(),
      CallService.asInt(cand['sdpMLineIndex']),
    );
    if (!_remoteDescSet || _pc == null) {
      _pendingIce.add(ice);
      return;
    }
    try {
      await _pc!.addCandidate(ice);
    } catch (_) {}
  }

  Future<void> _flushIce() async {
    final pc = _pc;
    if (pc == null) return;
    final pending = List<RTCIceCandidate>.from(_pendingIce);
    _pendingIce.clear();
    for (final ice in pending) {
      try {
        await pc.addCandidate(ice);
      } catch (_) {}
    }
  }

  RTCSessionDescription? _parseSdp(Map<String, dynamic> data) {
    final raw = data['sdp'];
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final sdp = m['sdp']?.toString();
      final type = m['type']?.toString();
      if (sdp == null || type == null) return null;
      return RTCSessionDescription(sdp, type);
    }
    if (raw is String && raw.isNotEmpty) {
      final type = data['sdp_type']?.toString() ??
          (data['type'] == 'call_answer' ? 'answer' : 'offer');
      return RTCSessionDescription(raw, type);
    }
    return null;
  }

  void _onSignal(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final callId = data['call_id']?.toString() ?? '';
    if (callId.isNotEmpty && callId != widget.callId) return;

    switch (type) {
      case 'call_accept':
        _peerAccepted = true;
        if (widget.isCaller) unawaited(_createOffer());
      case 'call_reject':
        _fail('${widget.peerName} declined');
      case 'call_hangup':
        _leave(sendHangup: false, message: 'Call ended');
      case 'call_offer':
        unawaited(_handleOffer(data));
      case 'call_answer':
        unawaited(_handleAnswer(data));
      case 'call_ice':
        unawaited(_handleIce(data));
      case 'call_error':
        _fail(data['message']?.toString() ?? 'Call failed');
    }
  }

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = _micOn;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleCam() async {
    if (!widget.video) return;
    _camOn = !_camOn;
    for (final track in _localStream?.getVideoTracks() ?? []) {
      track.enabled = _camOn;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _fail(String message) {
    if (_ending) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
      );
    }
    _leave(sendHangup: true);
  }

  Future<void> _leave({required bool sendHangup, String? message}) async {
    if (_ending) return;
    _ending = true;
    if (sendHangup) {
      try {
        await widget.callService.hangup(
          peerId: widget.peerId,
          callId: widget.callId,
        );
      } catch (_) {}
    }
    widget.callService.inCall = false;
    if (!mounted) return;
    Navigator.of(context).pop(message);
  }

  Future<void> _cleanup() async {
    _sigSub?.cancel();
    _sigSub = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      await _localRenderer.dispose();
    } catch (_) {}
    try {
      await _remoteRenderer.dispose();
    } catch (_) {}
    _localStream = null;
    _pc = null;
    widget.callService.inCall = false;
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(sendHangup: true);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: widget.video
                    ? RTCVideoView(
                        _remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Container(
                        color: AppTheme.bgDeep,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 48,
                                backgroundColor: AppTheme.primary,
                                child: Text(
                                  _initials(widget.peerName),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.peerName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_status.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _status,
                                  style: const TextStyle(color: AppTheme.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
              if (widget.video)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.peerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_status.isNotEmpty)
                        Text(_status, style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              if (widget.video)
                Positioned(
                  top: 16,
                  right: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 110,
                      height: 150,
                      child: RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundBtn(
                      icon: _micOn ? Icons.mic : Icons.mic_off,
                      on: _micOn,
                      onTap: _toggleMic,
                    ),
                    if (widget.video)
                      _roundBtn(
                        icon: _camOn ? Icons.videocam : Icons.videocam_off,
                        on: _camOn,
                        onTap: _toggleCam,
                      ),
                    _roundBtn(
                      icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                      on: _speakerOn,
                      onTap: _toggleSpeaker,
                    ),
                    _roundBtn(
                      icon: Icons.call_end,
                      on: false,
                      color: AppTheme.danger,
                      onTap: () => _leave(sendHangup: true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundBtn({
    required IconData icon,
    required bool on,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 28,
        backgroundColor: color ?? (on ? const Color(0x33FFFFFF) : Colors.white24),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({
    super.key,
    required this.invite,
    required this.onAccept,
    required this.onReject,
  });

  final CallInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    invite.video ? Icons.videocam : Icons.call,
                    color: AppTheme.primaryBright,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    invite.video ? 'Incoming video call' : 'Incoming audio call',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    invite.peerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onReject,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onAccept,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
