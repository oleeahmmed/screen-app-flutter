import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../utils/local_file_actions.dart';
import '../utils/ws_connect.dart';
import 'api_service.dart';
import 'chat_p2p_tokens.dart';
import 'local_notification_service.dart';
import 'notification_service.dart';
import 'p2p_received_store.dart';

enum ChatP2pPhase { idle, outgoing, incoming, connecting, transferring, complete, failed }

class ChatP2pTransferState {
  final ChatP2pPhase phase;
  final String sessionId;
  final int peerId;
  final String peerName;
  final String fileName;
  final int fileSize;
  final bool isSender;
  final double progress;
  final int bytesTransferred;
  final String statusText;
  final String? savedPath;
  final String? error;

  const ChatP2pTransferState({
    this.phase = ChatP2pPhase.idle,
    this.sessionId = '',
    this.peerId = 0,
    this.peerName = '',
    this.fileName = '',
    this.fileSize = 0,
    this.isSender = false,
    this.progress = 0,
    this.bytesTransferred = 0,
    this.statusText = '',
    this.savedPath,
    this.error,
  });

  bool get isActive =>
      phase != ChatP2pPhase.idle && phase != ChatP2pPhase.complete && phase != ChatP2pPhase.failed;

  ChatP2pTransferState copyWith({
    ChatP2pPhase? phase,
    String? sessionId,
    int? peerId,
    String? peerName,
    String? fileName,
    int? fileSize,
    bool? isSender,
    double? progress,
    int? bytesTransferred,
    String? statusText,
    String? savedPath,
    String? error,
  }) {
    return ChatP2pTransferState(
      phase: phase ?? this.phase,
      sessionId: sessionId ?? this.sessionId,
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      isSender: isSender ?? this.isSender,
      progress: progress ?? this.progress,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      statusText: statusText ?? this.statusText,
      savedPath: savedPath ?? this.savedPath,
      error: error,
    );
  }
}

/// In-chat P2P file transfer — server stores only session metadata, bytes go over WebRTC.
class ChatP2pFileService {
  ChatP2pFileService._();
  static final ChatP2pFileService instance = ChatP2pFileService._();

  static const _chunkSize = 16384;
  static const _highWater = 8 * 1024 * 1024;
  static const _desktopPlatforms = {'windows', 'linux', 'macos'};
  static const _pcConstraints = <String, dynamic>{
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 8,
  };

  ApiService? _api;
  NotificationService? _notif;
  int? _myUserId;

  ChatP2pTransferState _state = const ChatP2pTransferState();
  final _stateController = StreamController<ChatP2pTransferState>.broadcast();
  Stream<ChatP2pTransferState> get stateStream => _stateController.stream;
  ChatP2pTransferState get state => _state;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  WebSocketChannel? _ws;
  bool _wsAlive = false;
  String? _myRole;
  bool _remoteReady = false;
  bool _webrtcStarted = false;
  bool _webrtcReady = false;
  bool _peerFound = false;
  bool _transferSucceeded = false;
  bool _saveInProgress = false;
  String? _peerPlatform;
  String? _filePath;
  final List<Map<String, dynamic>> _pendingIce = [];
  final Set<String> _seenSessionIds = {};
  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];

  RandomAccessFile? _rxFile;
  String? _rxSavePath;
  int _rxWritten = 0;
  Future<void> _rxWriteChain = Future.value();
  Timer? _connectTimeout;
  Timer? _offerFallbackTimer;
  StreamSubscription<Map<String, dynamic>>? _chatSub;

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get _isSender => _state.isSender;

  bool get _shouldBeInitiator {
    final peer = (_peerPlatform ?? '').toLowerCase();
    final peerDesktop = _desktopPlatforms.contains(peer);
    if (_isDesktop != peerDesktop) return _isDesktop;
    return _isSender;
  }

  void bind({
    required ApiService apiService,
    required NotificationService notificationService,
    required int myUserId,
  }) {
    _api = apiService;
    _notif = notificationService;
    _myUserId = myUserId;
    _chatSub?.cancel();
    _chatSub = notificationService.chatMessageStream.listen((data) {
      unawaited(_onChatEvent(data));
    });
    unawaited(_loadIceServers());
  }

  void unbind() {
    _chatSub?.cancel();
    _chatSub = null;
  }

  void _emit(ChatP2pTransferState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  Future<void> _loadIceServers() async {
    final api = _api;
    if (api == null) return;
    final r = await api.p2pGetIceServers();
    if (r['success'] == true) {
      final data = r['data'];
      if (data is Map && data['ice_servers'] is List) {
        final servers = (data['ice_servers'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (servers.isNotEmpty) _iceServers = servers;
      }
    }
  }

  Future<String?> sendFile({
    required int peerId,
    required String peerName,
    required String filePath,
    required String fileName,
    required int fileSize,
  }) async {
    if (_state.isActive) return 'Another transfer is in progress';
    final api = _api;
    final myId = _myUserId;
    if (api == null || myId == null) return 'Not signed in';

    _filePath = filePath;
    _transferSucceeded = false;
    _saveInProgress = false;
    _emit(ChatP2pTransferState(
      phase: ChatP2pPhase.outgoing,
      peerId: peerId,
      peerName: peerName,
      fileName: fileName,
      fileSize: fileSize,
      isSender: true,
      statusText: 'Creating secure session…',
    ));

    final createR = await api.p2pCreateSession(
      receiverId: peerId,
      fileName: fileName,
      fileSize: fileSize,
    );
    if (createR['success'] != true) {
      _fail(createR['error']?.toString() ?? 'Could not start transfer');
      return _state.error;
    }

    final sessionId = createR['data']?['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      _fail('Could not start transfer');
      return _state.error;
    }

    _seenSessionIds.add(sessionId);
    _emit(_state.copyWith(sessionId: sessionId, statusText: 'Notifying peer…'));

    final invite = ChatP2pTokens.buildInvite(
      sessionId: sessionId,
      fileName: fileName,
      fileSize: fileSize,
      senderId: myId,
    );
    await _notif?.waitForConnection(timeout: const Duration(seconds: 6));
    final sendR = await api.sendMessage(peerId, invite);
    if (sendR['success'] != true) {
      await api.p2pCancelSession(sessionId);
      _fail(sendR['error']?.toString() ?? 'Could not reach peer');
      return _state.error;
    }

    _notif?.sendChatPayload({
      'type': 'p2p_file_invite',
      'session_id': sessionId,
      'receiver_id': peerId,
      'file_name': fileName,
      'file_size': fileSize,
    });

    _emit(_state.copyWith(statusText: 'Waiting for peer to accept…'));
    await _connectSignaling(sessionId);
    return null;
  }

  Future<void> _onChatEvent(Map<String, dynamic> data) async {
    if (_state.isActive) return;

    final wsType = data['type']?.toString();
    if (wsType == 'p2p_file_invite') {
      final sessionId = data['session_id']?.toString() ?? '';
      final senderId = data['sender_id'] is int
          ? data['sender_id'] as int
          : int.tryParse('${data['sender_id']}');
      if (sessionId.isEmpty || senderId == null || senderId == _myUserId) return;
      if (_seenSessionIds.contains(sessionId)) return;
      _seenSessionIds.add(sessionId);
      _emit(ChatP2pTransferState(
        phase: ChatP2pPhase.incoming,
        sessionId: sessionId,
        peerId: senderId,
        peerName: data['sender_name']?.toString() ?? 'Contact',
        fileName: data['file_name']?.toString() ?? 'file',
        fileSize: data['file_size'] is int
            ? data['file_size'] as int
            : int.tryParse('${data['file_size']}') ?? 0,
        isSender: false,
        statusText: 'Tap Receive to download directly',
      ));
      _notifyIncomingFile();
      return;
    }

    final text = data['message']?.toString() ?? '';
    final invite = ChatP2pTokens.parseInvite(text);
    if (invite == null) return;

    final senderId = invite['sender_id'] as int?;
    if (senderId == null || senderId == _myUserId) return;

    final sessionId = invite['session_id']?.toString() ?? '';
    if (sessionId.isEmpty || _seenSessionIds.contains(sessionId)) return;
    _seenSessionIds.add(sessionId);

    final senderName = data['sender_name']?.toString() ??
        data['sender_username']?.toString() ??
        'Contact';

    _emit(ChatP2pTransferState(
      phase: ChatP2pPhase.incoming,
      sessionId: sessionId,
      peerId: senderId,
      peerName: senderName,
      fileName: invite['file_name']?.toString() ?? 'file',
      fileSize: invite['file_size'] is int
          ? invite['file_size'] as int
          : int.tryParse('${invite['file_size']}') ?? 0,
      isSender: false,
      statusText: 'Tap Receive to download directly',
    ));
    _notifyIncomingFile();
  }

  void _notifyIncomingFile() {
    if (kIsWeb) return;
    final s = _state;
    if (s.phase != ChatP2pPhase.incoming) return;
    unawaited(LocalNotificationService.show(
      id: 92000 + (s.peerId % 1000),
      title: 'File from ${s.peerName}',
      body: 'Accept “${s.fileName}” to receive via P2P',
      payload: 'p2p_file:${s.sessionId}:${s.peerId}',
    ));
  }

  Future<String?> acceptIncoming() async {
    if (_state.phase != ChatP2pPhase.incoming) return 'No incoming transfer';
    final api = _api;
    final sessionId = _state.sessionId;
    if (api == null || sessionId.isEmpty) return 'Transfer unavailable';

    _emit(_state.copyWith(phase: ChatP2pPhase.connecting, statusText: 'Joining session…'));

    final joinR = await api.p2pJoinSession(sessionId);
    if (joinR['success'] != true) {
      _fail(joinR['error']?.toString() ?? 'Could not join');
      return _state.error;
    }

    final data = joinR['data'] as Map? ?? {};
    final fileName = data['file_name']?.toString() ?? _state.fileName;
    final fileSize = data['file_size'] is int
        ? data['file_size'] as int
        : int.tryParse('${data['file_size']}') ?? _state.fileSize;

    _emit(_state.copyWith(
      fileName: fileName,
      fileSize: fileSize,
      statusText: 'Connecting securely…',
    ));

    await api.sendMessage(
      _state.peerId,
      '${ChatP2pTokens.acceptPrefix}$sessionId',
    );

    await _connectSignaling(sessionId);
    return null;
  }

  Future<void> rejectIncoming() async {
    final sessionId = _state.sessionId;
    if (sessionId.isNotEmpty) {
      await _api?.sendMessage(
        _state.peerId,
        '${ChatP2pTokens.rejectPrefix}$sessionId',
      );
      await _api?.p2pCancelSession(sessionId);
    }
    await _cleanup();
    _emit(const ChatP2pTransferState());
  }

  Future<void> cancel() async {
    final sessionId = _state.sessionId;
    if (sessionId.isNotEmpty) {
      await _api?.p2pCancelSession(sessionId);
    }
    await _cleanup();
    _emit(const ChatP2pTransferState());
  }

  void _fail(String message) {
    _emit(_state.copyWith(phase: ChatP2pPhase.failed, error: message, statusText: message));
    unawaited(_cleanup());
  }

  Future<void> _connectSignaling(String sessionId) async {
    _connectTimeout?.cancel();
    final token = _api?.token ?? '';
    if (token.isEmpty) {
      _fail('Not signed in');
      return;
    }

    try {
      try {
        await _ws?.sink.close();
      } catch (_) {}
      _ws = connectWsUri(AppConfig.p2pWsUri(sessionId, token));
      _wsAlive = true;
      _webrtcStarted = false;
      _peerPlatform = null;
      _peerFound = false;

      _connectTimeout = Timer(const Duration(seconds: 90), () {
        if (!_webrtcReady && _state.phase != ChatP2pPhase.transferring && _state.phase != ChatP2pPhase.complete) {
          _fail('Connection timed out — both users must be online');
        }
      });

      _ws!.stream.listen(
        (msg) {
          try {
            unawaited(_onSignal(jsonDecode(msg as String) as Map<String, dynamic>));
          } catch (e) {
            if (kDebugMode) debugPrint('[ChatP2P] parse: $e');
          }
        },
        onError: (_) => _wsAlive = false,
        onDone: () => _wsAlive = false,
      );
    } catch (e) {
      _fail('Signaling failed: $e');
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
    final type = data['type']?.toString() ?? '';
    switch (type) {
      case 'connected':
        _wsSend({'type': 'hello', 'platform': Platform.operatingSystem.toLowerCase()});
        break;
      case 'peer_joined':
        _peerFound = true;
        _emit(_state.copyWith(statusText: 'Peer connected — securing link…'));
        _wsSend({'type': 'hello', 'platform': Platform.operatingSystem.toLowerCase()});
        _offerFallbackTimer?.cancel();
        _offerFallbackTimer = Timer(const Duration(milliseconds: 1800), () {
          if (!_webrtcStarted) unawaited(_maybeStartWebRtc());
        });
        break;
      case 'hello':
        _peerPlatform = data['platform']?.toString();
        _peerFound = true;
        await _maybeStartWebRtc();
        break;
      case 'role':
        await _maybeStartWebRtc();
        break;
      case 'offer':
        await _onOffer(data['sdp'] as Map<String, dynamic>?);
        break;
      case 'answer':
        await _onAnswer(data['sdp'] as Map<String, dynamic>?);
        break;
      case 'ice_candidate':
        await _onRemoteIce(data['candidate'] as Map<String, dynamic>?);
        break;
      case 'room_full':
        _fail('Transfer room is full');
        break;
    }
  }

  Future<void> _maybeStartWebRtc() async {
    if (_webrtcStarted || _pc != null) return;
    if (!_peerFound && _peerPlatform == null) return;
    final initiator = _peerPlatform != null ? _shouldBeInitiator : _isSender;
    await _startAsRole(initiator ? 'initiator' : 'responder');
  }

  Future<void> _startAsRole(String role) async {
    if (_webrtcStarted) return;
    _webrtcStarted = true;
    _myRole = role;
    _emit(_state.copyWith(
      phase: ChatP2pPhase.connecting,
      statusText: _isSender ? 'Preparing to send…' : 'Preparing to receive…',
    ));
    await _initPc();
    if (role == 'initiator') {
      _dataChannel = await _pc!.createDataChannel('file', RTCDataChannelInit()..ordered = true);
      _setupDc(isSender: _isSender);
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _wsSend({'type': 'offer', 'sdp': await _localSdpPayload(_pc!)});
    } else {
      _ensureDataChannelHandler(isSender: _isSender);
    }
  }

  void _ensureDataChannelHandler({required bool isSender}) {
    _pc?.onDataChannel = (ch) {
      _dataChannel = ch;
      _setupDc(isSender: isSender);
    };
  }

  Future<void> _onOffer(Map<String, dynamic>? sdp) async {
    if (sdp == null) return;
    if (_myRole == 'initiator' && _pc != null) return;
    _myRole = 'responder';
    _webrtcStarted = true;
    if (_pc == null) await _initPc();
    _ensureDataChannelHandler(isSender: _isSender);
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()));
    _remoteReady = true;
    await _flushCandidates();
    final answer = await _pc!.createAnswer(_pcConstraints);
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
      } catch (_) {}
    } else {
      _pendingIce.add(candidate);
    }
  }

  Future<void> _flushCandidates() async {
    if (_pc == null) return;
    for (final c in List<Map<String, dynamic>>.from(_pendingIce)) {
      try {
        await _pc!.addCandidate(_makeIceCandidate(c));
      } catch (_) {}
    }
    _pendingIce.clear();
  }

  Future<void> _initPc() async {
    if (_pc != null) return;
    _pc = await createPeerConnection({'iceServers': _iceServers, ..._pcConstraints});
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
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _connectTimeout?.cancel();
        _webrtcReady = true;
        if (_isSender) {
          _emit(_state.copyWith(statusText: 'Connected — starting send…'));
        } else {
          _emit(_state.copyWith(statusText: 'Connected — ready to receive…'));
        }
      }
    };
  }

  void _setupDc({required bool isSender}) {
    _dataChannel?.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen && isSender) {
        _sendMeta();
      }
    };

    _dataChannel?.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary) {
        final chunk = Uint8List.fromList(msg.binary);
        _rxWriteChain = _rxWriteChain.then((_) async {
          final raf = _rxFile;
          if (raf == null) return;
          await raf.writeFrom(chunk);
          _rxWritten += chunk.length;
          final total = _state.fileSize > 0 ? _state.fileSize : _rxWritten;
          _emit(_state.copyWith(
            phase: ChatP2pPhase.transferring,
            bytesTransferred: _rxWritten,
            progress: total > 0 ? _rxWritten / total : 0,
            statusText: 'Receiving… ${((_rxWritten / total) * 100).toStringAsFixed(0)}%',
          ));
        });
        return;
      }

      try {
        final ctrl = jsonDecode(msg.text) as Map<String, dynamic>;
        final kind = ctrl['kind']?.toString();
        if (kind == 'meta' && !isSender) {
          unawaited(_openReceiveFile(ctrl['name']?.toString() ?? _state.fileName));
          _dataChannel?.send(RTCDataChannelMessage(jsonEncode({'kind': 'ready'})));
          _emit(_state.copyWith(phase: ChatP2pPhase.transferring, statusText: 'Receiving…'));
        } else if (kind == 'ready' && isSender) {
          unawaited(_sendChunks());
        } else if (kind == 'done' && !isSender) {
          unawaited(_saveFile());
        }
      } catch (_) {}
    };
  }

  void _sendMeta() {
    _wsSend({
      'type': 'file_info',
      'file_name': _state.fileName,
      'file_size': _state.fileSize,
    });
    _dataChannel?.send(RTCDataChannelMessage(jsonEncode({
      'kind': 'meta',
      'name': _state.fileName,
      'size': _state.fileSize,
      'type': 'application/octet-stream',
    })));
    _emit(_state.copyWith(statusText: 'Sending metadata…'));
  }

  Future<void> _openReceiveFile(String name) async {
    final dir = await LocalFileActions.receiveTempDirectory();
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    _rxSavePath = '${dir.path}${Platform.pathSeparator}$safeName';
    final file = File(_rxSavePath!);
    if (await file.exists()) await file.delete();
    _rxWriteChain = Future.value();
    _rxFile = await file.open(mode: FileMode.write);
    _rxWritten = 0;
  }

  Future<void> _sendChunks() async {
    final path = _filePath;
    if (path == null || _dataChannel == null) return;
    _emit(_state.copyWith(phase: ChatP2pPhase.transferring, statusText: 'Sending…'));

    final file = File(path);
    final total = _state.fileSize > 0 ? _state.fileSize : await file.length();
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
        _emit(_state.copyWith(
          bytesTransferred: off,
          progress: off / total,
          statusText: 'Sending… ${((off / total) * 100).toStringAsFixed(0)}%',
        ));
        await Future.delayed(const Duration(milliseconds: 1));
      }
    } finally {
      await raf.close();
    }

    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({'kind': 'done'})));
    _wsSend({'type': 'transfer_complete'});
    _transferSucceeded = true;
    _emit(_state.copyWith(
      phase: ChatP2pPhase.complete,
      progress: 1,
      statusText: 'Sent successfully — not stored on server',
    ));
    unawaited(_cleanup(keepState: true));
  }

  Future<void> _saveFile() async {
    if (_saveInProgress || _transferSucceeded) return;
    _saveInProgress = true;
    try {
      await _rxWriteChain.catchError((_) {});
      final raf = _rxFile;
      _rxFile = null;
      if (raf != null) {
        await raf.flush();
        await raf.close();
      }
      final path = _rxSavePath;
      if (path == null || !await File(path).exists()) {
        _fail('Receive failed');
        return;
      }
      final displayName = _state.fileName.isNotEmpty
          ? _state.fileName
          : path.split(Platform.pathSeparator).last;
      await P2pReceivedStore.add(name: displayName, path: path, size: _rxWritten);
      _transferSucceeded = true;
      _emit(_state.copyWith(
        phase: ChatP2pPhase.complete,
        progress: 1,
        savedPath: path,
        statusText: 'Received — saved on your device only',
      ));
      unawaited(_cleanup(keepState: true));
    } catch (e) {
      _fail('Save failed: $e');
    }
  }

  Future<Map<String, dynamic>> _localSdpPayload(RTCPeerConnection pc) async {
    final desc = await pc.getLocalDescription();
    return {'sdp': desc?.sdp ?? '', 'type': desc?.type ?? 'offer'};
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

  Future<void> _cleanup({bool keepState = false}) async {
    _connectTimeout?.cancel();
    _offerFallbackTimer?.cancel();
    try {
      await _dataChannel?.close();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      await _ws?.sink.close();
    } catch (_) {}
    final raf = _rxFile;
    _rxFile = null;
    if (raf != null) {
      unawaited(_rxWriteChain.then((_) => raf.close()).catchError((_) {}));
    }
    _dataChannel = null;
    _pc = null;
    _ws = null;
    _wsAlive = false;
    _webrtcStarted = false;
    _webrtcReady = false;
    _peerFound = false;
    _filePath = null;
    _pendingIce.clear();
    if (!keepState) _emit(const ChatP2pTransferState());
  }
}
