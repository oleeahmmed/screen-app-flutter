import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../utils/ws_connect.dart';
import '../utils/platform_capabilities.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class Peer2PeerPage extends StatefulWidget {
  final ApiService apiService;
  final bool embedded;

  const Peer2PeerPage({
    super.key,
    required this.apiService,
    this.embedded = false,
  });

  @override
  State<Peer2PeerPage> createState() => _Peer2PeerPageState();
}

class _Peer2PeerPageState extends State<Peer2PeerPage> with SingleTickerProviderStateMixin {
  String _mode = 'home';
  String? _sessionId;
  String? _peerName;
  String? _selectedFileName;
  int _selectedFileSize = 0;
  Uint8List? _selectedFileBytes;
  double _progress = 0.0;
  String _statusText = '';
  bool _isConnected = false;
  bool _signalingOk = false;
  bool _peerFound = false;
  bool _webrtcReady = false;
  String _iceState = '';
  int _bytesTransferred = 0;
  Timer? _connectTimeout;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  WebSocketChannel? _ws;
  bool _wsAlive = false;

  String? _myRole;
  bool _remoteReady = false;
  final List<Map<String, dynamic>> _pendingIce = [];
  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];

  final List<Uint8List> _rxChunks = [];
  int _expectedSize = 0;
  int _rxSize = 0;
  String _rxFileName = '';
  bool _awaitingAccept = false;
  bool _joinedSession = false;

  late AnimationController _pulseCtrl;
  final _joinCtrl = TextEditingController();

  static const _chunkSize = 16384;
  static const _highWater = 8 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cleanup();
    _pulseCtrl.dispose();
    _joinCtrl.dispose();
    super.dispose();
  }

  void _cleanup() {
    _connectTimeout?.cancel();
    _connectTimeout = null;
    try {
      _dataChannel?.close();
    } catch (_) {}
    try {
      _pc?.close();
    } catch (_) {}
    try {
      _ws?.sink.close();
    } catch (_) {}
    _dataChannel = null;
    _pc = null;
    _ws = null;
    _wsAlive = false;
    _myRole = null;
    _remoteReady = false;
    _pendingIce.clear();
    _signalingOk = false;
    _peerFound = false;
    _webrtcReady = false;
    _iceState = '';
    _bytesTransferred = 0;
  }

  List<Map<String, dynamic>> _normalizeIceServers(List<Map<String, dynamic>> raw) {
    final out = <Map<String, dynamic>>[];
    for (final s in raw) {
      final m = <String, dynamic>{};
      final urls = s['urls'];
      if (urls is List) {
        m['urls'] = urls.map((e) => e.toString()).toList();
      } else if (urls != null) {
        m['urls'] = urls.toString();
      } else {
        continue;
      }
      if (s['username'] != null) m['username'] = s['username'].toString();
      if (s['credential'] != null) m['credential'] = s['credential'].toString();
      out.add(m);
    }
    if (out.isEmpty) {
      out.add({'urls': 'stun:stun.l.google.com:19302'});
    }
    return out;
  }

  Future<void> _loadIceServers() async {
    final r = await widget.apiService.p2pGetIceServers();
    if (r['success'] == true) {
      final data = r['data'] as Map<String, dynamic>? ?? {};
      final servers = data['ice_servers'] as List? ?? [];
      if (servers.isNotEmpty) {
        _iceServers = _normalizeIceServers(
          servers.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
        );
      }
    }
  }

  Future<void> _startSendFlow() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.first;

    Uint8List? bytes = pf.bytes;
    if (bytes == null && pf.path != null) {
      bytes = await File(pf.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      _showError('Could not read the selected file');
      return;
    }

    _selectedFileBytes = bytes;
    _selectedFileName = pf.name;
    _selectedFileSize = bytes.length;

    setState(() {
      _mode = 'sending';
      _statusText = 'Creating session...';
    });

    await _loadIceServers();

    final resp = await widget.apiService.p2pCreateSession(
      fileName: _selectedFileName!,
      fileSize: _selectedFileSize,
    );

    if (!resp['success']) {
      _showError(resp['error']?.toString() ?? 'Failed to create session');
      setState(() => _mode = 'home');
      return;
    }

    _sessionId = resp['data']['session_id']?.toString();
    setState(() => _statusText = 'Waiting for receiver...');
    _connectSignaling();
  }

  Future<void> _startReceiveFlow(String sessionId) async {
    setState(() {
      _mode = 'receiving';
      _statusText = 'Joining...';
      _sessionId = sessionId;
    _joinedSession = true;
    });

    await _loadIceServers();

    final resp = await widget.apiService.p2pJoinSession(sessionId);
    if (!resp['success']) {
      _showError(resp['error']?.toString() ?? 'Failed to join');
      setState(() => _mode = 'home');
      return;
    }

    _peerName = resp['data']['sender_name']?.toString();
    _rxFileName = resp['data']['file_name']?.toString() ?? 'file';
    _expectedSize = resp['data']['file_size'] is int ? resp['data']['file_size'] as int : int.tryParse('${resp['data']['file_size']}') ?? 0;
    setState(() => _statusText = 'Connecting to ${_peerName ?? 'sender'}...');
    _connectSignaling();
  }

  void _connectSignaling() {
    _connectTimeout?.cancel();
    final token = widget.apiService.token ?? '';
    if (_sessionId == null || token.isEmpty) {
      _showError('Not signed in — please log in again');
      return;
    }
    final wsUrl = AppConfig.p2pWsUrl(_sessionId!, token);

    try {
      _ws = connectWs(wsUrl);
      _wsAlive = true;

      _connectTimeout = Timer(const Duration(seconds: 90), () {
        if (!mounted) return;
        if (!_webrtcReady && _mode != 'transferring' && _mode != 'complete') {
          setState(() => _statusText = 'Connection timed out');
          _showError(
            'Connection timed out. Ensure Redis + ASGI (Daphne) are running and WebSocket is proxied.',
          );
        }
      });

      _ws!.stream.listen(
        (msg) {
          try {
            _onSignal(jsonDecode(msg as String));
          } catch (e) {
            debugPrint('P2P signal parse error: $e');
          }
        },
        onError: (e) {
          _wsAlive = false;
          if (mounted) {
            setState(() {
              _signalingOk = false;
              _statusText = 'Signaling error — check server WebSocket';
            });
            _showError('Signaling failed: $e');
          }
        },
        onDone: () {
          _wsAlive = false;
          if (mounted && _mode != 'complete' && _mode != 'home') {
            setState(() => _statusText = 'Signaling disconnected');
          }
        },
      );
    } catch (e) {
      _wsAlive = false;
      _showError('Signaling connection failed: $e');
    }
  }

  void _wsSend(Map<String, dynamic> data) {
    if (_ws != null && _wsAlive) {
      try {
        _ws!.sink.add(jsonEncode(data));
      } catch (_) {}
    }
  }

  Future<void> _onSignal(Map<String, dynamic> data) async {
    final type = data['type'] as String? ?? '';

    if (type == 'connected') {
      if (mounted) {
        setState(() {
          _signalingOk = true;
          _statusText = _mode == 'sending' ? 'Waiting for receiver...' : 'Signaling connected — finding peer...';
        });
      }
      return;
    }
    if (type == 'room_full') {
      _showError('This transfer already has two devices connected.');
      _cancel();
      return;
    }
    if (type == 'peer_joined') {
      _peerName = data['username']?.toString();
      if (mounted) {
        setState(() {
          _peerFound = true;
          _isConnected = true;
          _statusText = 'Peer found — setting up secure link...';
        });
      }
      return;
    }
    if (type == 'peer_left') {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _peerFound = false;
          _webrtcReady = false;
          _statusText = 'Peer disconnected';
        });
      }
      return;
    }
    if (type == 'role') {
      await _onRole(data['role']?.toString());
      return;
    }
    if (type == 'offer') {
      await _onOffer(data['sdp'] as Map<String, dynamic>?);
      return;
    }
    if (type == 'answer') {
      await _onAnswer(data['sdp'] as Map<String, dynamic>?);
      return;
    }
    if (type == 'ice_candidate') {
      await _onRemoteIce(data['candidate'] as Map<String, dynamic>?);
      return;
    }
    if (type == 'file_info') {
      _rxFileName = data['file_name']?.toString() ?? _rxFileName;
      _expectedSize = data['file_size'] is int ? data['file_size'] as int : int.tryParse('${data['file_size']}') ?? _expectedSize;
      if (data['sender_name'] != null) _peerName = data['sender_name']?.toString();
      if (mounted) setState(() => _statusText = 'Incoming: $_rxFileName');
      return;
    }
    if (type == 'transfer_complete') {
      if (mounted) {
        setState(() {
          _mode = 'complete';
          _progress = 1.0;
          _statusText = 'Transfer complete';
        });
      }
    }
  }

  Future<void> _onRole(String? role) async {
    if (role == null || role.isEmpty) return;
    _myRole = role;
    if (mounted) {
      setState(() => _statusText = 'Negotiating WebRTC (${role == 'initiator' ? 'sender' : 'receiver'})...');
    }
    await _initPc();
    if (role == 'initiator') {
      _dataChannel = await _pc!.createDataChannel('file', RTCDataChannelInit()..ordered = true);
      _setupDc(isSender: true);
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _wsSend({'type': 'offer', 'sdp': {'sdp': offer.sdp, 'type': offer.type}});
    } else {
      _ensureDataChannelHandler(isSender: false);
    }
  }

  void _ensureDataChannelHandler({required bool isSender}) {
    if (_pc == null || isSender) return;
    _pc!.onDataChannel = (ch) {
      _dataChannel = ch;
      _setupDc(isSender: false);
    };
  }

  Future<void> _onOffer(Map<String, dynamic>? sdp) async {
    if (sdp == null) return;
    _myRole ??= 'responder';
    if (_pc == null) await _initPc();
    _ensureDataChannelHandler(isSender: false);
    if (mounted) setState(() => _statusText = 'Processing connection offer...');
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()));
    _remoteReady = true;
    await _flushCandidates();
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    _wsSend({'type': 'answer', 'sdp': {'sdp': answer.sdp, 'type': answer.type}});
  }

  Future<void> _onAnswer(Map<String, dynamic>? sdp) async {
    if (sdp == null || _pc == null) return;
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()));
    _remoteReady = true;
    await _flushCandidates();
  }

  Future<void> _onRemoteIce(Map<String, dynamic>? candidate) async {
    if (candidate == null || _pc == null) return;
    if (_remoteReady) {
      try {
        await _pc!.addCandidate(RTCIceCandidate(
          candidate['candidate']?.toString(),
          candidate['sdpMid']?.toString(),
          candidate['sdpMLineIndex'] is int ? candidate['sdpMLineIndex'] as int : int.tryParse('${candidate['sdpMLineIndex']}'),
        ));
      } catch (_) {}
    } else {
      _pendingIce.add(candidate);
    }
  }

  Future<void> _flushCandidates() async {
    if (_pc == null) return;
    for (final c in List<Map<String, dynamic>>.from(_pendingIce)) {
      try {
        await _pc!.addCandidate(RTCIceCandidate(
          c['candidate']?.toString(),
          c['sdpMid']?.toString(),
          c['sdpMLineIndex'] is int ? c['sdpMLineIndex'] as int : int.tryParse('${c['sdpMLineIndex']}'),
        ));
      } catch (_) {}
    }
    _pendingIce.clear();
  }

  Future<void> _initPc() async {
    if (_pc != null) return;
    _pc = await createPeerConnection({'iceServers': _iceServers});

    _pc!.onIceCandidate = (c) => _wsSend({
      'type': 'ice_candidate',
      'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
    });

    _pc!.onIceConnectionState = (s) {
      final label = s.toString().split('.').last;
      if (mounted) setState(() => _iceState = label);
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _connectTimeout?.cancel();
        if (mounted) {
          setState(() {
            _webrtcReady = true;
            _statusText = _myRole == 'initiator'
                ? 'Connected — waiting for accept...'
                : 'Connected — preparing receive...';
          });
        }
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (mounted) {
          _showError('Direct connection failed — try Wi‑Fi or configure TURN on server');
          setState(() => _statusText = 'Connection failed (ICE)');
        }
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (mounted) setState(() => _statusText = 'Connection interrupted');
      }
    };

    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed && mounted) {
        _showError('Peer connection failed — check network or TURN server');
      }
    };
  }

  void _setupDc({required bool isSender}) {
    _dataChannel!.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen && isSender) {
        _sendMeta();
      }
    };

    _dataChannel!.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary) {
        _rxChunks.add(msg.binary);
        _rxSize += msg.binary.length;
        if (_expectedSize > 0 && mounted) {
          setState(() {
            _mode = 'transferring';
            _bytesTransferred = _rxSize;
            _progress = _rxSize / _expectedSize;
            _statusText = 'Receiving: ${(_progress * 100).toStringAsFixed(1)}% · ${_fmtSize(_rxSize)} / ${_fmtSize(_expectedSize)}';
          });
        }
        return;
      }

      try {
        final ctrl = jsonDecode(msg.text) as Map<String, dynamic>;
        final kind = ctrl['kind']?.toString();
        if (kind == 'meta' && !isSender) {
          _rxFileName = ctrl['name']?.toString() ?? _rxFileName;
          _expectedSize = ctrl['size'] is int ? ctrl['size'] as int : int.tryParse('${ctrl['size']}') ?? _expectedSize;
          if (mounted) {
            setState(() {
              _awaitingAccept = true;
              _statusText = 'Incoming file — tap Accept to begin';
            });
          }
        } else if (kind == 'ready' && isSender) {
          _sendChunks();
        } else if (kind == 'done' && !isSender) {
          _saveFile();
        }
      } catch (_) {
        if (msg.text == 'EOF') _saveFile();
      }
    };
  }

  void _sendMeta() {
    _wsSend({
      'type': 'file_info',
      'file_name': _selectedFileName,
      'file_size': _selectedFileSize,
    });
    _dataChannel?.send(RTCDataChannelMessage(jsonEncode({
      'kind': 'meta',
      'name': _selectedFileName,
      'size': _selectedFileSize,
      'type': 'application/octet-stream',
    })));
    if (mounted) setState(() => _statusText = 'Waiting for receiver to accept...');
  }

  Future<void> _acceptIncoming() async {
    if (_dataChannel == null) return;
    setState(() {
      _awaitingAccept = false;
      _mode = 'transferring';
      _statusText = 'Receiving...';
    });
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({'kind': 'ready'})));
  }

  Future<void> _sendChunks() async {
    if (_selectedFileBytes == null || _dataChannel == null) return;
    if (mounted) {
      setState(() {
        _mode = 'transferring';
        _statusText = 'Sending...';
      });
    }

    final total = _selectedFileBytes!.length;
    var off = 0;
    while (off < total) {
      while ((_dataChannel!.bufferedAmount ?? 0) > _highWater) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      final end = min(off + _chunkSize, total);
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(_selectedFileBytes!.sublist(off, end)));
      off = end;
      if (mounted) {
        setState(() {
          _progress = off / total;
          _bytesTransferred = off;
          _statusText = 'Sending: ${(_progress * 100).toStringAsFixed(1)}% · ${_fmtSize(off)} / ${_fmtSize(total)}';
        });
      }
      await Future.delayed(const Duration(milliseconds: 2));
    }

    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({'kind': 'done'})));
    _wsSend({'type': 'transfer_complete'});
    if (mounted) {
      setState(() {
        _mode = 'complete';
        _progress = 1.0;
        _statusText = 'Sent successfully!';
      });
    }
  }

  Future<void> _saveFile() async {
    try {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final path = '${dir.path}${Platform.pathSeparator}$_rxFileName';
      final bb = BytesBuilder();
      for (final c in _rxChunks) {
        bb.add(c);
      }
      await File(path).writeAsBytes(bb.toBytes());
      _rxChunks.clear();
      _rxSize = 0;
      if (mounted) {
        setState(() {
          _mode = 'complete';
          _progress = 1.0;
          _statusText = 'Saved to $path';
        });
      }
    } catch (e) {
      _showError('Save failed: $e');
    }
  }

  void _cancel() {
    _cleanup();
    _rxChunks.clear();
    _rxSize = 0;
    _selectedFileBytes = null;
    _awaitingAccept = false;
    _joinedSession = false;
    setState(() {
      _mode = 'home';
      _progress = 0;
      _statusText = '';
      _isConnected = false;
      _signalingOk = false;
      _peerFound = false;
      _webrtcReady = false;
      _iceState = '';
      _bytesTransferred = 0;
      _sessionId = null;
    });
  }

  void _showError(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: AppTheme.danger),
      );
    }
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }

  Widget _statusStepsPanel() {
    final steps = <({String label, bool done, bool active})>[
      (label: 'Signaling', done: _signalingOk, active: !_signalingOk),
      (label: 'Peer found', done: _peerFound, active: _signalingOk && !_peerFound),
      (label: 'WebRTC', done: _webrtcReady, active: _peerFound && !_webrtcReady),
      (label: _mode == 'transferring' ? 'Transfer' : 'Connected', done: _mode == 'complete', active: _webrtcReady && _mode != 'complete'),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassPanel(borderRadius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Connection status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 10),
          ...steps.map((s) {
            final color = s.done ? AppTheme.success : (s.active ? AppTheme.accent : AppTheme.textMuted);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    s.done ? Icons.check_circle_rounded : (s.active ? Icons.radio_button_checked : Icons.radio_button_off),
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.label, style: TextStyle(fontSize: 13, color: color))),
                  if (s.label == 'WebRTC' && _iceState.isNotEmpty)
                    Text(_iceState, style: TextStyle(fontSize: 11, color: AppTheme.textMuted.withValues(alpha: 0.9))),
                ],
              ),
            );
          }),
          if (_statusText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_statusText, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _unsupportedPlatform() {
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(
              'File transfer not available on Linux yet',
              style: AppTheme.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Use the Windows or mobile app for peer-to-peer file transfer.',
              style: AppTheme.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) return body;

    return Container(
      decoration: AppTheme.screenGradient(),
      child: SafeArea(child: body),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.peerToPeerFileTransfer) {
      return _unsupportedPlatform();
    }

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_mode != 'home' && _mode != 'complete') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _statusStepsPanel(),
            ),
          ] else if (_isConnected) ...[
            Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: _connectionBanner()),
          ],
          Expanded(child: _body()),
        ],
      );
    }

    return Container(
      decoration: AppTheme.screenGradient(),
      child: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _connectionBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.35)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: AppTheme.success),
            SizedBox(width: 8),
            Text('Peer connected', style: TextStyle(color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          if (_mode != 'home')
            IconButton(
              onPressed: _cancel,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textMuted, size: 20),
            ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.accent, AppTheme.primary]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Peer2Peer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const Spacer(),
          if (_isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('Connected', style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_mode) {
      case 'sending':
        return _sendView();
      case 'receiving':
        return _recvView();
      case 'transferring':
        return _xferView();
      case 'complete':
        return _doneView();
      default:
        return _homeView();
    }
  }

  Widget _homeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accent.withValues(alpha: 0.25 + _pulseCtrl.value * 0.15),
                    AppTheme.primary.withValues(alpha: 0.25 + _pulseCtrl.value * 0.15),
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: AppTheme.primary.withValues(alpha: 0.15 + _pulseCtrl.value * 0.1), blurRadius: 30),
                ],
              ),
              child: const Icon(Icons.swap_horiz_rounded, color: AppTheme.accent, size: 48),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Peer-to-Peer File Transfer', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text(
            'Send files directly between devices.\nNothing stored on the server.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.textMuted.withValues(alpha: 0.9), height: 1.5),
          ),
          const SizedBox(height: 40),
          _actionCard(Icons.upload_file_rounded, 'Send File', 'Pick a file and share via QR code', [AppTheme.primary, AppTheme.primaryBright], _startSendFlow),
          const SizedBox(height: 16),
          _actionCard(Icons.download_rounded, 'Receive File', 'Enter code to receive', [AppTheme.success, const Color(0xFF16A34A)], () => setState(() => _mode = 'receiving')),
        ],
      ),
    );
  }

  Widget _actionCard(IconData ic, String t, String s, List<Color> g, VoidCallback fn) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: fn,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.glassPanel(borderRadius: 16).copyWith(
            border: Border.all(color: g[0].withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(gradient: LinearGradient(colors: g), borderRadius: BorderRadius.circular(14)),
                child: Icon(ic, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text(s, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textMuted, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sendView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.glassPanel(borderRadius: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.insert_drive_file_rounded, color: AppTheme.primaryBright, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedFileName ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(_fmtSize(_selectedFileSize), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_sessionId != null) ...[
            const Text('Scan QR or share code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2), blurRadius: 30)],
              ),
              child: QrImageView(
                data: _sessionId!,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1E293B)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1E293B)),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _sessionId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied!'), backgroundColor: AppTheme.success, duration: Duration(seconds: 1)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: AppTheme.glassPanel(borderRadius: 12).copyWith(
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_sessionId!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accent, letterSpacing: 2)),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy_rounded, color: AppTheme.textMuted, size: 16),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _statusStepsPanel(),
          if (!_peerFound && _sessionId != null) ...[
            const SizedBox(height: 16),
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
          ],
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
          ),
        ],
      ),
    );
  }

  Widget _recvView() {
    if (_joinedSession) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _statusStepsPanel(),
            const SizedBox(height: 24),
            if (!_awaitingAccept) ...[
              const CircularProgressIndicator(color: AppTheme.success, strokeWidth: 3),
              const SizedBox(height: 20),
            ] else ...[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.file_download_rounded, color: AppTheme.primaryBright, size: 32),
              ),
              const SizedBox(height: 20),
            ],
            if (_peerName != null) ...[
              Text('From: $_peerName', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
            ],
            if (_awaitingAccept) ...[
              Text(_rxFileName, style: const TextStyle(color: AppTheme.accent, fontSize: 14)),
              Text(_fmtSize(_expectedSize), style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _acceptIncoming,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Accept & receive'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.success, size: 64),
          const SizedBox(height: 20),
          const Text('Receive a File', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 32),
          const Text('Enter the transfer code:', style: TextStyle(fontSize: 14, color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          TextField(
            controller: _joinCtrl,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(hintText: 'Paste code here'),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) _startReceiveFlow(v.trim());
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final c = _joinCtrl.text.trim();
                if (c.isNotEmpty) _startReceiveFlow(c);
              },
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Join', style: TextStyle(fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _xferView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: CircularProgressIndicator(
                      value: _progress,
                      strokeWidth: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(_progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      Text(_progress < 1 ? 'Transferring' : 'Done', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(_selectedFileName ?? _rxFileName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text(_statusText, style: const TextStyle(fontSize: 14, color: AppTheme.textMuted)),
            if (_bytesTransferred > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${_fmtSize(_bytesTransferred)} transferred',
                style: const TextStyle(fontSize: 12, color: AppTheme.accent),
              ),
            ],
            if (_peerName != null) ...[
              const SizedBox(height: 4),
              Text('with $_peerName', style: const TextStyle(fontSize: 13, color: AppTheme.accent)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _doneView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 48),
            ),
            const SizedBox(height: 24),
            const Text('Transfer Complete!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text(_selectedFileName ?? _rxFileName, style: const TextStyle(fontSize: 15, color: AppTheme.accent, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_statusText, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.home_rounded, size: 18),
                label: const Text('Back to Home', style: TextStyle(fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
