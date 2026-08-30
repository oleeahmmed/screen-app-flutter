import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/user_data_service.dart';
import '../services/voice_recorder_service.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/empty_state.dart';
import '../utils/responsive.dart';
import '../utils/platform_capabilities.dart';

class ChatPage extends StatefulWidget {
  final ApiService apiService;
  final NotificationService? notificationService;

  const ChatPage({
    super.key,
    required this.apiService,
    this.notificationService,
  });
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  // State
  String _currentTab = 'direct'; // 'direct' or 'group'
  List<dynamic> _users = [];
  List<dynamic> _groups = [];
  dynamic _selectedUser;
  dynamic _selectedGroup;
  List<dynamic> _messages = [];
  bool _isLoadingUsers = true;
  bool _isLoadingGroups = false;
  bool _isSending = false;
  String _searchQuery = '';
  Timer? _refreshTimer;
  Timer? _usersPollTimer;
  Timer? _typingDebounce;
  Timer? _typingIdle;
  StreamSubscription<Map<String, dynamic>>? _presenceSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<Map<String, dynamic>>? _messagesReadSub;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  Process? _recProcess;
  String? _recPath;
  VoiceRecorderService? _voiceRecorder;
  AudioPlayer? _audioPlayer;
  String? _playingUrl;
  int? _myUserId;
  bool _iAmTyping = false;
  Map<String, dynamic>? _replyTo;
  /// peerUserId / groupId → display name while typing
  final Map<String, String> _typingPeers = {};
  final _imagePicker = ImagePicker();

  bool get _supportsNativeAudio => PlatformCapabilities.nativeAudio;

  VoiceRecorderService get _recorder => _voiceRecorder ??= VoiceRecorderService();

  AudioPlayer? get _player {
    if (!_supportsNativeAudio) return null;
    return _audioPlayer ??= AudioPlayer();
  }

  final _msgController = TextEditingController();
  final _msgFocus = FocusNode();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _msgFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _msgController.addListener(_onComposerChanged);
    _loadUsers();
    _loadMyUserId();
    _usersPollTimer = Timer.periodic(const Duration(seconds: 25), (_) => _loadUsers(silent: true));
    _presenceSub = widget.notificationService?.presenceStream.listen(_onPresenceUpdate);
    _typingSub = widget.notificationService?.typingStream.listen(_onTypingEvent);
    _messagesReadSub = widget.notificationService?.messagesReadStream.listen(_onMessagesRead);
  }

  Future<void> _loadMyUserId() async {
    final id = int.tryParse(await UserDataService.getUserId());
    if (mounted) setState(() => _myUserId = id);
  }

  @override
  void dispose() {
    _stopTypingSignal();
    _refreshTimer?.cancel();
    _usersPollTimer?.cancel();
    _typingDebounce?.cancel();
    _typingIdle?.cancel();
    _presenceSub?.cancel();
    _typingSub?.cancel();
    _messagesReadSub?.cancel();
    _recordTimer?.cancel();
    _recProcess?.kill();
    _voiceRecorder?.dispose();
    _audioPlayer?.dispose();
    _msgController.removeListener(_onComposerChanged);
    _msgController.dispose();
    _msgFocus.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Data Loading ───
  Future<void> _loadUsers({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoadingUsers = true);
    final result = await widget.apiService.getChatUsers();
    if (result['success'] && mounted) {
      setState(() {
        _users = _sortUsersByRecent(result['data'] ?? []);
        _isLoadingUsers = false;
        if (_selectedUser != null) {
          final id = _selectedUser['id'];
          for (final u in _users) {
            if (u['id'] == id) {
              _selectedUser = u;
              break;
            }
          }
        }
      });
    } else if (mounted) {
      setState(() => _isLoadingUsers = false);
      if (!silent) _showError('Failed to load users');
    }
  }

  List<dynamic> _sortUsersByRecent(List<dynamic> users) {
    final list = List<dynamic>.from(users);
    list.sort((a, b) {
      final at = DateTime.tryParse('${a['last_message_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = DateTime.tryParse('${b['last_message_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return list;
  }

  String _formatChatListTime(dynamic iso) {
    final dt = DateTime.tryParse('${iso ?? ''}');
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (day == today) return t;
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (now.difference(local).inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[local.weekday - 1];
    }
    return '${local.day}/${local.month}/${local.year % 100}';
  }

  String _chatPreviewText(Map user) {
    final key = 'u:${user['id']}';
    if (_typingPeers.containsKey(key)) return 'typing…';
    final raw = (user['last_message'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    final designation = (user['designation'] ?? '').toString().trim();
    if (designation.isNotEmpty) return designation;
    return 'Tap to chat';
  }

  void _onPresenceUpdate(Map<String, dynamic> data) {
    final userId = data['user_id'];
    final online = _parseOnline(data['is_online']);
    if (!mounted || userId == null) return;
    setState(() {
      _users = _users.map((u) {
        if (u['id'] == userId) {
          return {...Map<String, dynamic>.from(u as Map), 'is_online': online};
        }
        return u;
      }).toList();
      if (_selectedUser != null && _selectedUser['id'] == userId) {
        _selectedUser = {...Map<String, dynamic>.from(_selectedUser as Map), 'is_online': online};
      }
    });
  }

  bool _parseOnline(dynamic v) => v == true || v == 1 || v == 'true';

  void _onTypingEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type']?.toString() ?? '';
    final isTyping = data['is_typing'] == true;
    final senderId = data['sender_id'];
    final name = (data['sender_username'] ?? data['sender_full_name'] ?? 'Someone').toString();

    if (type == 'typing_indicator') {
      final receiverId = data['receiver_id'];
      // Only care when we are the intended receiver.
      if (_myUserId != null && receiverId != null && receiverId != _myUserId) return;
      if (senderId == _myUserId) return;
      final key = 'u:$senderId';
      setState(() {
        if (isTyping) {
          _typingPeers[key] = name;
        } else {
          _typingPeers.remove(key);
        }
      });
      return;
    }

    if (type == 'group_typing') {
      final groupId = data['group_id'];
      if (senderId == _myUserId) return;
      final key = 'g:$groupId:$senderId';
      setState(() {
        if (isTyping) {
          _typingPeers[key] = name;
        } else {
          _typingPeers.remove(key);
        }
      });
    }
  }

  void _onMessagesRead(Map<String, dynamic> data) {
    if (!mounted || _myUserId == null) return;
    final readerId = data['reader_id'];
    final senderId = data['sender_id'];
    // Peer read my messages.
    if (senderId != _myUserId) return;
    if (_selectedUser == null || _selectedUser['id'] != readerId) return;
    setState(() {
      _messages = _messages.map((m) {
        final map = Map<String, dynamic>.from(m as Map);
        if (map['is_own'] == true) map['is_read'] = true;
        return map;
      }).toList();
    });
  }

  String? _activeTypingLabel() {
    if (_selectedUser != null) {
      final key = 'u:${_selectedUser['id']}';
      if (_typingPeers.containsKey(key)) return 'typing…';
      return null;
    }
    if (_selectedGroup != null) {
      final prefix = 'g:${_selectedGroup['id']}:';
      final names = _typingPeers.entries
          .where((e) => e.key.startsWith(prefix))
          .map((e) => e.value)
          .toList();
      if (names.isEmpty) return null;
      if (names.length == 1) return '${names.first} is typing…';
      return '${names.length} people typing…';
    }
    return null;
  }

  void _onComposerChanged() {
    if (!_hasDraft) {
      _stopTypingSignal();
      return;
    }
    _typingIdle?.cancel();
    _typingIdle = Timer(const Duration(seconds: 2), _stopTypingSignal);
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!_hasDraft || !mounted) return;
      _emitTyping(true);
    });
    if (mounted) setState(() {});
  }

  void _emitTyping(bool isTyping) {
    final ns = widget.notificationService;
    if (ns == null) return;
    if (isTyping == _iAmTyping) return;
    _iAmTyping = isTyping;
    if (_selectedUser != null) {
      final id = _selectedUser['id'];
      final uid = id is int ? id : int.tryParse('$id');
      if (uid != null) ns.sendTyping(receiverId: uid, isTyping: isTyping);
    } else if (_selectedGroup != null) {
      final id = _selectedGroup['id'];
      final gid = id is int ? id : int.tryParse('$id');
      if (gid != null) ns.sendGroupTyping(groupId: gid, isTyping: isTyping);
    }
  }

  void _stopTypingSignal() {
    _typingDebounce?.cancel();
    _typingIdle?.cancel();
    if (_iAmTyping) _emitTyping(false);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _avatarColor(int id) {
    const colors = [
      Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFF10B981),
      Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF06B6D4),
    ];
    return colors[id.abs() % colors.length];
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoadingGroups = true);
    final result = await widget.apiService.getChatGroups();
    if (result['success']) {
      setState(() { _groups = result['data'] ?? []; _isLoadingGroups = false; });
    } else {
      setState(() => _isLoadingGroups = false);
      _showError('Failed to load groups');
    }
  }

  Future<void> _selectUser(dynamic user) async {
    _stopTypingSignal();
    setState(() {
      _selectedUser = user;
      _selectedGroup = null;
      _messages = [];
      _replyTo = null;
      _typingPeers.removeWhere((k, _) => k.startsWith('g:'));
    });
    _startRefresh();
    final result = await widget.apiService.getConversation(user['id']);
    if (result['success']) {
      setState(() => _messages = result['data'] ?? []);
      _scrollToBottom();
      unawaited(widget.apiService.markMessagesRead(user['id']));
    }
  }

  Future<void> _selectGroup(dynamic group) async {
    _stopTypingSignal();
    setState(() {
      _selectedGroup = group;
      _selectedUser = null;
      _messages = [];
      _replyTo = null;
      _typingPeers.removeWhere((k, _) => k.startsWith('u:'));
    });
    _startRefresh();
    final result = await widget.apiService.getGroupMessages(group['id']);
    if (result['success']) {
      setState(() => _messages = result['data'] ?? []);
      _scrollToBottom();
    }
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _silentRefresh());
  }

  Future<void> _silentRefresh() async {
    if (_selectedUser != null) {
      final r = await widget.apiService.getConversation(_selectedUser['id']);
      if (r['success'] && mounted) {
        setState(() => _messages = r['data'] ?? []);
        unawaited(widget.apiService.markMessagesRead(_selectedUser['id']));
      }
    } else if (_selectedGroup != null) {
      final r = await widget.apiService.getGroupMessages(_selectedGroup['id']);
      if (r['success'] && mounted) setState(() => _messages = r['data'] ?? []);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;
    if (_selectedUser == null && _selectedGroup == null) return;

    _stopTypingSignal();
    _msgController.clear();
    final replyId = _replyToId;
    setState(() {
      _isSending = true;
      _replyTo = null;
    });

    Map<String, dynamic> result;
    if (_selectedUser != null) {
      result = await widget.apiService.sendMessage(_selectedUser['id'], text, replyToId: replyId);
    } else {
      result = await widget.apiService.sendGroupMessage(_selectedGroup['id'], text, replyToId: replyId);
    }

    if (!mounted) return;
    setState(() => _isSending = false);
    if (result['success'] == true) {
      final payload = result['data'];
      setState(() {
        _messages.add(payload is Map
            ? {
                ...Map<String, dynamic>.from(payload),
                'is_own': true,
                'is_read': payload['is_read'] == true,
              }
            : {
                'message': text,
                'is_own': true,
                'is_read': false,
                'timestamp': DateTime.now().toIso8601String(),
              });
      });
      _scrollToBottom();
      _msgFocus.requestFocus();
    } else {
      _msgController.text = text;
      _msgController.selection = TextSelection.collapsed(offset: text.length);
      _showError(result['error']?.toString() ?? 'Failed to send message');
    }
  }

  bool get _hasDraft => _msgController.text.trim().isNotEmpty;

  int? get _replyToId {
    final raw = _replyTo?['id'];
    if (raw is int) return raw;
    return int.tryParse('${raw ?? ''}');
  }

  void _setReplyTo(dynamic msg) {
    if (msg == null) return;
    final map = Map<String, dynamic>.from(msg as Map);
    final preview = _replyPreviewFromMessage(map);
    setState(() {
      _replyTo = {
        'id': map['id'],
        'sender_name': map['sender_name'] ??
            map['sender_full_name'] ??
            map['sender_username'] ??
            (map['is_own'] == true ? 'You' : 'User'),
        'preview': preview,
        'message_type': map['message_type'] ?? 'text',
      };
    });
    _msgFocus.requestFocus();
  }

  String _replyPreviewFromMessage(Map<String, dynamic> msg) {
    if (msg['is_deleted'] == true) return 'Message deleted';
    final type = (msg['message_type'] ?? 'text').toString();
    if (type == 'image') return 'Photo';
    if (type == 'voice') return 'Voice message';
    if (type == 'file') {
      final name = (msg['file_name'] ?? '').toString().trim();
      return name.isNotEmpty ? 'File: $name' : 'File';
    }
    final text = (msg['message'] ?? '').toString().trim();
    if (text.isEmpty) return 'Message';
    return text.length > 100 ? '${text.substring(0, 100)}…' : text;
  }

  // ─── Voice recording (Android/iOS: record package, Windows: PowerShell) ───
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndSendRecording();
    } else if (Platform.isAndroid || Platform.isIOS) {
      final started = await _recorder.start();
      if (!started) {
        _showError('Microphone permission required');
        return;
      }
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
      Future.delayed(const Duration(seconds: 60), () {
        if (_isRecording) _stopAndSendRecording();
      });
    } else {
      final dir = await getTemporaryDirectory();
      _recPath =
          '${dir.path}${Platform.pathSeparator}voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      // Use PowerShell with .NET to record audio via MCI in a single script
      // The script records until a stop file is created
      final stopFile = '${dir.path}${Platform.pathSeparator}stop_rec.flag';
      // Remove old stop file
      try { await File(stopFile).delete(); } catch (_) {}
      
      final ps = '''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MciRec {
  [DllImport("winmm.dll", CharSet=CharSet.Auto)]
  public static extern int mciSendString(string cmd, System.Text.StringBuilder ret, int retLen, IntPtr hwnd);
}
"@
[MciRec]::mciSendString("open new Type waveaudio Alias vrec", \$null, 0, [IntPtr]::Zero)
[MciRec]::mciSendString("record vrec", \$null, 0, [IntPtr]::Zero)
while (-not (Test-Path '$stopFile')) { Start-Sleep -Milliseconds 200 }
[MciRec]::mciSendString("stop vrec", \$null, 0, [IntPtr]::Zero)
[MciRec]::mciSendString("save vrec $_recPath", \$null, 0, [IntPtr]::Zero)
[MciRec]::mciSendString("close vrec", \$null, 0, [IntPtr]::Zero)
Remove-Item '$stopFile' -ErrorAction SilentlyContinue
''';
      _recProcess = await Process.start('powershell', [
        '-ExecutionPolicy', 'Bypass', '-NoProfile', '-WindowStyle', 'Hidden', '-Command', ps
      ]);
      setState(() { _isRecording = true; _recordSeconds = 0; });
      _recordTimer = Timer.periodic(Duration(seconds: 1), (_) { if (mounted) setState(() => _recordSeconds++); });
      // Auto-stop after 60s
      Future.delayed(Duration(seconds: 60), () { if (_isRecording) _stopAndSendRecording(); });
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    setState(() => _isRecording = false);

    String? filePath;
    if (Platform.isAndroid || Platform.isIOS) {
      filePath = await _recorder.stop();
    } else {
      final dir = await getTemporaryDirectory();
      final stopFile = File('${dir.path}${Platform.pathSeparator}stop_rec.flag');
      await stopFile.writeAsString('stop');
      await Future.delayed(const Duration(seconds: 2));
      _recProcess?.kill();
      filePath = _recPath;
    }

    final user = _selectedUser;
    if (filePath != null && user != null) {
      final file = File(filePath);
      if (await file.exists() && await file.length() > 500) {
        setState(() => _isSending = true);
        final bytes = await file.readAsBytes();
        final ext = filePath.endsWith('.m4a') ? 'm4a' : 'wav';
        final result = await widget.apiService.sendVoiceMessage(
          user['id'],
          bytes,
          'voice_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
        if (mounted) setState(() => _isSending = false);
        if (result['success'] == true) {
          _refreshMessages();
        } else {
          _showError('Failed to send voice');
        }
        await file.delete().catchError((_) {});
      } else {
        _showError('Recording failed - try again');
      }
    }
    if (mounted) setState(() => _recordSeconds = 0);
  }

  // ─── Attach (WhatsApp paperclip sheet) ───
  Future<void> _showAttachSheet() async {
    if (_selectedUser == null && _selectedGroup == null) return;
    final mobile = Responsive.isMobile(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  if (mobile)
                    Expanded(
                      child: _attachTile(
                        icon: Icons.photo_camera_rounded,
                        label: 'Camera',
                        color: const Color(0xFFEF4444),
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(_takePhoto());
                        },
                      ),
                    ),
                  if (mobile) const SizedBox(width: 10),
                  Expanded(
                    child: _attachTile(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      color: const Color(0xFFA855F7),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_pickGalleryImage());
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _attachTile(
                      icon: Icons.insert_drive_file_rounded,
                      label: 'Document',
                      color: const Color(0xFF6366F1),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_pickFile());
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        _showError('Camera permission needed');
        return;
      }
    }
    try {
      final shot = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (shot == null) return;
      await _sendPickedImagePath(shot.path, shot.name);
    } catch (e) {
      _showError('Camera unavailable');
    }
  }

  Future<void> _pickGalleryImage() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final shot = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1920,
        );
        if (shot == null) return;
        await _sendPickedImagePath(shot.path, shot.name);
        return;
      }
    } catch (_) {
      // Fall through to file picker on desktop / failures.
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    await _sendPickedImagePath(result.files.first.path!, result.files.first.name);
  }

  Future<void> _sendPickedImagePath(String path, String name) async {
    if (_selectedUser == null && _selectedGroup == null) return;
    final file = File(path);
    if (!await file.exists()) {
      _showError('Could not read image');
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      _showError('Image must be under 10MB');
      return;
    }
    final replyId = _replyToId;
    setState(() {
      _isSending = true;
      _replyTo = null;
    });
    Map<String, dynamic> r;
    if (_selectedUser != null) {
      r = await widget.apiService.sendImageMessage(
        _selectedUser['id'],
        bytes,
        name.isNotEmpty ? name : 'photo.jpg',
        replyToId: replyId,
      );
    } else {
      r = await widget.apiService.sendGroupImageMessage(
        _selectedGroup['id'],
        bytes,
        name.isNotEmpty ? name : 'photo.jpg',
        replyToId: replyId,
      );
    }
    if (!mounted) return;
    setState(() => _isSending = false);
    if (r['success'] == true) {
      _refreshMessages();
    } else {
      _showError(r['error']?.toString() ?? 'Failed to send image');
    }
  }

  Future<void> _pickFile() async {
    if (_selectedUser == null && _selectedGroup == null) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.first;
    if (pf.path == null) return;
    if (pf.size > 10 * 1024 * 1024) {
      _showError('File must be under 10MB');
      return;
    }
    final file = File(pf.path!);
    setState(() => _isSending = true);
    final bytes = await file.readAsBytes();
    final replyId = _replyToId;
    setState(() => _replyTo = null);
    Map<String, dynamic> r;
    if (_selectedUser != null) {
      r = await widget.apiService.sendFileMessage(
        _selectedUser['id'],
        bytes,
        pf.name,
        replyToId: replyId,
      );
    } else {
      r = await widget.apiService.sendGroupFileMessage(
        _selectedGroup['id'],
        bytes,
        pf.name,
        replyToId: replyId,
      );
    }
    if (!mounted) return;
    setState(() => _isSending = false);
    if (r['success'] == true) {
      _refreshMessages();
    } else {
      _showError(r['error']?.toString() ?? 'Failed to send file');
    }
  }

  // ─── Play Voice ───
  Future<void> _playVoice(String url) async {
    final player = _player;
    if (player == null) {
      _showError('Voice playback is not available on this platform');
      return;
    }
    if (_playingUrl == url) {
      await player.stop();
      setState(() => _playingUrl = null);
      return;
    }
    setState(() => _playingUrl = url);
    await player.play(UrlSource(url));
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingUrl = null);
    });
  }

  void _refreshMessages() {
    if (_selectedUser != null) { _selectUser(_selectedUser); }
    else if (_selectedGroup != null) { _selectGroup(_selectedGroup); }
  }

  Future<void> _createGroup(String name, String desc, List<int> memberIds) async {
    final result = await widget.apiService.createGroup(name, desc, memberIds);
    if (result['success']) {
      _loadGroups();
      if (mounted) Navigator.pop(context);
      _showSuccess('Group created');
    } else {
      _showError('Failed to create group');
    }
  }

  void _scrollToBottom() {
    Future.delayed(Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _showSuccess(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.success),
      );
    }
  }

  String _formatTime(String? ts) {
    if (ts == null || ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  // ═══════════════════════════════════════════════════════════════
  /// Logo → dashboard (home tab). Used when immersive chrome hides the main top bar.
  Widget _dashboardLogoButton() {
    return Tooltip(
      message: 'Dashboard',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => AppNavigation.instance.goHome(),
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: AppLogo(size: 30, showBorder: false),
          ),
        ),
      ),
    );
  }

  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.useChatSplit(context);
    final hasChat = _selectedUser != null || _selectedGroup != null;
    final listWidth = isWide ? Responsive.chatListPaneWidth(context) : double.infinity;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final immersive = PlatformCapabilities.immersiveChatChrome;
    final bottomInset = keyboard > 0
        ? 0.0
        : (immersive
            ? MediaQuery.paddingOf(context).bottom
            : Responsive.bottomNavInset(context));

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: immersive,
        bottom: false,
        child: isWide
            ? Row(children: [
                SizedBox(width: listWidth, child: _buildSidebar()),
                Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
                Expanded(child: hasChat ? _buildChatArea() : _buildEmptyState()),
              ])
            : hasChat ? _buildChatArea() : _buildSidebar(),
      ),
    );
  }

  // ─── LEFT SIDEBAR ───
  Widget _buildSidebar() {
    final immersive = PlatformCapabilities.immersiveChatChrome;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            immersive ? 4 : Responsive.pagePadding(context),
            immersive ? 4 : 8,
            Responsive.pagePadding(context),
            4,
          ),
          child: Row(
            children: [
              if (immersive)
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => AppNavigation.instance.goHome(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppTheme.textPrimary),
                ),
              Expanded(
                child: Text(
                  'Chat',
                  textAlign: immersive ? TextAlign.left : TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (immersive && _currentTab == 'group')
                IconButton(
                  tooltip: 'New group',
                  onPressed: _showCreateGroupDialog,
                  icon: const Icon(Icons.group_add_rounded, color: AppTheme.primaryBright, size: 22),
                ),
              if (immersive) _dashboardLogoButton(),
            ],
          ),
        ),
        Container(
          margin: EdgeInsets.fromLTRB(Responsive.pagePadding(context), 4, Responsive.pagePadding(context), 10),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              _buildTab('Direct', Icons.person_outline_rounded, 'direct'),
              _buildTab('Groups', Icons.groups_outlined, 'group'),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(Responsive.pagePadding(context), 0, Responsive.pagePadding(context), 10),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search people or groups',
              hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.75), fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMuted.withValues(alpha: 0.9), size: 22),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.07),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.55)),
              ),
            ),
          ),
        ),
        Expanded(
          child: _currentTab == 'direct' ? _buildUsersList() : _buildGroupsList(),
        ),
      ],
    );
  }

  Widget _buildTab(String label, IconData icon, String tab) {
    final isActive = _currentTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() { _currentTab = tab; });
          if (tab == 'group' && _groups.isEmpty) _loadGroups();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primary.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isActive ? AppTheme.primaryBright : AppTheme.textMuted),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: isActive ? AppTheme.textPrimary : AppTheme.textMuted,
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Users List ───
  Widget _buildUsersList() {
    if (_isLoadingUsers) return _buildLoader('Loading users...');
    if (_users.isEmpty) return _buildEmpty('No users available');

    final filtered = _users.where((u) {
      if (_searchQuery.isEmpty) return true;
      final name = (u['full_name'] ?? u['username'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery);
    }).toList();

    final immersive = PlatformCapabilities.immersiveChatChrome;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(immersive ? 8 : 12, 0, immersive ? 8 : 12, 8),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => immersive
          ? Divider(height: 1, indent: 72, color: Colors.white.withValues(alpha: 0.06))
          : const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final user = filtered[i];
        final isSelected = _selectedUser != null && _selectedUser['id'] == user['id'];
        final isOnline = _parseOnline(user['is_online']);
        final unread = user['unread_count'] ?? 0;
        final name = user['full_name'] ?? user['username'] ?? 'User';
        final preview = _chatPreviewText(Map<String, dynamic>.from(user as Map));
        final isPeerTyping = _typingPeers.containsKey('u:${user['id']}');
        final timeLabel = _formatChatListTime(user['last_message_at']);
        final uid = user['id'] is int ? user['id'] as int : int.tryParse('${user['id']}') ?? 0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectUser(user),
            borderRadius: BorderRadius.circular(immersive ? 14 : 12),
            child: Container(
              margin: immersive ? EdgeInsets.zero : const EdgeInsets.only(bottom: 0),
              padding: EdgeInsets.symmetric(
                horizontal: immersive ? 10 : 12,
                vertical: immersive ? 12 : 12,
              ),
              decoration: immersive
                  ? (isSelected
                      ? BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        )
                      : null)
                  : (isSelected
                      ? AppTheme.taskCardDecoration(borderRadius: 12).copyWith(
                          color: AppTheme.primary.withValues(alpha: 0.18),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                        )
                      : AppTheme.taskFieldDecoration(borderRadius: 12)),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: immersive ? 24 : 20,
                        backgroundColor: _avatarColor(uid),
                        child: Text(_initials(name),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: immersive ? 15 : 14,
                          )),
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: isOnline ? const Color(0xFF34D399) : const Color(0xFF6B7280),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.bgDeep, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(name, style: TextStyle(
                                fontSize: immersive ? 16 : 14,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : AppTheme.textPrimary.withValues(alpha: 0.92),
                              ), overflow: TextOverflow.ellipsis),
                            ),
                            if (timeLabel.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                timeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: unread > 0
                                      ? AppTheme.success
                                      : AppTheme.textMuted.withValues(alpha: 0.85),
                                  fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isPeerTyping
                                      ? const Color(0xFF34D399)
                                      : unread > 0
                                          ? AppTheme.textPrimary.withValues(alpha: 0.85)
                                          : AppTheme.textMuted.withValues(alpha: 0.9),
                                  fontWeight: isPeerTyping || unread > 0 ? FontWeight.w500 : FontWeight.w400,
                                  fontStyle: isPeerTyping ? FontStyle.italic : FontStyle.normal,
                                ),
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                decoration: const BoxDecoration(
                                  color: AppTheme.danger,
                                  borderRadius: BorderRadius.all(Radius.circular(11)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  unread > 99 ? '99+' : '$unread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Groups List ───
  Widget _buildGroupsList() {
    final immersive = PlatformCapabilities.immersiveChatChrome;
    return Column(
      children: [
        if (!immersive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showCreateGroupDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create Group', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        Expanded(
          child: _isLoadingGroups
              ? _buildLoader('Loading groups...')
              : _groups.isEmpty
                  ? _buildEmpty('No groups yet')
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: immersive ? 8 : 12, vertical: 4),
                      itemCount: _filteredGroups.length,
                      itemBuilder: (_, i) {
                        final group = _filteredGroups[i];
                        final isSelected = _selectedGroup != null && _selectedGroup['id'] == group['id'];
                        final unread = group['unread_count'] ?? 0;
                        final name = group['name'] ?? 'Group';
                        final members = group['member_count'] ?? 0;
                        final preview = (group['last_message'] ?? '').toString().trim();
                        final subtitle = preview.isNotEmpty ? preview : '$members members';
                        final timeLabel = _formatChatListTime(group['last_message_at'] ?? group['updated_at']);

                        return GestureDetector(
                          onTap: () => _selectGroup(group),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(12),
                            decoration: isSelected
                                ? AppTheme.taskCardDecoration(borderRadius: 12).copyWith(
                                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
                                  )
                                : AppTheme.taskFieldDecoration(borderRadius: 12),
                            child: Row(
                              children: [
                                // Group avatar
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [AppTheme.primary, AppTheme.primaryBright],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(child: Text(
                                    name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase(),
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  )),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(name, style: TextStyle(
                                              fontSize: 14, fontWeight: FontWeight.w600,
                                              color: isSelected ? Colors.white : AppTheme.textPrimary.withValues(alpha: 0.85),
                                            ), overflow: TextOverflow.ellipsis),
                                          ),
                                          if (timeLabel.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              timeLabel,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: unread > 0
                                                    ? AppTheme.success
                                                    : AppTheme.textMuted.withValues(alpha: 0.85),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                                        fontSize: 12, color: AppTheme.textMuted,
                                      )),
                                    ],
                                  ),
                                ),
                                if (unread > 0)
                                  Container(
                                    width: 20, height: 20,
                                    decoration: BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                                    child: Center(child: Text('$unread',
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  List<dynamic> get _filteredGroups {
    if (_searchQuery.isEmpty) return _groups;
    return _groups.where((g) =>
      (g['name'] ?? '').toString().toLowerCase().contains(_searchQuery)
    ).toList();
  }

  // ─── Chat Area (Right Side) ───
  Widget _buildChatArea() {
    final isWide = Responsive.useChatSplit(context);
    final isGroup = _selectedGroup != null;
    final name = isGroup
        ? (_selectedGroup['name'] ?? 'Group')
        : (_selectedUser['full_name'] ?? _selectedUser['username'] ?? 'Chat');
    final isOnline = !isGroup && _parseOnline(_selectedUser?['is_online']);
    final typingLabel = _activeTypingLabel();
    final designation = !isGroup
        ? (_selectedUser?['designation'] ?? '').toString().trim()
        : '';
    final subtitle = typingLabel ??
        (isGroup
            ? '${_selectedGroup['member_count'] ?? 0} members'
            : (isOnline
                ? 'online'
                : (designation.isNotEmpty ? designation : 'offline')));
    final subtitleColor = typingLabel != null
        ? const Color(0xFF34D399)
        : (isOnline ? const Color(0xFF34D399) : AppTheme.textMuted);
    final headerUid = !isGroup && _selectedUser != null
        ? (_selectedUser['id'] is int ? _selectedUser['id'] as int : int.tryParse('${_selectedUser['id']}') ?? 0)
        : 0;

    return Column(
      children: [
        Container(
          height: PlatformCapabilities.immersiveChatChrome ? 66 : 74,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xF20B1220),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
          ),
          child: Row(
            children: [
              if (!isWide)
                IconButton(
                  tooltip: 'Back',
                  onPressed: () {
                    _stopTypingSignal();
                    setState(() {
                      _selectedUser = null;
                      _selectedGroup = null;
                      _refreshTimer?.cancel();
                    });
                  },
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
                ),
              if (isGroup)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                    ),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: const Center(child: Icon(Icons.group_rounded, color: Colors.white, size: 22)),
                )
              else
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _avatarColor(headerUid),
                      child: Text(
                        _initials(name),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF34D399) : const Color(0xFF64748B),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF0B1220), width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: typingLabel != null ? FontWeight.w600 : FontWeight.w400,
                        fontStyle: typingLabel != null ? FontStyle.italic : FontStyle.normal,
                        color: subtitleColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isGroup)
                IconButton(
                  tooltip: 'Group settings',
                  onPressed: () => _showGroupSettings(_selectedGroup),
                  icon: const Icon(Icons.settings_outlined, color: AppTheme.textMuted, size: 22),
                ),
              if (PlatformCapabilities.immersiveChatChrome) _dashboardLogoButton(),
            ],
          ),
        ),

        Expanded(
          child: ColoredBox(
            color: const Color(0xFF0B141A),
            child: _messages.isEmpty
                ? _buildEmpty('No messages yet\nStart the conversation!')
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildMessageBubble(_messages[i]),
                  ),
          ),
        ),

        if (_isRecording)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x331E293B),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Row(children: [
              Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.danger)),
              const SizedBox(width: 8),
              Text('Recording ${_recordSeconds}s', style: const TextStyle(color: AppTheme.danger, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: _stopAndSendRecording,
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                  child: const Icon(Icons.stop, color: Colors.white, size: 22),
                ),
              ),
            ]),
          )
        else
          _buildMessageComposer(),
      ],
    );
  }

  Future<void> _showEmojiPicker() async {
    const emojis = [
      '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤔', '😢',
      '😭', '😡', '👍', '👎', '👏', '🙏', '🔥', '❤️', '💯', '✅',
      '🎉', '🤝', '💪', '🙌', '😅', '😉', '😴', '🤗', '🫡', '🫶',
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                itemCount: emojis.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemBuilder: (_, i) {
                  final e = emojis[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      final t = _msgController.text;
                      final sel = _msgController.selection;
                      final start = sel.start >= 0 ? sel.start : t.length;
                      final end = sel.end >= 0 ? sel.end : t.length;
                      final next = t.replaceRange(start, end, e);
                      _msgController.value = TextEditingValue(
                        text: next,
                        selection: TextSelection.collapsed(offset: start + e.length),
                      );
                      setState(() {});
                    },
                    child: Center(child: Text(e, style: const TextStyle(fontSize: 24))),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    _msgFocus.requestFocus();
  }

  /// WhatsApp-style composer: [emoji | Message | 📎 📷]  (🎤/➤)
  Widget _buildMessageComposer() {
    final mobile = Responsive.isMobile(context);
    final hasText = _hasDraft;
    const waGreen = Color(0xFF00A884);
    const inputBg = Color(0xFF2A3942);
    const iconGrey = Color(0xFF8696A0);

    return Container(
      color: const Color(0xFF0B141A),
      padding: EdgeInsets.fromLTRB(mobile ? 6 : 12, 6, mobile ? 6 : 12, 6),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null) _buildReplyComposerBar(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48, maxHeight: 140),
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Emoji',
                          onPressed: _isSending ? null : _showEmojiPicker,
                          icon: const Icon(Icons.emoji_emotions_outlined, color: iconGrey, size: 26),
                        ),
                        Expanded(
                          child: CallbackShortcuts(
                            bindings: {
                              const SingleActivator(LogicalKeyboardKey.enter, control: true): _sendMessage,
                              const SingleActivator(LogicalKeyboardKey.enter, meta: true): _sendMessage,
                            },
                            child: TextField(
                              controller: _msgController,
                              focusNode: _msgFocus,
                              enabled: !_isSending,
                              minLines: 1,
                              maxLines: 6,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(color: Color(0xFFE9EDEF), fontSize: 16, height: 1.35),
                              cursorColor: waGreen,
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'Message',
                                hintStyle: TextStyle(color: iconGrey, fontSize: 16),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Attach',
                          onPressed: _isSending ? null : _showAttachSheet,
                          icon: const Icon(Icons.attach_file_rounded, color: iconGrey, size: 24),
                        ),
                        if (!hasText)
                          IconButton(
                            tooltip: 'Camera',
                            onPressed: _isSending ? null : () => unawaited(_takePhoto()),
                            icon: const Icon(Icons.photo_camera_outlined, color: iconGrey, size: 24),
                          ),
                        const SizedBox(width: 2),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _isSending ? null : (hasText ? _sendMessage : _toggleRecording),
                      child: Ink(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: waGreen,
                          shape: BoxShape.circle,
                        ),
                        child: _isSending
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(
                                hasText ? Icons.send_rounded : Icons.mic_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyComposerBar() {
    final reply = _replyTo!;
    const accent = Color(0xFF00A884);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.horizontal(left: Radius.circular(10)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reply',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${reply['sender_name'] ?? 'Message'}',
                      style: const TextStyle(
                        color: Color(0xFFE9EDEF),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${reply['preview'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF8696A0).withValues(alpha: 0.95),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Cancel reply',
              onPressed: () => setState(() => _replyTo = null),
              icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF8696A0)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Message Bubble ───
  Widget _buildMessageBubble(dynamic msg) {
    final isOwn = msg['is_own'] == true;
    final isGroup = _selectedGroup != null;
    final senderName = msg['sender_name'] ?? msg['sender_username'] ?? msg['sender_full_name'] ?? '';
    final text = msg['message'] ?? '';
    final time = _formatTime(msg['timestamp'] ?? msg['created_at'] ?? '');
    final isDeleted = msg['is_deleted'] == true;
    final isEdited = msg['edited_at'] != null;
    final msgType = msg['message_type'] ?? 'text';
    final voiceUrl = msg['voice_url'];
    final imageUrl = msg['image_url'];
    final fileUrl = msg['file_url'];
    final fileName = msg['file_name'] ?? 'file';
    final reply = msg['reply'] is Map ? Map<String, dynamic>.from(msg['reply'] as Map) : null;
    const ownBubble = Color(0xFF005C4B);
    const otherBubble = Color(0xFF1F2C34);

    Widget metaRow({required bool light}) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEdited)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  'edited',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: light ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF8696A0),
                  ),
                ),
              ),
            Text(
              time,
              style: TextStyle(
                fontSize: 11,
                color: light ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF8696A0),
              ),
            ),
            if (isOwn && !isGroup && !isDeleted) ...[
              const SizedBox(width: 3),
              Icon(
                Icons.done_all_rounded,
                size: 16,
                color: msg['is_read'] == true
                    ? const Color(0xFF53BDEB)
                    : Colors.white.withValues(alpha: 0.55),
              ),
            ],
          ],
        ),
      );
    }

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: GestureDetector(
          onLongPress: !isDeleted ? () => _showMessageOptions(msg) : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 6, 9, 5),
            decoration: BoxDecoration(
              color: isOwn ? ownBubble : otherBubble,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isOwn ? 12 : 2),
                bottomRight: Radius.circular(isOwn ? 2 : 12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isOwn && isGroup)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3, left: 2),
                    child: Text(
                      senderName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF53BDEB),
                      ),
                    ),
                  ),
                if (reply != null) ...[
                  _buildQuotedReply(reply, isOwn: isOwn),
                  const SizedBox(height: 4),
                ],
                if (isDeleted)
                  Text(
                    'This message was deleted',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else if (msgType == 'voice' && voiceUrl != null)
                  GestureDetector(
                    onTap: () => _playVoice(voiceUrl),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        _playingUrl == voiceUrl ? Icons.stop_circle : Icons.play_circle_fill,
                        color: isOwn ? Colors.white : const Color(0xFF00A884),
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          'Voice message',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _playingUrl == voiceUrl ? 'Playing…' : 'Tap to play',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
                        ),
                      ]),
                    ]),
                  )
                else if (msgType == 'image' && imageUrl != null)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        width: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 220,
                          height: 100,
                          color: Colors.white10,
                          child: const Icon(Icons.broken_image, color: Colors.white38),
                        ),
                      ),
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(text, style: const TextStyle(color: Color(0xFFE9EDEF), fontSize: 14.5, height: 1.35)),
                    ],
                  ])
                else if (msgType == 'file' && fileUrl != null)
                  GestureDetector(
                    onTap: () => _openFileUrl(fileUrl),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF53BDEB), size: 24),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            fileName,
                            style: const TextStyle(
                              color: Color(0xFFE9EDEF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('Tap to open', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11)),
                        ]),
                      ),
                    ]),
                  )
                else
                  Text(
                    text.toString(),
                    softWrap: true,
                    style: const TextStyle(color: Color(0xFFE9EDEF), fontSize: 15, height: 1.35),
                  ),
                Align(alignment: Alignment.bottomRight, child: metaRow(light: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuotedReply(Map<String, dynamic> reply, {required bool isOwn}) {
    final accent = isOwn ? const Color(0xFF06CF9C) : const Color(0xFF53BDEB);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reply['sender_name'] ?? 'Message'}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${reply['preview'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFileUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showError('Could not open file');
    }
  }

  // ─── Message Options (Reply / Edit / Delete) ───
  void _showMessageOptions(dynamic msg) {
    final isOwn = msg['is_own'] == true;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppTheme.textMuted, borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: AppTheme.primaryBright),
              title: const Text('Reply', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _setReplyTo(msg);
              },
            ),
            if (isOwn && (msg['message_type'] == 'text' || msg['message_type'] == null))
              ListTile(
                leading: const Icon(Icons.edit, color: AppTheme.primary),
                title: const Text('Edit Message', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(msg);
                },
              ),
            if (isOwn)
              ListTile(
                leading: const Icon(Icons.delete, color: AppTheme.danger),
                title: const Text('Delete Message', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(msg);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(dynamic msg) {
    final controller = TextEditingController(text: msg['message'] ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Message', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          minLines: 1,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: AppTheme.textPrimary, height: 1.35),
          decoration: InputDecoration(
            filled: true, fillColor: AppTheme.surface2.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await widget.apiService.editMessage(msg['id'], controller.text);
              if (result['success']) { _silentRefresh(); _showSuccess('Message edited'); }
              else { _showError('Failed to edit'); }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(dynamic msg) async {
    final result = await widget.apiService.deleteMessage(msg['id']);
    if (result['success']) { _silentRefresh(); _showSuccess('Message deleted'); }
    else { _showError('Failed to delete'); }
  }

  // ─── Create Group Dialog ───
  void _showCreateGroupDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final selectedIds = <int>{};

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Create New Group', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Group Name', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: _dialogInputDecor('e.g., Development Team'),
                  ),
                  SizedBox(height: 16),
                  Text('Description (Optional)', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    maxLines: 3,
                    decoration: _dialogInputDecor("What's this group about?"),
                  ),
                  SizedBox(height: 16),
                  Text('Add Members', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Container(
                    constraints: BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: AppTheme.surface2.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _users.length,
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        final uid = u['id'] as int;
                        final uname = u['full_name'] ?? u['username'] ?? 'User';
                        return CheckboxListTile(
                          dense: true,
                          value: selectedIds.contains(uid),
                          onChanged: (v) => setDialogState(() {
                            v == true ? selectedIds.add(uid) : selectedIds.remove(uid);
                          }),
                          title: Text(uname, style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.85), fontSize: 14)),
                          activeColor: AppTheme.primary,
                          checkColor: Colors.white,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) { _showError('Group name is required'); return; }
                Navigator.pop(context);
                _createGroup(nameCtrl.text.trim(), descCtrl.text.trim(), selectedIds.toList());
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text('Create Group'),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
    filled: true, fillColor: AppTheme.surface2.withValues(alpha: 0.5),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary)),
  );

  // ─── Group Settings ───
  void _showGroupSettings(dynamic group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => _GroupSettingsSheet(
          group: group,
          apiService: widget.apiService,
          users: _users,
          scrollController: scrollCtrl,
          onGroupUpdated: () { _loadGroups(); _silentRefresh(); },
          onGroupDeleted: () {
            _loadGroups();
            setState(() { _selectedGroup = null; _messages = []; _refreshTimer?.cancel(); });
          },
        ),
      ),
    );
  }

  // ─── Helpers ───
  Widget _buildLoader(String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryBright, strokeWidth: 2),
            const SizedBox(height: 12),
            Text(text, style: AppTheme.caption.copyWith(fontSize: 14)),
          ],
        ),
      );

  Widget _buildEmpty(String text) {
    final lines = text.split('\n');
    return Center(
      child: EmptyState(
        icon: Icons.chat_bubble_outline,
        title: lines.first,
        subtitle: lines.length > 1 ? lines.sublist(1).join('\n') : null,
        iconColor: AppTheme.featureChat,
      ),
    );
  }

  Widget _buildEmptyState() => const Center(
        child: EmptyState(
          icon: Icons.forum_outlined,
          title: 'Select a chat',
          subtitle: 'Pick a conversation from the list to start messaging',
          iconColor: AppTheme.featureChat,
        ),
      );
}


// ═══════════════════════════════════════════════════════════════
// Group Settings Bottom Sheet
// ═══════════════════════════════════════════════════════════════
class _GroupSettingsSheet extends StatefulWidget {
  final dynamic group;
  final ApiService apiService;
  final List<dynamic> users;
  final ScrollController scrollController;
  final VoidCallback onGroupUpdated;
  final VoidCallback onGroupDeleted;

  const _GroupSettingsSheet({
    required this.group,
    required this.apiService,
    required this.users,
    required this.scrollController,
    required this.onGroupUpdated,
    required this.onGroupDeleted,
  });

  @override
  State<_GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends State<_GroupSettingsSheet> {
  List<dynamic> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final r = await widget.apiService.getGroupMembers(widget.group['id']);
    if (r['success'] && mounted) {
      setState(() { _members = r['data'] ?? []; _loading = false; });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.all(20),
      children: [
        // Handle
        Center(child: Container(width: 40, height: 4, margin: EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: AppTheme.textMuted, borderRadius: BorderRadius.circular(2)))),

        Text('Group Settings', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
        SizedBox(height: 20),

        // ─── Group Info ───
        _settingsCard([
          _infoRow('Group Name', group['name'] ?? ''),
          _infoRow('Description', group['description'] ?? 'No description'),
          _infoRow('Created', group['created_at'] ?? ''),
          if (group['project_name'] != null)
            _infoRow('Project', group['project_name']),
        ], action: TextButton.icon(
          onPressed: () => _showEditGroup(),
          icon: Icon(Icons.edit, size: 14, color: AppTheme.primary),
          label: Text('Edit', style: TextStyle(color: AppTheme.primary, fontSize: 12)),
        )),
        SizedBox(height: 16),

        // ─── Members ───
        _settingsCard([
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Members (${_members.length})', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              TextButton.icon(
                onPressed: _showAddMembers,
                icon: Icon(Icons.person_add, size: 14, color: AppTheme.success),
                label: Text('Add', style: TextStyle(color: AppTheme.success, fontSize: 12)),
              ),
            ],
          ),
          if (_loading)
            Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.textMuted)))
          else
            ..._members.map((m) => _memberTile(m)),
        ]),
        SizedBox(height: 16),

        // ─── Danger Zone ───
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.danger.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Danger Zone', style: TextStyle(color: AppTheme.danger, fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('These actions cannot be undone.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _confirmDeleteGroup,
                icon: Icon(Icons.delete, size: 16),
                label: Text('Delete Group'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsCard(List<Widget> children, {Widget? action}) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0x4D1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (action != null) Row(mainAxisAlignment: MainAxisAlignment.end, children: [action]),
        ...children,
      ]),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      SizedBox(height: 4),
      Text(value, style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.85), fontSize: 14)),
    ]),
  );

  Widget _memberTile(dynamic m) {
    final name = m['full_name'] ?? m['username'] ?? 'User';
    final role = m['role'] ?? 'member';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(radius: 16, backgroundColor: AppTheme.surface2,
            child: Text(name[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: 12))),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
            Text(role, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ])),
          if (role != 'admin')
            GestureDetector(
              onTap: () => _removeMember(m),
              child: Icon(Icons.remove_circle_outline, color: AppTheme.danger, size: 20),
            ),
        ],
      ),
    );
  }

  void _showEditGroup() {
    final nameCtrl = TextEditingController(text: widget.group['name'] ?? '');
    final descCtrl = TextEditingController(text: widget.group['description'] ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Group', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(labelText: 'Group Name', labelStyle: TextStyle(color: AppTheme.textMuted),
              filled: true, fillColor: AppTheme.surface2.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary)))),
          SizedBox(height: 12),
          TextField(controller: descCtrl, style: TextStyle(color: AppTheme.textPrimary), maxLines: 3,
            decoration: InputDecoration(labelText: 'Description', labelStyle: TextStyle(color: AppTheme.textMuted),
              filled: true, fillColor: AppTheme.surface2.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary)))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final r = await widget.apiService.updateGroup(widget.group['id'], nameCtrl.text.trim(), descCtrl.text.trim());
              if (r['success']) { widget.onGroupUpdated(); if (mounted) Navigator.pop(context); }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddMembers() {
    final memberUserIds = _members.map((m) => m['user']).toSet();
    final available = widget.users.where((u) => !memberUserIds.contains(u['id'])).toList();
    final selectedIds = <int>{};

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: AppTheme.surface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Add Members', style: TextStyle(color: AppTheme.textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: available.isEmpty
                ? Text('No available members to add', style: TextStyle(color: AppTheme.textMuted))
                : Container(
                    constraints: BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: available.length,
                      itemBuilder: (_, i) {
                        final u = available[i];
                        return CheckboxListTile(
                          dense: true,
                          value: selectedIds.contains(u['id']),
                          onChanged: (v) => setDState(() {
                            v == true ? selectedIds.add(u['id']) : selectedIds.remove(u['id']);
                          }),
                          title: Text(u['full_name'] ?? u['username'] ?? 'User',
                            style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.85), fontSize: 14)),
                          activeColor: AppTheme.primary,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                if (selectedIds.isNotEmpty) {
                  await widget.apiService.addGroupMembers(widget.group['id'], selectedIds.toList());
                  _loadMembers();
                  widget.onGroupUpdated();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              child: Text('Add Members'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeMember(dynamic m) async {
    final r = await widget.apiService.removeGroupMember(widget.group['id'], m['user']);
    if (r['success']) { _loadMembers(); widget.onGroupUpdated(); }
  }

  void _confirmDeleteGroup() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Group?', style: TextStyle(color: AppTheme.danger)),
        content: Text('This action cannot be undone.', style: TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close settings sheet
              await widget.apiService.deleteGroup(widget.group['id']);
              widget.onGroupDeleted();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }
}
