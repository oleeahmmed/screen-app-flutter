import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../utils/ws_connect.dart';
import '../utils/platform_capabilities.dart';
import '../utils/local_file_actions.dart';
import '../services/api_service.dart';
import '../services/p2p_received_store.dart';
import '../theme/app_theme.dart';
import '../widgets/p2p_ui.dart';
import '../widgets/vault/vault_helpers.dart';

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

class _Peer2PeerPageState extends State<Peer2PeerPage> {
  String _mode = 'home';
  String? _sessionId;
  String? _peerName;
  String? _selectedFileName;
  int _selectedFileSize = 0;
  String? _selectedFilePath;
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

  RandomAccessFile? _rxFile;
  String? _rxSavePath;
  String? _rxContentUri;
  int _rxWritten = 0;
  String _rxFileName = '';
  int _expectedSize = 0;
  int _rxSize = 0;
  bool _awaitingAccept = false;
  bool _joinedSession = false;
  bool _webrtcStarted = false;
  String? _peerPlatform;
  Timer? _wsReconnectTimer;
  Timer? _offerFallbackTimer;
  int _wsReconnectAttempt = 0;

  final _joinCtrl = TextEditingController();
  List<Map<String, dynamic>> _received = [];

  static const _chunkSize = 16384;
  static const _highWater = 8 * 1024 * 1024;
  static const _desktopPlatforms = {'windows', 'linux', 'macos'};

  static const _pcConstraints = <String, dynamic>{
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 8,
  };

  bool get _amFileSender => _mode == 'sending';
  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Prefer desktop as WebRTC offerer (better ICE vs mobile NAT). Else file sender.
  bool get _shouldBeInitiator {
    final peer = (_peerPlatform ?? '').toLowerCase();
    final peerDesktop = _desktopPlatforms.contains(peer);
    if (_isDesktop != peerDesktop) return _isDesktop;
    return _amFileSender;
  }

  String _normalizeSessionCode(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    final uri = Uri.tryParse(t);
    if (uri != null) {
      final code = uri.queryParameters['code'];
      if (code != null && code.trim().isNotEmpty) return code.trim().toLowerCase();
      if (uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last.trim();
        if (last.length >= 8 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(last)) {
          return last.toLowerCase();
        }
      }
    }
    return t.toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _loadReceived();
  }

  Future<void> _loadReceived() async {
    final items = await P2pReceivedStore.load();
    if (!mounted) return;
    setState(() => _received = items);
  }

  @override
  void dispose() {
    _cleanup();
    _joinCtrl.dispose();
    super.dispose();
  }

  void _cleanup() {
    _connectTimeout?.cancel();
    _connectTimeout = null;
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = null;
    _offerFallbackTimer?.cancel();
    _offerFallbackTimer = null;
    try {
      _dataChannel?.close();
    } catch (_) {}
    try {
      _pc?.close();
    } catch (_) {}
    try {
      _ws?.sink.close();
    } catch (_) {}
    try {
      _rxFile?.close();
    } catch (_) {}
    _dataChannel = null;
    _pc = null;
    _ws = null;
    _wsAlive = false;
    _rxFile = null;
    _rxSavePath = null;
    _rxWritten = 0;
    _myRole = null;
    _remoteReady = false;
    _pendingIce.clear();
    _signalingOk = false;
    _peerFound = false;
    _webrtcReady = false;
    _webrtcStarted = false;
    _peerPlatform = null;
    _wsReconnectAttempt = 0;
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
    debugPrint('[P2P] ICE servers: ${_iceServers.length}');
  }

  RTCIceCandidate _makeIceCandidate(Map<String, dynamic> candidate) {
    final idx = candidate['sdpMLineIndex'];
    int lineIndex = 0;
    if (idx is int) {
      lineIndex = idx;
    } else if (idx != null) {
      lineIndex = int.tryParse('$idx') ?? 0;
    }
    final mid = candidate['sdpMid']?.toString();
    return RTCIceCandidate(
      candidate['candidate']?.toString(),
      (mid != null && mid.isNotEmpty) ? mid : '0',
      lineIndex,
    );
  }

  Future<Map<String, dynamic>> _localSdpPayload(RTCPeerConnection pc) async {
    final desc = await pc.getLocalDescription();
    return {'sdp': desc?.sdp ?? '', 'type': desc?.type ?? 'offer'};
  }

  void _sendHello() {
    _wsSend({
      'type': 'hello',
      'platform': Platform.operatingSystem.toLowerCase(),
    });
  }

  void _scheduleWsReconnect() {
    if (!mounted) return;
    if (_mode != 'sending' && _mode != 'receiving') return;
    if (_webrtcReady || _mode == 'transferring' || _mode == 'complete') return;
    _wsReconnectTimer?.cancel();
    final delay = Duration(seconds: (1 + _wsReconnectAttempt).clamp(1, 8));
    _wsReconnectAttempt += 1;
    _wsReconnectTimer = Timer(delay, () {
      if (!mounted || _wsAlive) return;
      if (_mode != 'sending' && _mode != 'receiving') return;
      debugPrint('[P2P] Reconnecting signaling (attempt $_wsReconnectAttempt)...');
      if (mounted) {
        setState(() => _statusText = 'Reconnecting signaling…');
      }
      _connectSignaling(isReconnect: true);
    });
  }

  Future<void> _startSendFlow() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: false);
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.first;

    String? path = pf.path;
    var size = pf.size;
    if (path == null || path.isEmpty) {
      _showError('Could not access the selected file path');
      return;
    }
    if (size <= 0) {
      size = await File(path).length();
    }

    _selectedFilePath = path;
    _selectedFileName = pf.name;
    _selectedFileSize = size;

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
    final normalized = _normalizeSessionCode(sessionId);
    if (normalized.isEmpty) {
      _showError('Invalid session code');
      return;
    }
    setState(() {
      _mode = 'receiving';
      _statusText = 'Joining...';
      _sessionId = normalized;
      _joinedSession = true;
    });

    await _loadIceServers();

    final resp = await widget.apiService.p2pJoinSession(normalized);
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

  void _connectSignaling({bool isReconnect = false}) {
    _connectTimeout?.cancel();
    _wsReconnectTimer?.cancel();
    final token = widget.apiService.token ?? '';
    if (_sessionId == null || token.isEmpty) {
      _showError('Not signed in — please log in again');
      return;
    }
    final wsUri = AppConfig.p2pWsUri(_sessionId!, token);

    try {
      try {
        _ws?.sink.close();
      } catch (_) {}
      _ws = connectWsUri(wsUri);
      _wsAlive = true;
      if (!isReconnect) {
        _wsReconnectAttempt = 0;
        _webrtcStarted = false;
        _peerPlatform = null;
      }

      _connectTimeout = Timer(const Duration(seconds: 90), () {
        if (!mounted) return;
        if (!_webrtcReady && _mode != 'transferring' && _mode != 'complete') {
          setState(() => _statusText = 'Connection timed out');
          _showError(
            'Connection timed out. Keep both apps open on the same network, or ask admin to enable TURN.',
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
              _statusText = 'Signaling error — reconnecting…';
            });
          }
          _scheduleWsReconnect();
        },
        onDone: () {
          _wsAlive = false;
          if (mounted && _mode != 'complete' && _mode != 'home') {
            setState(() {
              _signalingOk = false;
              _statusText = 'Signaling disconnected — reconnecting…';
            });
            _scheduleWsReconnect();
          }
        },
      );
    } catch (e) {
      _wsAlive = false;
      _showError('Signaling connection failed: $e');
      _scheduleWsReconnect();
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
      _wsReconnectAttempt = 0;
      if (mounted) {
        setState(() {
          _signalingOk = true;
          _statusText = _mode == 'sending'
              ? 'Waiting for receiver...'
              : (_peerFound
                  ? 'Peer found — setting up secure link...'
                  : 'Signaling connected — finding peer...');
        });
      }
      _sendHello();
      return;
    }
    if (type == 'room_full') {
      _showError('This transfer already has two devices connected.');
      _cancel();
      return;
    }
    if (type == 'peer_joined') {
      _peerName = data['username']?.toString() ?? _peerName;
      if (mounted) {
        setState(() {
          _peerFound = true;
          _isConnected = true;
          _statusText = 'Peer found — setting up secure link...';
        });
      }
      _sendHello();
      _offerFallbackTimer?.cancel();
      _offerFallbackTimer = Timer(const Duration(milliseconds: 1800), () {
        if (!_webrtcStarted) {
          unawaited(_maybeStartWebRtc(reason: 'peer-joined-fallback'));
        }
      });
      return;
    }
    if (type == 'peer_left') {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _peerFound = false;
          _webrtcReady = false;
          _webrtcStarted = false;
          _peerPlatform = null;
          _statusText = 'Peer disconnected — waiting…';
        });
      }
      _offerFallbackTimer?.cancel();
      return;
    }
    if (type == 'hello') {
      _peerPlatform = data['platform']?.toString().toLowerCase();
      if (mounted) {
        setState(() {
          _peerFound = true;
          _isConnected = true;
          if (!_webrtcReady) {
            _statusText = 'Peer found — setting up secure link...';
          }
        });
      }
      await _maybeStartWebRtc(reason: 'hello');
      return;
    }
    if (type == 'role') {
      // Server role is a fallback if peer hello never arrives.
      _myRole ??= data['role']?.toString();
      _offerFallbackTimer?.cancel();
      _offerFallbackTimer = Timer(const Duration(seconds: 2), () {
        if (!_webrtcStarted && _peerFound) {
          unawaited(_maybeStartWebRtc(reason: 'role-fallback'));
        }
      });
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

  Future<void> _maybeStartWebRtc({required String reason}) async {
    if (_webrtcStarted || _pc != null) return;
    if (!_peerFound && _peerPlatform == null) return;

    // Need peer platform for desktop-prefer rule; fall back to file-sender role.
    final iAmInitiator = _peerPlatform != null ? _shouldBeInitiator : _amFileSender;
    debugPrint('[P2P] start WebRTC ($reason) initiator=$iAmInitiator platform=${Platform.operatingSystem} peer=$_peerPlatform');
    await _startAsRole(iAmInitiator ? 'initiator' : 'responder');
  }

  Future<void> _startAsRole(String role) async {
    if (_webrtcStarted) return;
    _webrtcStarted = true;
    _myRole = role;
    _offerFallbackTimer?.cancel();
    if (mounted) {
      setState(() => _statusText = 'Negotiating WebRTC (${_amFileSender ? 'sending' : 'receiving'})...');
    }
    await _initPc();
    if (role == 'initiator') {
      _dataChannel = await _pc!.createDataChannel('file', RTCDataChannelInit()..ordered = true);
      _setupDc(isSender: _amFileSender);
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      // Trickle ICE — send SDP immediately (do not wait for gathering).
      _wsSend({'type': 'offer', 'sdp': await _localSdpPayload(_pc!)});
    } else {
      _ensureDataChannelHandler(isSender: _amFileSender);
    }
  }

  void _ensureDataChannelHandler({required bool isSender}) {
    if (_pc == null) return;
    _pc!.onDataChannel = (ch) {
      _dataChannel = ch;
      _setupDc(isSender: isSender);
    };
  }

  Future<void> _onOffer(Map<String, dynamic>? sdp) async {
    if (sdp == null) return;
    // Glare: if we already created an offer, ignore remote offer when we should be initiator.
    if (_myRole == 'initiator' && _pc != null) {
      debugPrint('[P2P] Ignoring remote offer (we are initiator)');
      return;
    }
    _myRole = 'responder';
    _webrtcStarted = true;
    _offerFallbackTimer?.cancel();
    if (_pc == null) await _initPc();
    _ensureDataChannelHandler(isSender: _amFileSender);
    if (mounted) setState(() => _statusText = 'Processing connection offer...');
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()));
    _remoteReady = true;
    await _flushCandidates();
    final answer = await _pc!.createAnswer(_sessionConstraints);
    await _pc!.setLocalDescription(answer);
    _wsSend({'type': 'answer', 'sdp': await _localSdpPayload(_pc!)});
  }

  Future<void> _onAnswer(Map<String, dynamic>? sdp) async {
    if (sdp == null || _pc == null) return;
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()));
    _remoteReady = true;
    await _flushCandidates();
  }

  Future<void> _onRemoteIce(Map<String, dynamic>? candidate) async {
    if (candidate == null || _pc == null) return;
    final cand = candidate['candidate']?.toString();
    if (cand == null || cand.isEmpty) return;
    if (_remoteReady) {
      try {
        await _pc!.addCandidate(_makeIceCandidate(candidate));
      } catch (e) {
        debugPrint('[P2P] addCandidate error: $e');
      }
    } else {
      _pendingIce.add(candidate);
    }
  }

  Future<void> _flushCandidates() async {
    if (_pc == null) return;
    for (final c in List<Map<String, dynamic>>.from(_pendingIce)) {
      try {
        await _pc!.addCandidate(_makeIceCandidate(c));
      } catch (e) {
        debugPrint('[P2P] flush ICE error: $e');
      }
    }
    _pendingIce.clear();
  }

  Future<void> _initPc() async {
    if (_pc != null) return;
    _pc = await createPeerConnection({
      'iceServers': _iceServers,
      ..._pcConstraints,
    });

    _pc!.onIceCandidate = (c) {
      final cand = c.candidate;
      if (cand == null || cand.isEmpty) return;
      _wsSend({
        'type': 'ice_candidate',
        'candidate': {
          'candidate': cand,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };

    _pc!.onIceConnectionState = (s) {
      final label = s.toString().split('.').last;
      if (mounted) setState(() => _iceState = label);
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _connectTimeout?.cancel();
        _wsReconnectTimer?.cancel();
        if (mounted) {
          setState(() {
            _webrtcReady = true;
            _statusText = _amFileSender
                ? 'Connected — waiting for accept...'
                : 'Connected — preparing receive...';
          });
        }
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (mounted) {
          final hasTurn = _iceServers.any((srv) {
            final urls = srv['urls'];
            if (urls is List) {
              return urls.any((u) => u.toString().startsWith('turn'));
            }
            return urls?.toString().startsWith('turn') == true;
          });
          _showError(
            hasTurn
                ? 'Connection failed — check firewall allows UDP/TCP 3478 or try another network'
                : 'Direct connection failed — server needs TURN (coturn). Ask admin to set TURN_HOST in .env',
          );
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

    _dataChannel!.onMessage = (RTCDataChannelMessage msg) async {
      if (msg.isBinary) {
        if (_rxFile != null) {
          await _rxFile!.writeFrom(msg.binary);
        }
        _rxWritten += msg.binary.length;
        _rxSize = _rxWritten;
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

  Future<void> _openReceiveFile() async {
    final dir = await LocalFileActions.receiveTempDirectory();
    final safeName = _rxFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    _rxSavePath = '${dir.path}${Platform.pathSeparator}$safeName';
    _rxContentUri = null;
    final file = File(_rxSavePath!);
    if (await file.exists()) {
      await file.delete();
    }
    _rxFile = await file.open(mode: FileMode.write);
    _rxWritten = 0;
    _rxSize = 0;
  }

  Future<void> _acceptIncoming() async {
    if (_dataChannel == null) return;
    try {
      await _openReceiveFile();
    } catch (e) {
      _showError('Could not prepare save location: $e');
      return;
    }
    setState(() {
      _awaitingAccept = false;
      _mode = 'transferring';
      _statusText = 'Receiving...';
    });
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({'kind': 'ready'})));
  }

  Future<void> _sendChunks() async {
    final path = _selectedFilePath;
    if (path == null || _dataChannel == null) return;
    if (mounted) {
      setState(() {
        _mode = 'transferring';
        _statusText = 'Sending...';
      });
    }

    final file = File(path);
    final total = _selectedFileSize > 0 ? _selectedFileSize : await file.length();
    final raf = await file.open(mode: FileMode.read);
    try {
      var off = 0;
      final buf = Uint8List(_chunkSize);
      while (off < total) {
        while ((_dataChannel!.bufferedAmount ?? 0) > _highWater) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        final toRead = min(_chunkSize, total - off);
        final read = await raf.readInto(buf, 0, toRead);
        if (read <= 0) break;
        _dataChannel!.send(RTCDataChannelMessage.fromBinary(Uint8List.sublistView(buf, 0, read)));
        off += read;
        if (mounted) {
          setState(() {
            _progress = off / total;
            _bytesTransferred = off;
            _statusText = 'Sending: ${(_progress * 100).toStringAsFixed(1)}% · ${_fmtSize(off)} / ${_fmtSize(total)}';
          });
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }
    } finally {
      await raf.close();
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
      if (_rxFile != null) {
        await _rxFile!.close();
        _rxFile = null;
      }
      var path = _rxSavePath;
      if (path == null || !await File(path).exists()) {
        _showError('Receive failed — no file saved');
        return;
      }

      var contentUri = _rxContentUri;
      final displayName = _rxFileName.isNotEmpty
          ? _rxFileName
          : path.split(Platform.pathSeparator).last;

      if (Platform.isAndroid) {
        try {
          final committed = await LocalFileActions.commitReceiveFile(path, displayName);
          path = committed['path'] ?? path;
          contentUri = committed['contentUri'];
          _rxSavePath = path;
          _rxContentUri = contentUri;
        } catch (e) {
          _showError('Save failed: $e');
          return;
        }
      }

      if (mounted) {
        setState(() {
          _mode = 'complete';
          _progress = 1.0;
          _statusText = Platform.isAndroid
              ? 'Saved to Download/Aims'
              : 'Saved to $path';
        });
      }
      unawaited(P2pReceivedStore.add(
        name: displayName,
        path: path,
        size: _expectedSize > 0 ? _expectedSize : _rxSize,
        contentUri: contentUri,
      ).then((_) => _loadReceived()));
    } catch (e) {
      _showError('Save failed: $e');
    }
  }

  Future<void> _openLocalFile(String path, {String? contentUri}) async {
    if (contentUri == null) {
      final f = File(path);
      if (!await f.exists()) {
        _showError('File not found');
        await P2pReceivedStore.remove(path);
        await _loadReceived();
        return;
      }
    }
    final r = await LocalFileActions.openFile(path, contentUri: contentUri);
    if (!mounted) return;
    if (r == 'missing') {
      _showError('File not found');
      return;
    }
    if (r == 'no_handler') {
      _showOpenWithHelp(path);
      return;
    }
    if (r != 'ok' && r != 'ok_downloads') {
      _showError(r.isNotEmpty ? r : 'Could not open file');
    }
  }

  Future<void> _openLocalFolder(String path) async {
    final file = File(path);
    final dirPath = file.parent.path;
    final r = await LocalFileActions.openFolder(path);
    if (!mounted) return;
    if (r == 'ok' || r == 'ok_downloads') {
      if (r == 'ok_downloads') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opened Downloads — look in the Aims folder'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Open folder',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  dirPath,
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined, color: AppTheme.primaryBright),
                  title: const Text('Open file with…', style: TextStyle(color: AppTheme.textPrimary)),
                  subtitle: Text(
                    'Choose an app for this file',
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openLocalFile(path);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_all_outlined, color: AppTheme.accent),
                  title: const Text('Copy folder path', style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: dirPath));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Path copied'), backgroundColor: AppTheme.success),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOpenWithHelp(String path) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final name = path.split(Platform.pathSeparator).last;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Open with',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'No default app for “$name”. Try again or open the folder in Files.',
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: const Icon(Icons.apps_outlined, color: AppTheme.primaryBright),
                  title: const Text('Try Open with again', style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    LocalFileActions.openFile(path);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined, color: AppTheme.accent),
                  title: const Text('Open folder', style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openLocalFolder(path);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _scanQrAndJoin() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        _showError('Camera permission needed to scan QR');
        return;
      }
    }
    if (!mounted) return;
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _P2pQrScanPage()),
    );
    if (code == null || code.trim().isEmpty) return;
    final sessionId = _normalizeSessionCode(code);
    _joinCtrl.text = sessionId;
    await _startReceiveFlow(sessionId);
  }

  Future<void> _cancel() async {
    final sid = _sessionId;
    final wasSender = _mode == 'sending' || _myRole == 'initiator';
    _cleanup();
    _rxWritten = 0;
    _selectedFilePath = null;
    _awaitingAccept = false;
    _joinedSession = false;
    if (sid != null && wasSender) {
      unawaited(widget.apiService.p2pCancelSession(sid));
    }
    setState(() {
      _mode = 'home';
      _progress = 0;
      _statusText = '';
      _isConnected = false;
      _signalingOk = false;
      _peerFound = false;
      _webrtcReady = false;
      _webrtcStarted = false;
      _peerPlatform = null;
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

  void _copySessionCode() {
    if (_sessionId == null) return;
    Clipboard.setData(ClipboardData(text: _sessionId!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied!'),
        backgroundColor: AppTheme.success,
        duration: Duration(seconds: 1),
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
      return _body();
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
    return P2pPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          vaultSectionLabel('Transfer'),
          const SizedBox(height: 10),
          vaultSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Send or receive files directly between devices',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.95),
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _bigAction(
                        color: AppTheme.primary,
                        icon: Icons.upload_rounded,
                        label: 'Send',
                        onTap: _startSendFlow,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _bigAction(
                        color: AppTheme.success,
                        icon: Icons.download_rounded,
                        label: 'Receive',
                        onTap: () => setState(() => _mode = 'receiving'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          vaultSectionLabel('Received files'),
          const SizedBox(height: 10),
          if (_received.isEmpty)
            vaultSurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 36, color: AppTheme.textMuted.withValues(alpha: 0.55)),
                  const SizedBox(height: 10),
                  Text(
                    'No files received yet',
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13.5),
                  ),
                ],
              ),
            )
          else
            ..._received.map(_receivedTile),
        ],
      ),
    );
  }

  Widget _bigAction({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 108,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.7)],
            ),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receivedTile(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? 'File';
    final path = item['path']?.toString() ?? '';
    final contentUri = item['contentUri']?.toString();
    final size = item['size'] is int ? item['size'] as int : int.tryParse('${item['size']}') ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: vaultSurfaceCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            vaultIconBox(icon: Icons.insert_drive_file_outlined, color: AppTheme.accent, size: 42, iconSize: 20, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    size > 0 ? _fmtSize(size) : 'Received',
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open file',
              onPressed: path.isEmpty ? null : () => _openLocalFile(path, contentUri: contentUri),
              icon: const Icon(Icons.open_in_new_rounded, size: 20, color: AppTheme.primaryBright),
            ),
            IconButton(
              tooltip: 'Open folder',
              onPressed: path.isEmpty ? null : () => _openLocalFolder(path),
              icon: Icon(Icons.folder_open_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.9)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sendView() {
    return P2pPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          vaultSectionLabel('Send'),
          const SizedBox(height: 10),
          vaultSurfaceCard(
            child: Column(
              children: [
                Text(
                  _selectedFileName ?? 'File',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(_fmtSize(_selectedFileSize), style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13)),
                if (_sessionId != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: QrImageView(
                      data: _sessionId!,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  P2pSessionCodeBadge(code: _sessionId!, onCopy: _copySessionCode),
                  const SizedBox(height: 12),
                  Text(
                    'Ask them to tap Receive → Scan QR',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  !_signalingOk
                      ? 'Connecting…'
                      : !_peerFound
                          ? 'Waiting for the other phone…'
                          : (_webrtcReady ? (_statusText.isEmpty ? 'Connected' : _statusText) : 'Linking devices…${_iceState.isEmpty ? '' : ' ($_iceState)'}'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.primaryBright.withValues(alpha: 0.95), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          P2pGhostButton(label: 'Cancel', icon: LucideIcons.x, onTap: _cancel),
        ],
      ),
    );
  }

  Widget _recvView() {
    if (_joinedSession) {
      return P2pPageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            vaultSectionLabel('Receive'),
            const SizedBox(height: 10),
            vaultSurfaceCard(
              child: Column(
                children: [
                  Text(
                    _awaitingAccept ? 'Incoming file' : 'Connecting…',
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  if (_peerName != null) ...[
                    const SizedBox(height: 6),
                    Text('From $_peerName', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9))),
                  ],
                  const SizedBox(height: 16),
                  if (_awaitingAccept) ...[
                    Text(_rxFileName, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    Text(_fmtSize(_expectedSize), style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85))),
                    const SizedBox(height: 18),
                    P2pPrimaryButton(
                      label: 'Accept',
                      icon: LucideIcons.check,
                      onTap: _acceptIncoming,
                      gradient: const [Color(0xFF10B981), Color(0xFF047857)],
                    ),
                  ] else ...[
                    P2pStatusSteps(
                      steps: [
                        (label: 'Signaling', done: _signalingOk, active: !_signalingOk),
                        (label: 'Peer found', done: _peerFound, active: _signalingOk && !_peerFound),
                        (
                          label: 'WebRTC',
                          done: _webrtcReady,
                          active: _peerFound && !_webrtcReady,
                        ),
                        (
                          label: 'Connected',
                          done: _webrtcReady && (_awaitingAccept || _mode == 'transferring'),
                          active: false,
                        ),
                      ],
                      statusText: _statusText,
                      iceState: _iceState.isEmpty ? null : _iceState,
                    ),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(color: AppTheme.success),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            P2pGhostButton(label: 'Cancel', icon: LucideIcons.x, onTap: _cancel),
          ],
        ),
      );
    }

    final canScan = Platform.isAndroid || Platform.isIOS;

    return P2pPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          vaultSectionLabel('Receive'),
          const SizedBox(height: 10),
          if (canScan) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _scanQrAndJoin,
                borderRadius: BorderRadius.circular(18),
                child: Ink(
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    boxShadow: [
                      BoxShadow(color: AppTheme.success.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 40),
                      SizedBox(height: 10),
                      Text('Scan QR code', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text('or enter code', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12.5)),
            ),
            const SizedBox(height: 10),
          ],
          vaultSurfaceCard(
            child: Column(
              children: [
                P2pJoinField(
                  controller: _joinCtrl,
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _startReceiveFlow(v.trim());
                  },
                ),
                const SizedBox(height: 12),
                P2pPrimaryButton(
                  label: 'Join',
                  icon: LucideIcons.logIn,
                  onTap: () {
                    final c = _joinCtrl.text.trim();
                    if (c.isNotEmpty) _startReceiveFlow(c);
                  },
                  gradient: const [Color(0xFF10B981), Color(0xFF047857)],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          P2pGhostButton(label: 'Back', icon: LucideIcons.arrowLeft, onTap: _cancel, color: AppTheme.textMuted),
        ],
      ),
    );
  }

  Widget _xferView() {
    final pct = (_progress * 100).clamp(0, 100);
    return P2pPageFrame(
      center: true,
      scroll: false,
      child: vaultSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    strokeWidth: 7,
                    color: AppTheme.primaryBright,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                  Text(
                    _progress > 0 ? '${pct.toStringAsFixed(0)}%' : '…',
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _selectedFileName ?? _rxFileName,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
            ),
            if (_bytesTransferred > 0) ...[
              const SizedBox(height: 6),
              Text(
                _fmtSize(_bytesTransferred),
                style: TextStyle(color: AppTheme.primaryBright.withValues(alpha: 0.95), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _doneView() {
    final path = _rxSavePath ?? _selectedFilePath;
    final isReceived = _rxSavePath != null && _rxSavePath!.isNotEmpty;

    return P2pPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          vaultSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.success.withValues(alpha: 0.18),
                    border: Border.all(color: AppTheme.success.withValues(alpha: 0.45)),
                  ),
                  child: const Icon(Icons.check_rounded, color: AppTheme.success, size: 40),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Done',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedFileName ?? _rxFileName,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.95), fontSize: 14),
                ),
              ],
            ),
          ),
          if (isReceived && path != null) ...[
            const SizedBox(height: 14),
            P2pPrimaryButton(
              label: 'Open file',
              icon: LucideIcons.externalLink,
              onTap: () => _openLocalFile(path, contentUri: _rxContentUri),
              gradient: const [Color(0xFF10B981), Color(0xFF047857)],
            ),
            const SizedBox(height: 10),
            P2pPrimaryButton(
              label: 'Open folder',
              icon: LucideIcons.folderOpen,
              onTap: () => _openLocalFolder(path),
              gradient: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
            ),
            const SizedBox(height: 18),
            const Text(
              'Transfer complete',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            P2pFilePreview(
              fileName: _selectedFileName ?? _rxFileName,
              fileSize: _statusText,
              icon: LucideIcons.fileCheck,
              gradient: const [Color(0xFF10B981), Color(0xFF059669)],
            ),
            const SizedBox(height: 18),
            P2pPrimaryButton(
              label: 'Back to home',
              icon: LucideIcons.home,
              onTap: _cancel,
              gradient: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
            ),
          ],
          const SizedBox(height: 10),
          P2pGhostButton(label: 'Back', icon: LucideIcons.home, onTap: _cancel),
        ],
      ),
    );
  }
}

/// Full-screen QR scanner for joining a P2P session.
class _P2pQrScanPage extends StatefulWidget {
  const _P2pQrScanPage();

  @override
  State<_P2pQrScanPage> createState() => _P2pQrScanPageState();
}

class _P2pQrScanPageState extends State<_P2pQrScanPage> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        _done = true;
        Navigator.pop(context, v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan transfer QR'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2.5),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Point at the sender’s QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
