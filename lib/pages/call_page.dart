import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';

/// WhatsApp-style call UI — incoming ring, answer/decline, then in-call controls.
class CallPage extends StatefulWidget {
  const CallPage({super.key});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> with TickerProviderStateMixin {
  final _call = CallService.instance;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _muted = false;
  bool _cameraOff = false;
  bool _speaker = false;
  StreamSubscription<CallPhase>? _phaseSub;
  StreamSubscription<MediaStream?>? _localSub;
  StreamSubscription<MediaStream?>? _remoteSub;
  StreamSubscription<String>? _endedSub;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    unawaited(_initRenderers());
    _phaseSub = _call.phaseStream.listen((phase) {
      if ((phase == CallPhase.connecting || phase == CallPhase.active) &&
          _isVideo &&
          !_speaker) {
        _speaker = true;
        unawaited(Helper.setSpeakerphoneOn(true));
      }
      if (mounted) setState(() {});
    });
    _localSub = _call.localStreamStream.listen((s) {
      _localRenderer.srcObject = s;
      if (mounted) setState(() {});
    });
    _remoteSub = _call.remoteStreamStream.listen((s) {
      _remoteRenderer.srcObject = s;
      if (mounted) setState(() {});
    });
    _endedSub = _call.endedReasonStream.listen((_) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _localRenderer.srcObject = _call.localStream;
    _remoteRenderer.srcObject = _call.remoteStream;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulse.dispose();
    _phaseSub?.cancel();
    _localSub?.cancel();
    _remoteSub?.cancel();
    _endedSub?.cancel();
    _durationTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  CallSession? get _session => _call.session;
  CallPhase get _phase => _call.phase;
  bool get _isVideo => _session?.kind == CallKind.video;
  bool get _hasLocalVideo => _isVideo && _call.localStream != null && !_cameraOff;
  bool get _hasRemoteVideo =>
      _isVideo && _phase == CallPhase.active && _call.remoteStream != null;
  bool get _isRinging =>
      _phase == CallPhase.outgoing || _phase == CallPhase.connecting;

  String get _statusText {
    switch (_phase) {
      case CallPhase.outgoing:
        return 'Ringing…';
      case CallPhase.incoming:
        return _isVideo ? 'Incoming video call' : 'Incoming voice call';
      case CallPhase.connecting:
        return 'Connecting…';
      case CallPhase.active:
        return _formatDuration(_activeSeconds);
      default:
        return '';
    }
  }

  int _activeSeconds = 0;
  Timer? _durationTimer;

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _activeSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_call.phase == CallPhase.active && mounted) {
        setState(() => _activeSeconds++);
      }
    });
  }

  String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget get _bottomControls {
    if (_phase == CallPhase.incoming) return _incomingActions(video: _isVideo);
    if (_isRinging) return _ringingActions();
    return _inCallControls();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == CallPhase.active && _durationTimer == null) {
      _startDurationTimer();
    }
    if (_phase != CallPhase.active) {
      _durationTimer?.cancel();
      _durationTimer = null;
    }
    if (_phase == CallPhase.incoming) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }

    final session = _session;
    if (session == null) {
      return const Scaffold(backgroundColor: Color(0xFF0B141A), body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: _isVideo ? _buildVideoBody(session) : _buildAudioBody(session),
    );
  }

  Widget _buildVideoBody(CallSession session) {
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_hasRemoteVideo)
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else if (_hasLocalVideo)
            RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Container(
              color: const Color(0xFF0B141A),
              child: Center(
                child: Icon(Icons.videocam_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.35)),
              ),
            ),
          if (_phase != CallPhase.active)
            Container(color: Colors.black.withValues(alpha: 0.35)),
          if (_hasRemoteVideo && _hasLocalVideo)
            Positioned(
              top: 12,
              right: 12,
              width: 108,
              height: 152,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white38, width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 8),
                    ],
                  ),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 8,
            left: 16,
            right: _hasRemoteVideo && _hasLocalVideo ? 130 : 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.peerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 15,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: _bottomControls,
          ),
        ],
      ),
    );
  }

  Widget _buildAudioBody(CallSession session) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F2C34), Color(0xFF0B141A)],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 72),
            _pulseAvatar(session.peerName),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                session.peerName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusText,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 16),
            ),
            const Spacer(),
            _bottomControls,
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _pulseAvatar(String name) {
    return SizedBox(
      width: 180,
      height: 180,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          final t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final delay in [0.0, 0.5])
                Builder(builder: (_) {
                  final p = (t + delay) % 1.0;
                  final incoming = _phase == CallPhase.incoming;
                  return Container(
                    width: 112 + (incoming ? 64 * p : 0),
                    height: 112 + (incoming ? 64 * p : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: incoming ? (1 - p) * 0.28 : 0),
                        width: 2,
                      ),
                    ),
                  );
                }),
              CircleAvatar(
                radius: 56,
                backgroundColor: const Color(0xFF00A884),
                child: Text(
                  _initials(name),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _incomingActions({required bool video}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _roundAction(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            color: const Color(0xFFE53935),
            size: 68,
            onTap: () {
              _call.rejectIncoming();
              Navigator.pop(context);
            },
          ),
          _roundAction(
            icon: video ? Icons.videocam_rounded : Icons.call_rounded,
            label: 'Accept',
            color: const Color(0xFF25D366),
            size: 68,
            onTap: () async {
              await _call.acceptIncoming();
            },
          ),
        ],
      ),
    );
  }

  Widget _ringingActions() {
    return Center(
      child: _roundAction(
        icon: Icons.call_end_rounded,
        label: 'End',
        color: const Color(0xFFE53935),
        size: 68,
        onTap: () {
          _call.hangUp();
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _inCallControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
          _roundAction(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: _muted ? 'Unmute' : 'Mute',
            color: Colors.white.withValues(alpha: 0.18),
            iconColor: Colors.white,
            onTap: () async {
              setState(() => _muted = !_muted);
              await _call.toggleMute(_muted);
            },
          ),
          _roundAction(
            icon: _speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
            label: _speaker ? 'Speaker' : 'Earpiece',
            color: _speaker ? const Color(0xFF25D366) : Colors.white.withValues(alpha: 0.18),
            iconColor: Colors.white,
            onTap: () {
              setState(() => _speaker = !_speaker);
              unawaited(Helper.setSpeakerphoneOn(_speaker));
            },
          ),
          if (_isVideo) ...[
            _roundAction(
              icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
              label: _cameraOff ? 'Camera off' : 'Camera',
              color: Colors.white.withValues(alpha: 0.18),
              iconColor: Colors.white,
              onTap: () async {
                setState(() => _cameraOff = !_cameraOff);
                await _call.toggleCamera(!_cameraOff);
              },
            ),
            _roundAction(
              icon: Icons.cameraswitch_rounded,
              label: 'Flip',
              color: Colors.white.withValues(alpha: 0.18),
              iconColor: Colors.white,
              onTap: () => _call.switchCamera(),
            ),
          ],
          _roundAction(
            icon: Icons.call_end_rounded,
            label: 'End',
            color: const Color(0xFFE53935),
            onTap: () {
              _call.hangUp();
              Navigator.pop(context);
            },
          ),
        ],
        ),
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String label,
    required Color color,
    Color iconColor = Colors.white,
    double size = 58,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: iconColor, size: size * 0.45),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
