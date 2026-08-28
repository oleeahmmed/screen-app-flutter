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
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../utils/ws_connect.dart';
import '../utils/platform_capabilities.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/p2p_ui.dart';

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
  int _rxWritten = 0;
  String _rxFileName = '';
  int _expectedSize = 0;
  int _rxSize = 0;
  bool _awaitingAccept = false;
  bool _joinedSession = false;

  final _joinCtrl = TextEditingController();

  static const _chunkSize = 16384;
  static const _highWater = 8 * 1024 * 1024;

  static const _pcConstraints = <String, dynamic>{
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 8,
  };

  static const _sessionConstraints = <String, dynamic>{
    'offerToReceiveAudio': false,
    'offerToReceiveVideo': false,
  };

  @override
  void dispose() {
    _cleanup();
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

  Future<void> _waitForIceGathering(RTCPeerConnection pc) async {
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<Map<String, dynamic>> _localSdpPayload(RTCPeerConnection pc) async {
    final desc = await pc.getLocalDescription();
    return {'sdp': desc?.sdp ?? '', 'type': desc?.type ?? 'offer'};
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
    final wsUri = AppConfig.p2pWsUri(_sessionId!, token);

    try {
      _ws = connectWsUri(wsUri);
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
      final offer = await _pc!.createOffer(_sessionConstraints);
      await _pc!.setLocalDescription(offer);
      await _waitForIceGathering(_pc!);
      _wsSend({'type': 'offer', 'sdp': await _localSdpPayload(_pc!)});
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
    final answer = await _pc!.createAnswer(_sessionConstraints);
    await _pc!.setLocalDescription(answer);
    await _waitForIceGathering(_pc!);
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
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final safeName = _rxFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    _rxSavePath = '${dir.path}${Platform.pathSeparator}$safeName';
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
      final path = _rxSavePath;
      if (path == null || !await File(path).exists()) {
        _showError('Receive failed — no file saved');
        return;
      }
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

  List<({String label, bool done, bool active})> get _connectionSteps => [
        (label: 'Signaling', done: _signalingOk, active: !_signalingOk),
        (label: 'Peer found', done: _peerFound, active: _signalingOk && !_peerFound),
        (label: 'WebRTC', done: _webrtcReady, active: _peerFound && !_webrtcReady),
        (
          label: _mode == 'transferring' ? 'Transfer' : 'Connected',
          done: _mode == 'complete',
          active: _webrtcReady && _mode != 'complete',
        ),
      ];

  Widget _statusStepsPanel() {
    return P2pStatusSteps(
      steps: _connectionSteps,
      statusText: _statusText,
      iceState: _iceState.isEmpty ? null : _iceState,
    );
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
      center: true,
      scroll: false,
      child: P2pHubCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const P2pCardHeader(
              icon: LucideIcons.arrowLeftRight,
              iconGradient: [Color(0xFF38BDF8), Color(0xFF3B82F6)],
              title: 'P2P Transfer',
              subtitle: 'Send files directly between devices — nothing stored on the server.',
            ),
            const SizedBox(height: 16),
            const P2pFeatureStrip(),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 480;
                final sendTile = P2pActionTile(
                  icon: LucideIcons.upload,
                  gradient: const [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                  label: 'Send file',
                  subtitle: 'Pick & share via QR',
                  onTap: _startSendFlow,
                );
                final recvTile = P2pActionTile(
                  icon: LucideIcons.download,
                  gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                  label: 'Receive',
                  subtitle: 'Enter transfer code',
                  onTap: () => setState(() => _mode = 'receiving'),
                );
                if (stacked) {
                  return Column(
                    children: [
                      sendTile,
                      const SizedBox(height: 10),
                      recvTile,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sendTile),
                    const SizedBox(width: 10),
                    Expanded(child: recvTile),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sendView() {
    return P2pPageFrame(
      child: P2pHubCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            P2pCardHeader(
              icon: LucideIcons.send,
              iconGradient: const [Color(0xFF3B82F6), Color(0xFF60A5FA)],
              title: 'Share your file',
              subtitle: 'Receiver can scan the QR code or enter the session code below.',
            ),
            const SizedBox(height: 16),
            P2pFilePreview(
              fileName: _selectedFileName ?? '',
              fileSize: _fmtSize(_selectedFileSize),
            ),
            if (_sessionId != null) ...[
              const SizedBox(height: 16),
              const P2pSectionLabel('Scan or share code'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.loginInsetDecoration(borderRadius: 16, emphasized: true),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.18),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: _sessionId!,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0F172A),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              P2pSessionCodeBadge(code: _sessionId!, onCopy: _copySessionCode),
            ],
            const SizedBox(height: 16),
            _statusStepsPanel(),
            if (!_peerFound && _sessionId != null) ...[
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryBright),
                ),
              ),
            ],
            const SizedBox(height: 8),
            P2pGhostButton(
              label: 'Cancel transfer',
              icon: LucideIcons.x,
              onTap: _cancel,
            ),
          ],
        ),
      ),
    );
  }

  Widget _recvView() {
    if (_joinedSession) {
      return P2pPageFrame(
        child: P2pHubCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              P2pCardHeader(
                icon: LucideIcons.inbox,
                iconGradient: const [Color(0xFF10B981), Color(0xFF059669)],
                title: _awaitingAccept ? 'Incoming file' : 'Connecting…',
                subtitle: _peerName != null
                    ? 'From $_peerName'
                    : 'Setting up a secure direct link with the sender.',
              ),
              const SizedBox(height: 16),
              _statusStepsPanel(),
              const SizedBox(height: 16),
              if (_awaitingAccept) ...[
                P2pFilePreview(
                  fileName: _rxFileName,
                  fileSize: _fmtSize(_expectedSize),
                  icon: LucideIcons.fileDown,
                  gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                ),
                const SizedBox(height: 16),
                P2pPrimaryButton(
                  label: 'Accept & receive',
                  icon: LucideIcons.check,
                  onTap: _acceptIncoming,
                  gradient: const [Color(0xFF10B981), Color(0xFF047857)],
                ),
              ] else ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 2.8, color: AppTheme.success),
                    ),
                  ),
                ),
              ],
              P2pGhostButton(
                label: 'Cancel',
                icon: LucideIcons.x,
                onTap: _cancel,
              ),
            ],
          ),
        ),
      );
    }

    return P2pPageFrame(
      child: P2pHubCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const P2pCardHeader(
              icon: LucideIcons.qrCode,
              iconGradient: [Color(0xFF10B981), Color(0xFF059669)],
              title: 'Receive a file',
              subtitle: 'Enter the transfer code shared by the sender.',
            ),
            const SizedBox(height: 16),
            P2pJoinField(
              controller: _joinCtrl,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _startReceiveFlow(v.trim());
              },
            ),
            const SizedBox(height: 14),
            P2pPrimaryButton(
              label: 'Join transfer',
              icon: LucideIcons.logIn,
              onTap: () {
                final c = _joinCtrl.text.trim();
                if (c.isNotEmpty) _startReceiveFlow(c);
              },
              gradient: const [Color(0xFF10B981), Color(0xFF047857)],
            ),
            const SizedBox(height: 6),
            P2pGhostButton(
              label: 'Back',
              icon: LucideIcons.arrowLeft,
              onTap: _cancel,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _xferView() {
    return P2pPageFrame(
      child: P2pProgressPanel(
        progress: _progress,
        fileName: _selectedFileName ?? _rxFileName,
        statusText: _statusText,
        bytesLabel: _bytesTransferred > 0 ? '${_fmtSize(_bytesTransferred)} transferred' : null,
        peerName: _peerName,
      ),
    );
  }

  Widget _doneView() {
    return P2pPageFrame(
      child: P2pHubCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 80,
                height: 80,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.success.withValues(alpha: 0.25),
                      AppTheme.success.withValues(alpha: 0.12),
                    ],
                  ),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.45)),
                ),
                child: Icon(LucideIcons.badgeCheck, color: AppTheme.success, size: 42),
              ),
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
        ),
      ),
    );
  }
}
