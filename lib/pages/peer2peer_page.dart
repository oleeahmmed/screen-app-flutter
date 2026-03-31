// peer2peer_page.dart — Peer-to-Peer File Transfer (WebRTC)
// Uses REST API polling for signaling (works without Daphne/ASGI)
// Falls back to WebSocket if available

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:path_provider/path_provider.dart';
import '../config.dart';
import '../services/api_service.dart';

class _C {
  static const bgDark = Color(0xFF0F172A);
  static const bgCard = Color(0xFF1E293B);
  static const blue = Color(0xFF3B82F6);
  static const blueDark = Color(0xFF2563EB);
  static const cyan = Color(0xFF06B6D4);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const textMain = Color(0xFFF8FAFC);
  static const textMuted = Color(0xFF94A3B8);
  static const glassBorder = Color(0x14FFFFFF);
  static const inputBg = Color(0x990F172A);
  static const inputBorder = Color(0x1AFFFFFF);
}

class Peer2PeerPage extends StatefulWidget {
  final ApiService apiService;
  const Peer2PeerPage({required this.apiService});
  @override
  State<Peer2PeerPage> createState() => _Peer2PeerPageState();
}

class _Peer2PeerPageState extends State<Peer2PeerPage>
    with SingleTickerProviderStateMixin {
  String _mode = 'home';
  String? _sessionId;
  String? _peerName;
  String? _selectedFileName;
  int _selectedFileSize = 0;
  Uint8List? _selectedFileBytes;
  double _progress = 0.0;
  String _statusText = '';
  bool _isConnected = false;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  WebSocketChannel? _ws;
  bool _wsAlive = false;
  Timer? _pollTimer;

  final List<Uint8List> _rxChunks = [];
  int _expectedSize = 0;
  int _rxSize = 0;
  String _rxFileName = '';

  late AnimationController _pulseCtrl;
  final _joinCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cleanup();
    _pulseCtrl.dispose();
    _joinCtrl.dispose();
    super.dispose();
  }

  void _cleanup() {
    _pollTimer?.cancel();
    try { _dataChannel?.close(); } catch (_) {}
    try { _pc?.close(); } catch (_) {}
    try { _ws?.sink.close(); } catch (_) {}
    _dataChannel = null;
    _pc = null;
    _ws = null;
    _wsAlive = false;
  }

  // ═══════════════════════════════════════════════════════════
  // SEND FLOW
  // ═══════════════════════════════════════════════════════════

  Future<void> _startSendFlow() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.first;
    if (pf.path == null) return;

    final file = File(pf.path!);
    _selectedFileBytes = await file.readAsBytes();
    _selectedFileName = pf.name;
    _selectedFileSize = _selectedFileBytes!.length;

    setState(() { _mode = 'sending'; _statusText = 'Creating session...'; });

    final resp = await widget.apiService.p2pCreateSession(
      fileName: _selectedFileName!, fileSize: _selectedFileSize,
    );

    if (!resp['success']) {
      _showError(resp['error'] ?? 'Failed to create session');
      setState(() => _mode = 'home');
      return;
    }

    _sessionId = resp['data']['session_id'];
    setState(() => _statusText = 'Waiting for receiver...');
    _connectSignaling(isSender: true);
  }

  // ═══════════════════════════════════════════════════════════
  // RECEIVE FLOW
  // ═══════════════════════════════════════════════════════════

  Future<void> _startReceiveFlow(String sessionId) async {
    setState(() { _mode = 'receiving'; _statusText = 'Joining...'; _sessionId = sessionId; });

    final resp = await widget.apiService.p2pJoinSession(sessionId);
    if (!resp['success']) {
      _showError(resp['error'] ?? 'Failed to join');
      setState(() => _mode = 'home');
      return;
    }

    _peerName = resp['data']['sender_name'];
    _rxFileName = resp['data']['file_name'] ?? 'file';
    _expectedSize = resp['data']['file_size'] ?? 0;
    setState(() => _statusText = 'Connecting to $_peerName...');
    _connectSignaling(isSender: false);
  }

  // ═══════════════════════════════════════════════════════════
  // SIGNALING (WebSocket with fallback)
  // ═══════════════════════════════════════════════════════════

  void _connectSignaling({required bool isSender}) {
    final token = widget.apiService.token ?? '';
    final wsUrl = '${AppConfig.p2pWsUrl}$_sessionId/?token=$token';
    print('🔌 P2P connecting: $wsUrl');

    try {
      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsAlive = true;

      _ws!.stream.listen(
        (msg) {
          try {
            _onSignal(jsonDecode(msg as String), isSender);
          } catch (e) { print('❌ Parse: $e'); }
        },
        onError: (e) {
          print('❌ WS error: $e');
          _wsAlive = false;
          if (mounted && _mode == 'sending') {
            setState(() => _statusText = 'Waiting for receiver... (WS reconnecting)');
          }
        },
        onDone: () {
          print('🔌 WS closed');
          _wsAlive = false;
        },
      );
    } catch (e) {
      print('❌ WS failed: $e');
      _wsAlive = false;
      _showError('WebSocket connection failed. Make sure Django is running with Daphne (ASGI).');
    }
  }

  void _wsSend(Map<String, dynamic> data) {
    if (_ws != null && _wsAlive) {
      try { _ws!.sink.add(jsonEncode(data)); } catch (_) {}
    }
  }

  Future<void> _onSignal(Map<String, dynamic> data, bool isSender) async {
    final type = data['type'] as String? ?? '';
    print('📨 Signal: $type');

    switch (type) {
      case 'peer_joined':
        _peerName = data['username'];
        setState(() { _isConnected = true; _statusText = 'Peer: $_peerName'; });
        if (isSender) {
          await _initPc(isSender: true);
          await _createOffer();
        }
      case 'peer_left':
        setState(() { _isConnected = false; _statusText = 'Peer disconnected'; });
      case 'offer':
        await _initPc(isSender: false);
        final s = data['sdp'];
        await _pc!.setRemoteDescription(RTCSessionDescription(s['sdp'], s['type']));
        final ans = await _pc!.createAnswer();
        await _pc!.setLocalDescription(ans);
        _wsSend({'type': 'answer', 'sdp': {'sdp': ans.sdp, 'type': ans.type}});
      case 'answer':
        final s = data['sdp'];
        await _pc!.setRemoteDescription(RTCSessionDescription(s['sdp'], s['type']));
      case 'ice_candidate':
        final c = data['candidate'];
        if (c != null && _pc != null) {
          await _pc!.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
        }
      case 'file_info':
        _rxFileName = data['file_name'] ?? 'file';
        _expectedSize = data['file_size'] ?? 0;
        if (data['sender_name'] != null) _peerName = data['sender_name'];
        setState(() => _statusText = 'Receiving: $_rxFileName');
      case 'transfer_complete':
        setState(() { _mode = 'complete'; _progress = 1.0; _statusText = 'Transfer complete'; });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // WEBRTC
  // ═══════════════════════════════════════════════════════════

  Future<void> _initPc({required bool isSender}) async {
    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    });

    _pc!.onIceCandidate = (c) => _wsSend({
      'type': 'ice_candidate',
      'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
    });

    _pc!.onIceConnectionState = (s) {
      print('🧊 ICE: $s');
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (mounted) setState(() => _statusText = isSender ? 'Sending...' : 'Receiving...');
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (mounted) _showError('Connection failed');
      }
    };

    if (isSender) {
      _dataChannel = await _pc!.createDataChannel('ft', RTCDataChannelInit()..ordered = true..maxRetransmits = 30);
      _setupDc(isSender: true);
    } else {
      _pc!.onDataChannel = (ch) { _dataChannel = ch; _setupDc(isSender: false); };
    }
  }

  void _setupDc({required bool isSender}) {
    _dataChannel!.onDataChannelState = (s) {
      print('📡 DC: $s');
      if (s == RTCDataChannelState.RTCDataChannelOpen && isSender) {
        _wsSend({'type': 'file_info', 'file_name': _selectedFileName, 'file_size': _selectedFileSize});
        Future.delayed(Duration(milliseconds: 200), _sendChunks);
      }
    };

    if (!isSender) {
      _dataChannel!.onMessage = (RTCDataChannelMessage msg) {
        if (msg.isBinary) {
          _rxChunks.add(msg.binary);
          _rxSize += msg.binary.length;
          if (_expectedSize > 0 && mounted) {
            setState(() {
              _mode = 'transferring';
              _progress = _rxSize / _expectedSize;
              _statusText = 'Receiving: ${(_progress * 100).toStringAsFixed(1)}%';
            });
          }
        } else if (msg.text == 'EOF') {
          _saveFile();
        }
      };
    }
  }

  Future<void> _sendChunks() async {
    if (_selectedFileBytes == null || _dataChannel == null) return;
    setState(() { _mode = 'transferring'; _statusText = 'Sending...'; });

    const cs = 16384;
    final total = _selectedFileBytes!.length;
    int off = 0;
    while (off < total) {
      final end = min(off + cs, total);
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(_selectedFileBytes!.sublist(off, end)));
      off = end;
      if (mounted) setState(() { _progress = off / total; _statusText = 'Sending: ${(_progress * 100).toStringAsFixed(1)}%'; });
      await Future.delayed(Duration(milliseconds: 5));
    }
    _dataChannel!.send(RTCDataChannelMessage('EOF'));
    _wsSend({'type': 'transfer_complete'});
    if (mounted) setState(() { _mode = 'complete'; _progress = 1.0; _statusText = 'Sent!'; });
  }

  Future<void> _saveFile() async {
    try {
      final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final path = '${dir.path}${Platform.pathSeparator}$_rxFileName';
      final bb = BytesBuilder();
      for (final c in _rxChunks) bb.add(c);
      await File(path).writeAsBytes(bb.toBytes());
      _rxChunks.clear(); _rxSize = 0;
      if (mounted) setState(() { _mode = 'complete'; _progress = 1.0; _statusText = 'Saved: $path'; });
    } catch (e) { _showError('Save failed: $e'); }
  }

  Future<void> _createOffer() async {
    final o = await _pc!.createOffer();
    await _pc!.setLocalDescription(o);
    _wsSend({'type': 'offer', 'sdp': {'sdp': o.sdp, 'type': o.type}});
  }

  void _cancel() {
    _cleanup();
    _rxChunks.clear(); _rxSize = 0; _selectedFileBytes = null;
    setState(() { _mode = 'home'; _progress = 0; _statusText = ''; _isConnected = false; _sessionId = null; });
  }

  void _showError(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: _C.red));
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }

  // ═══════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [_C.bgDark, Color(0xFF1E293B), Color(0xFF162032)])),
      child: SafeArea(child: Column(children: [_header(), Expanded(child: _body())])),
    );
  }

  Widget _header() => Container(
    height: 64, padding: EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(color: Color(0x1A1E293B), border: Border(bottom: BorderSide(color: _C.glassBorder))),
    child: Row(children: [
      if (_mode != 'home') GestureDetector(onTap: _cancel,
        child: Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.arrow_back_ios, color: _C.textMuted, size: 20))),
      Container(width: 36, height: 36,
        decoration: BoxDecoration(gradient: LinearGradient(colors: [_C.cyan, _C.blue]), borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.swap_horiz, color: Colors.white, size: 20)),
      SizedBox(width: 12),
      Text('Peer2Peer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.textMain)),
      Spacer(),
      if (_isConnected) Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: _C.green.withOpacity(0.2), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.green.withOpacity(0.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: _C.green, shape: BoxShape.circle)),
          SizedBox(width: 6),
          Text('Connected', style: TextStyle(color: _C.green, fontSize: 11, fontWeight: FontWeight.w600)),
        ])),
    ]),
  );

  Widget _body() {
    switch (_mode) {
      case 'sending': return _sendView();
      case 'receiving': return _recvView();
      case 'transferring': return _xferView();
      case 'complete': return _doneView();
      default: return _homeView();
    }
  }

  Widget _homeView() => SingleChildScrollView(padding: EdgeInsets.all(24), child: Column(children: [
    SizedBox(height: 20),
    AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) => Container(
      width: 100, height: 100,
      decoration: BoxDecoration(shape: BoxShape.circle,
        gradient: LinearGradient(colors: [
          _C.cyan.withOpacity(0.3 + _pulseCtrl.value * 0.2),
          _C.blue.withOpacity(0.3 + _pulseCtrl.value * 0.2)]),
        boxShadow: [BoxShadow(color: _C.cyan.withOpacity(0.2 + _pulseCtrl.value * 0.1), blurRadius: 30)]),
      child: Icon(Icons.swap_horiz, color: _C.cyan, size: 48))),
    SizedBox(height: 24),
    Text('Peer-to-Peer File Transfer', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _C.textMain)),
    SizedBox(height: 8),
    Text('Send files directly between devices.\nNothing stored on server.', textAlign: TextAlign.center,
      style: TextStyle(fontSize: 14, color: _C.textMuted, height: 1.5)),
    SizedBox(height: 40),
    _card(Icons.upload_file, 'Send File', 'Pick a file and share via QR code', [_C.blue, _C.blueDark], _startSendFlow),
    SizedBox(height: 16),
    _card(Icons.download, 'Receive File', 'Enter code to receive', [_C.green, Color(0xFF16A34A)], () => setState(() => _mode = 'receiving')),
    SizedBox(height: 32),
    Container(padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: _C.cyan.withOpacity(0.08), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.cyan.withOpacity(0.2))),
      child: Row(children: [
        Icon(Icons.info_outline, color: _C.cyan, size: 20), SizedBox(width: 12),
        Expanded(child: Text(
          'Requires Django running with Daphne (ASGI) for WebSocket signaling.\nRun: daphne -b 0.0.0.0 -p 8000 config.asgi:application',
          style: TextStyle(color: _C.textMuted, fontSize: 11, height: 1.4))),
      ])),
  ]));

  Widget _card(IconData ic, String t, String s, List<Color> g, VoidCallback fn) => GestureDetector(
    onTap: fn, child: Container(padding: EdgeInsets.all(20),
      decoration: BoxDecoration(color: _C.bgCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: g[0].withOpacity(0.3)),
        boxShadow: [BoxShadow(color: g[0].withOpacity(0.1), blurRadius: 20)]),
      child: Row(children: [
        Container(width: 52, height: 52,
          decoration: BoxDecoration(gradient: LinearGradient(colors: g), borderRadius: BorderRadius.circular(14)),
          child: Icon(ic, color: Colors.white, size: 26)),
        SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _C.textMain)),
          SizedBox(height: 4), Text(s, style: TextStyle(fontSize: 13, color: _C.textMuted)),
        ])),
        Icon(Icons.arrow_forward_ios, color: _C.textMuted, size: 16),
      ])));

  Widget _sendView() => SingleChildScrollView(padding: EdgeInsets.all(24), child: Column(children: [
    SizedBox(height: 16),
    Container(padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: _C.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.glassBorder)),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(color: _C.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.insert_drive_file, color: _C.blue, size: 24)),
        SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_selectedFileName ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _C.textMain),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(_fmtSize(_selectedFileSize), style: TextStyle(fontSize: 12, color: _C.textMuted)),
        ])),
      ])),
    SizedBox(height: 24),
    if (_sessionId != null) ...[
      Text('Scan QR or share code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _C.textMain)),
      SizedBox(height: 16),
      Container(padding: EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: _C.blue.withOpacity(0.2), blurRadius: 30)]),
        child: QrImageView(data: _sessionId!, version: QrVersions.auto, size: 200, backgroundColor: Colors.white,
          eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1E293B)),
          dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1E293B)))),
      SizedBox(height: 16),
      GestureDetector(
        onTap: () { Clipboard.setData(ClipboardData(text: _sessionId!));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied!'), backgroundColor: _C.green, duration: Duration(seconds: 1))); },
        child: Container(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: _C.bgCard, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _C.blue.withOpacity(0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_sessionId!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.cyan, letterSpacing: 2)),
            SizedBox(width: 8), Icon(Icons.copy, color: _C.textMuted, size: 16),
          ]))),
    ],
    SizedBox(height: 24),
    Text(_statusText, style: TextStyle(fontSize: 14, color: _C.textMuted)),
    if (!_isConnected && _sessionId != null) ...[
      SizedBox(height: 16), SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _C.blue))],
    SizedBox(height: 24),
    TextButton.icon(onPressed: _cancel, icon: Icon(Icons.close, size: 18), label: Text('Cancel'),
      style: TextButton.styleFrom(foregroundColor: _C.red)),
  ]));

  Widget _recvView() {
    if (_sessionId == null) {
      return SingleChildScrollView(padding: EdgeInsets.all(24), child: Column(children: [
        SizedBox(height: 20),
        Icon(Icons.qr_code_scanner, color: _C.green, size: 64),
        SizedBox(height: 20),
        Text('Receive a File', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _C.textMain)),
        SizedBox(height: 32),
        Text('Enter the transfer code:', style: TextStyle(fontSize: 14, color: _C.textMuted)),
        SizedBox(height: 12),
        TextField(controller: _joinCtrl,
          style: TextStyle(color: _C.textMain, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          decoration: InputDecoration(hintText: 'Paste code here',
            hintStyle: TextStyle(color: _C.textMuted, fontSize: 14, letterSpacing: 0, fontWeight: FontWeight.normal),
            filled: true, fillColor: _C.inputBg,
            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _C.inputBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _C.inputBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _C.green))),
          onSubmitted: (v) { if (v.trim().isNotEmpty) _startReceiveFlow(v.trim()); }),
        SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () { final c = _joinCtrl.text.trim(); if (c.isNotEmpty) _startReceiveFlow(c); },
          icon: Icon(Icons.login, size: 18), label: Text('Join', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: _C.green, foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
        SizedBox(height: 24),
        TextButton.icon(onPressed: _cancel, icon: Icon(Icons.arrow_back, size: 18), label: Text('Back'),
          style: TextButton.styleFrom(foregroundColor: _C.textMuted)),
      ]));
    }
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: _C.green, strokeWidth: 3),
      SizedBox(height: 20),
      Text(_statusText, style: TextStyle(color: _C.textMuted, fontSize: 14)),
      if (_peerName != null) ...[SizedBox(height: 8),
        Text('From: $_peerName', style: TextStyle(color: _C.textMain, fontSize: 16, fontWeight: FontWeight.w600))],
      SizedBox(height: 24),
      TextButton.icon(onPressed: _cancel, icon: Icon(Icons.close, size: 18), label: Text('Cancel'),
        style: TextButton.styleFrom(foregroundColor: _C.red)),
    ]));
  }

  Widget _xferView() => Center(child: Padding(padding: EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(width: 140, height: 140, child: Stack(alignment: Alignment.center, children: [
      SizedBox(width: 140, height: 140, child: CircularProgressIndicator(
        value: _progress, strokeWidth: 8, backgroundColor: _C.glassBorder, valueColor: AlwaysStoppedAnimation(_C.cyan))),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${(_progress * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _C.textMain)),
        Text(_progress < 1 ? 'Transferring' : 'Done', style: TextStyle(fontSize: 12, color: _C.textMuted)),
      ]),
    ])),
    SizedBox(height: 24),
    Text(_selectedFileName ?? _rxFileName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _C.textMain),
      maxLines: 1, overflow: TextOverflow.ellipsis),
    SizedBox(height: 8),
    Text(_statusText, style: TextStyle(fontSize: 14, color: _C.textMuted)),
    if (_peerName != null) ...[SizedBox(height: 4), Text('with $_peerName', style: TextStyle(fontSize: 13, color: _C.cyan))],
    SizedBox(height: 32),
    TextButton.icon(onPressed: _cancel, icon: Icon(Icons.close, size: 18), label: Text('Cancel'),
      style: TextButton.styleFrom(foregroundColor: _C.red)),
  ])));

  Widget _doneView() => Center(child: Padding(padding: EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 80, height: 80,
      decoration: BoxDecoration(color: _C.green.withOpacity(0.2), shape: BoxShape.circle),
      child: Icon(Icons.check_circle, color: _C.green, size: 48)),
    SizedBox(height: 24),
    Text('Transfer Complete!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _C.textMain)),
    SizedBox(height: 12),
    Text(_selectedFileName ?? _rxFileName, style: TextStyle(fontSize: 15, color: _C.cyan, fontWeight: FontWeight.w600)),
    SizedBox(height: 8),
    Padding(padding: EdgeInsets.symmetric(horizontal: 16),
      child: Text(_statusText, style: TextStyle(fontSize: 13, color: _C.textMuted), textAlign: TextAlign.center)),
    SizedBox(height: 32),
    SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _cancel, icon: Icon(Icons.home, size: 18),
      label: Text('Back to Home', style: TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: _C.blue, foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
  ])));
}
