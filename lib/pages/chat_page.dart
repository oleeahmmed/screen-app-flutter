import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../utils/chat_emojis.dart';
import '../services/chat_notification_router.dart';
import '../services/notification_service.dart';
import '../services/call_service.dart';
import '../services/call_navigation.dart';
import '../services/user_data_service.dart';
import '../services/voice_recorder_service.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/app_logo.dart';
import '../services/chat_clipboard.dart';
import '../services/chat_wallpaper_prefs.dart';
import '../services/chat_pin_prefs.dart';
import '../widgets/chat_wallpaper_background.dart';
import '../widgets/swipe_to_reply.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_reactions.dart';
import '../widgets/chat_image_send_preview.dart';
import '../widgets/chat_details_panel.dart';
import '../widgets/chat_image_viewer.dart';
import '../widgets/empty_state.dart';
import '../utils/responsive.dart';
import '../utils/platform_capabilities.dart';

int? _chatInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse('$v');
}

int? _membershipUserId(dynamic m) {
  if (m is! Map) return null;
  final u = m['user'];
  if (u is Map) return _chatInt(u['id']);
  return _chatInt(u ?? m['user_id']);
}

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
  StreamSubscription<Map<String, dynamic>>? _chatMsgSub;
  StreamSubscription<Map<String, dynamic>>? _reactionSub;
  StreamSubscription<CallPhase>? _callPhaseSub;
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
  /// Keep quote visible even if API refresh omits `reply` (migration lag / race).
  final Map<int, Map<String, dynamic>> _replyQuotesByMsgId = {};
  /// peerUserId / groupId â†’ display name while typing
  final Map<String, String> _typingPeers = {};
  final _imagePicker = ImagePicker();
  bool _emojiOpen = false;
  double _emojiPanelHeight = 280;
  /// Latest chat thread pane width (from LayoutBuilder) for bubble sizing.
  double _chatThreadWidth = 400;
  /// WhatsApp-style contact/group details (right pane on wide desktop).
  bool _detailsOpen = false;
  /// Filter messages in the open thread (from details Search).
  String _inChatQuery = '';
  bool _chatDragOver = false;
  ChatWallpaperKind _wallpaperKind = ChatWallpaperKind.doodle;
  int _wallpaperSolid = 0xFF0B141A;
  String? _wallpaperImagePath;
  Uint8List? _lastCopiedImageBytes;
  final Set<int> _selectedMessageIds = {};
  final Set<int> _starredMessageIds = {};
  List<String> _pinnedChatKeys = [];
  final GlobalKey _selectionHeaderKey = GlobalKey();
  final GlobalKey _chatMessageStackKey = GlobalKey();
  dynamic _reactionPickerMsg;
  BuildContext? _reactionPickerAnchor;
  Offset? _reactionPickerTopLeft;
  Size? _reactionPickerAnchorSize;
  bool _reactionPickerShowMore = false;
  bool _reactionPickerClearSelectionOnDismiss = false;
  static const int _chatPageSize = 30;
  bool _hasMoreMessages = false;
  bool _isLoadingMoreMessages = false;
  bool _isLoadingMessages = false;
  bool _loadMoreArmed = true;

  static const TextStyle _bubbleTextStyle = TextStyle(
    color: Color(0xFFE9EDEF),
    fontSize: 15,
    height: 1.28,
    letterSpacing: 0.15,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _bubbleMetaStyle = TextStyle(
    fontSize: 11,
    height: 1,
    letterSpacing: 0,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _reactionEmojiStyle = TextStyle(
    fontSize: 17,
    height: 1.0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static Widget _emojiText(String emoji, {double size = 17}) {
    return Text(
      emoji,
      style: _reactionEmojiStyle.copyWith(fontSize: size),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );
  }

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
      if (!mounted) return;
      if (_msgFocus.hasFocus && _emojiOpen) {
        setState(() => _emojiOpen = false);
      } else {
        setState(() {});
      }
    });
    _msgController.addListener(_onComposerChanged);
    _loadUsers();
    _loadGroups(silent: true);
    _loadMyUserId();
    unawaited(_loadWallpaper());
    unawaited(_loadPinnedChats());
    _usersPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadUsers(silent: true);
      _loadGroups(silent: true);
    });
    _presenceSub = widget.notificationService?.presenceStream.listen(_onPresenceUpdate);
    _typingSub = widget.notificationService?.typingStream.listen(_onTypingEvent);
    _messagesReadSub = widget.notificationService?.messagesReadStream.listen(_onMessagesRead);
    _chatMsgSub = widget.notificationService?.chatMessageStream.listen(_onRealtimeChatMessage);
    _reactionSub = widget.notificationService?.reactionStream.listen(_onRealtimeReaction);
    AppNavigation.instance.onPendingChatOpen = _consumePendingChatOpen;
    ChatNotificationRouter.chatTabActive = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _consumePendingChatOpen();
    });
    _callPhaseSub = CallService.instance.phaseStream.listen((phase) {
      if (phase == CallPhase.incoming && mounted) {
        CallNavigation.openCallPageIfNeeded();
      }
    });
    _scrollController.addListener(_onChatScroll);
  }

  void _onChatScroll() {
    if (!_scrollController.hasClients || _isLoadingMoreMessages || !_hasMoreMessages) return;
    if (_scrollController.position.pixels > 140) {
      _loadMoreArmed = true;
      return;
    }
    if (_loadMoreArmed) {
      _loadMoreArmed = false;
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadWallpaper() async {
    final w = await ChatWallpaperPrefs.load();
    if (!mounted) return;
    setState(() {
      _wallpaperKind = w.kind;
      _wallpaperSolid = w.solidColor;
      _wallpaperImagePath = w.imagePath;
    });
  }

  Future<void> _loadPinnedChats() async {
    final keys = await ChatPinPrefs.loadOrderedKeys();
    if (!mounted) return;
    setState(() => _pinnedChatKeys = keys);
  }

  String? _openChatPinKey() {
    if (_selectedGroup != null) {
      final id = _asInt(_selectedGroup['id']);
      if (id == null) return null;
      return ChatPinPrefs.chatKey(isGroup: true, id: id);
    }
    if (_selectedUser != null) {
      final id = _asInt(_selectedUser['id']);
      if (id == null) return null;
      return ChatPinPrefs.chatKey(isGroup: false, id: id);
    }
    return null;
  }

  bool _isChatPinned(String pinKey) => _pinnedChatKeys.contains(pinKey);

  Future<void> _toggleChatPin({
    required bool isGroup,
    required int id,
    String? name,
  }) async {
    final pinKey = ChatPinPrefs.chatKey(isGroup: isGroup, id: id);
    final wasPinned = _isChatPinned(pinKey);
    final keys = await ChatPinPrefs.togglePin(pinKey);
    if (!mounted) return;
    setState(() => _pinnedChatKeys = keys);
    final label = name?.trim();
    final who = (label != null && label.isNotEmpty) ? label : 'Chat';
    AppToast.success(context, wasPinned ? '$who unpinned' : '$who pinned');
  }

  Future<void> _showInboxChatOptions({
    required bool isGroup,
    required int id,
    required String name,
  }) async {
    final pinKey = ChatPinPrefs.chatKey(isGroup: isGroup, id: id);
    final pinned = _isChatPinned(pinKey);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                color: AppTheme.primaryBright,
              ),
              title: Text(pinned ? 'Unpin chat' : 'Pin chat'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: AppTheme.textMuted),
              title: const Text('Chat info'),
              onTap: () => Navigator.pop(ctx, 'info'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'pin') {
      await _toggleChatPin(isGroup: isGroup, id: id, name: name);
    } else if (action == 'info') {
      if (isGroup) {
        final group = _groups.cast<Map?>().firstWhere(
          (g) => _asInt(g?['id']) == id,
          orElse: () => null,
        );
        if (group != null) unawaited(_selectGroup(group, openDetails: true));
      } else {
        final user = _users.cast<Map?>().firstWhere(
          (u) => _asInt(u?['id']) == id,
          orElse: () => null,
        );
        if (user != null) unawaited(_selectUser(user, openDetails: true));
      }
    }
  }

  Future<void> _showWallpaperPicker() async {
    const presets = <int>[
      0xFF0B141A,
      0xFF111B21,
      0xFF1A2E2A,
      0xFF1F2937,
      0xFF2D1B2E,
      0xFF1B2533,
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chat wallpaper',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'WhatsApp-style background for all chats',
                style: TextStyle(color: Color(0xFF8696A0), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _wallpaperSwatch(
                    label: 'Default',
                    selected: _wallpaperKind == ChatWallpaperKind.doodle,
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: CustomPaint(painter: WhatsAppDoodleWallpaperPainter()),
                    ),
                    onTap: () async {
                      await ChatWallpaperPrefs.setDoodle();
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _loadWallpaper();
                    },
                  ),
                  for (final c in presets)
                    _wallpaperSwatch(
                      label: null,
                      selected: _wallpaperKind == ChatWallpaperKind.solid && _wallpaperSolid == c,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Color(c),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onTap: () async {
                        await ChatWallpaperPrefs.setSolid(c);
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _loadWallpaper();
                      },
                    ),
                  _wallpaperSwatch(
                    label: 'Gallery',
                    selected: _wallpaperKind == ChatWallpaperKind.image,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A3942),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.photo_library_rounded, color: Color(0xFF00A884)),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _pickChatWallpaper();
                    },
                  ),
                ],
              ),
              if (_wallpaperKind == ChatWallpaperKind.image) ...[
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: () async {
                    await ChatWallpaperPrefs.clearImage();
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadWallpaper();
                  },
                  icon: const Icon(Icons.restore_rounded, color: Color(0xFF8696A0)),
                  label: const Text('Reset to default', style: TextStyle(color: Color(0xFF8696A0))),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _wallpaperSwatch({
    required Widget child,
    required bool selected,
    required VoidCallback onTap,
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? const Color(0xFF00A884) : Colors.white.withValues(alpha: 0.08),
                width: selected ? 2.5 : 1,
              ),
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Color(0xFF8696A0), fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Future<void> _pickChatWallpaper() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked == null) return;
      final path = await ChatWallpaperPrefs.setImageFile(File(picked.path));
      if (!mounted) return;
      setState(() {
        _wallpaperKind = ChatWallpaperKind.image;
        _wallpaperImagePath = path;
      });
    } catch (e) {
      if (mounted) {
        AppToast.show(context, message: 'Could not set wallpaper', type: AppToastType.error);
      }
    }
  }

  Future<void> _loadMyUserId() async {
    final id = int.tryParse(await UserDataService.getUserId());
    if (mounted) setState(() => _myUserId = id);
    _bindCallIfReady();
  }

  void _bindCallIfReady() {
    final id = _myUserId;
    if (id == null || widget.notificationService == null) return;
    CallService.instance.bind(
      notificationService: widget.notificationService!,
      apiService: widget.apiService,
      myUserId: id,
    );
  }

  @override
  void dispose() {
    ChatNotificationRouter.clear();
    _stopTypingSignal();
    _refreshTimer?.cancel();
    _usersPollTimer?.cancel();
    _typingDebounce?.cancel();
    _typingIdle?.cancel();
    _presenceSub?.cancel();
    _typingSub?.cancel();
    _messagesReadSub?.cancel();
    _chatMsgSub?.cancel();
    _reactionSub?.cancel();
    if (AppNavigation.instance.onPendingChatOpen == _consumePendingChatOpen) {
      AppNavigation.instance.onPendingChatOpen = null;
    }
    _callPhaseSub?.cancel();
    _recordTimer?.cancel();
    _recProcess?.kill();
    _voiceRecorder?.dispose();
    _audioPlayer?.dispose();
    _msgController.removeListener(_onComposerChanged);
    _msgController.dispose();
    _msgFocus.dispose();
    _searchController.dispose();
    _scrollController.removeListener(_onChatScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // â”€â”€â”€ Data Loading â”€â”€â”€
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
      _consumePendingChatOpen();
    } else if (mounted) {
      setState(() => _isLoadingUsers = false);
      if (!silent) _showError('Failed to load users');
    }
  }

  void _consumePendingChatOpen() {
    final userId = AppNavigation.instance.pendingChatUserId;
    final groupId = AppNavigation.instance.pendingChatGroupId;
    if (userId == null && groupId == null) return;

    if (userId != null) {
      for (final u in _users) {
        if (u is Map && _asInt(u['id']) == userId) {
          AppNavigation.instance.pendingChatUserId = null;
          unawaited(_selectUser(u));
          return;
        }
      }
      if (_isLoadingUsers) return;
      AppNavigation.instance.pendingChatUserId = null;
      unawaited(_selectUser(<String, dynamic>{
        'id': userId,
        'username': 'user_$userId',
        'full_name': 'Chat',
      }));
      return;
    }

    if (groupId != null) {
      for (final g in _groups) {
        if (g is Map && _asInt(g['id']) == groupId) {
          AppNavigation.instance.pendingChatGroupId = null;
          setState(() => _currentTab = 'group');
          unawaited(_selectGroup(g));
          return;
        }
      }
      if (_isLoadingGroups) {
        if (_groups.isEmpty) unawaited(_loadGroups(silent: true));
        return;
      }
      AppNavigation.instance.pendingChatGroupId = null;
      setState(() => _currentTab = 'group');
      unawaited(_selectGroup(<String, dynamic>{
        'id': groupId,
        'name': 'Group',
      }));
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
    DateTime? dt;
    if (iso is DateTime) {
      dt = iso;
    } else {
      dt = DateTime.tryParse('${iso ?? ''}');
    }
    if (dt == null) return '';
    // Epoch / missing timestamps (shown as 1/1/70) â€” hide instead of showing junk.
    if (dt.year < 2000) return '';
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
    if (_typingPeers.containsKey(key)) return 'typing\u2026';
    final raw = (user['last_message'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    final designation = (user['designation'] ?? '').toString().trim();
    if (designation.isNotEmpty) return designation;
    return 'Tap to chat';
  }

  String _formatLastSeen(dynamic iso) {
    final dt = DateTime.tryParse('${iso ?? ''}');
    if (dt == null) return 'offline';
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'last seen just now';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes} min ago';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'last seen today at $t';
    if (day == today.subtract(const Duration(days: 1))) return 'last seen yesterday at $t';
    return 'last seen ${local.day}/${local.month} at $t';
  }

  void _onRealtimeChatMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    final wsType = data['type']?.toString() ?? 'chat_message';
    final isGroup = wsType == 'group_message' || data['group_id'] != null;

    if (isGroup) {
      final groupId = _asInt(data['group_id']);
      if (groupId == null) return;

      final senderId = _asInt(data['sender_id']);
      final isOwn = _myUserId != null && senderId == _myUserId;
      final text = (data['message'] ?? '').toString();
      if (CallService.isHiddenCallChatMessage(text)) return;

      final preview = text.trim().isEmpty
          ? _chatPreviewText({'last_message': data['message_type']})
          : (text.length > 80 ? '${text.substring(0, 80)}\u2026' : text);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final viewing = _selectedGroup != null && _asInt(_selectedGroup['id']) == groupId;

      setState(() {
        _groups = _groups.map((g) {
          if (g is! Map || _asInt(g['id']) != groupId) return g;
          final map = Map<String, dynamic>.from(g);
          map['last_message'] = preview;
          map['last_message_at'] = nowIso;
          if (!isOwn && !viewing) {
            final n = _asInt(map['unread_count']) ?? 0;
            map['unread_count'] = n + 1;
          }
          return map;
        }).toList();

        if (viewing) {
          final msgId = _eventMessageId(data);
          if (msgId == null) return;
          if (isOwn && _messageExists(msgId)) return;
          final msg = _messageFromRealtimeEvent(data, isOwn: isOwn, fallbackTime: nowIso);
          _messages = _upsertMessage(_messages, msg);
        }
      });

      if (viewing) {
        ChatNotificationRouter.setActiveChat(groupId: groupId);
        _scrollToBottom();
      }
      return;
    }

    final senderId = _asInt(data['sender_id']);
    final receiverId = _asInt(data['receiver_id']);
    final text = (data['message'] ?? '').toString();
    if (CallService.isHiddenCallChatMessage(text)) return;

    final isOwn = _myUserId != null && senderId == _myUserId;
    final peerId = isOwn ? receiverId : senderId;
    if (peerId == null) return;

    final preview = text.trim().isEmpty
        ? _chatPreviewText({'last_message': data['message_type']})
        : (text.length > 80 ? '${text.substring(0, 80)}\u2026' : text);
    final nowIso = DateTime.now().toUtc().toIso8601String();

    setState(() {
      _users = _users.map((u) {
        if (u['id'] != peerId && '${u['id']}' != '$peerId') return u;
        final map = Map<String, dynamic>.from(u as Map);
        map['last_message'] = preview;
        map['last_message_at'] = nowIso;
        if (!isOwn && (_selectedUser == null || _selectedUser['id'] != peerId)) {
          final unread = map['unread_count'];
          final n = unread is int ? unread : int.tryParse('$unread') ?? 0;
          map['unread_count'] = n + 1;
        }
        return map;
      }).toList();
      _users = _sortUsersByRecent(_users);

      final viewing = _selectedUser != null &&
          (_selectedUser['id'] == peerId || '${_selectedUser['id']}' == '$peerId');
      if (viewing) {
        final msgId = _eventMessageId(data);
        if (msgId == null) return;
        if (isOwn && _messageExists(msgId)) return;
        final msg = _messageFromRealtimeEvent(data, isOwn: isOwn, fallbackTime: nowIso);
        _messages = _upsertMessage(_messages, msg);
      }
    });
    if (_selectedUser != null &&
        (_selectedUser['id'] == peerId || '${_selectedUser['id']}' == '$peerId')) {
      ChatNotificationRouter.setActiveChat(peerId: peerId);
      _scrollToBottom();
      if (!isOwn) unawaited(widget.apiService.markMessagesRead(peerId));
    }
  }

  Map<String, dynamic> _messageFromRealtimeEvent(
    Map<String, dynamic> data, {
    required bool isOwn,
    required String fallbackTime,
  }) {
    final msgId = _eventMessageId(data)!;
    final replyRaw = data['reply'];
    Map<String, dynamic>? reply;
    if (replyRaw is Map) {
      reply = Map<String, dynamic>.from(replyRaw);
    }
    return {
      'id': msgId,
      'message': (data['message'] ?? '').toString(),
      'message_type': data['message_type'] ?? 'text',
      'sender_id': _asInt(data['sender_id']),
      'sender_name': data['sender_full_name'] ?? data['sender_name'] ?? data['sender_username'],
      'sender_username': data['sender_username'],
      'is_own': isOwn,
      'is_read': data['is_read'] == true,
      'created_at': data['created_at'] ?? fallbackTime,
      'timestamp': data['created_at'] ?? fallbackTime,
      'image_url': data['image_url'],
      'file_url': data['file_url'],
      'file_name': data['file_name'],
      'voice_url': data['voice_url'],
      'reply_to': _asInt(data['reply_to'] ?? data['reply_to_id']),
      if (reply != null) 'reply': reply,
    };
  }

  void _onRealtimeReaction(Map<String, dynamic> data) {
    if (!mounted) return;
    final chatType = data['chat_type']?.toString() ?? 'direct';
    final msgId = _asInt(data['message_id']);
    if (msgId == null) return;

    if (chatType == 'group') {
      final groupId = _asInt(data['group_id']);
      if (_selectedGroup == null || _asInt(_selectedGroup['id']) != groupId) return;
    } else {
      if (_selectedUser == null) return;
      final peerId = _asInt(_selectedUser['id']);
      final senderId = _asInt(data['sender_id']);
      final receiverId = _asInt(data['receiver_id']);
      if (peerId == null || (senderId != peerId && receiverId != peerId)) return;
    }

    final reactions = data['reactions'];
    setState(() {
      _messages = _messages.map((m) {
        if (m is Map && _messageIdOf(m) == msgId) {
          return {
            ...Map<String, dynamic>.from(m),
            'reactions': reactions is List ? reactions : [],
          };
        }
        return m;
      }).toList();
    });
  }

  Future<void> _toggleReaction(dynamic msg, String emoji) async {
    if (msg is! Map) return;
    final msgId = _messageIdOf(msg);
    if (msgId == null) return;
    final isGroup = _selectedGroup != null;
    final groupId = isGroup ? _asInt(_selectedGroup!['id']) : null;

    final result = await widget.apiService.setMessageReaction(
      msgId,
      emoji,
      isGroup: isGroup,
      groupId: groupId,
    );
    if (!mounted) return;
    if (result['success'] == true && result['data'] is Map) {
      final reactions = (result['data'] as Map)['reactions'];
      setState(() {
        _messages = _messages.map((m) {
          if (m is Map && _messageIdOf(m) == msgId) {
            return {
              ...Map<String, dynamic>.from(m),
              'reactions': reactions is List ? reactions : [],
            };
          }
          return m;
        }).toList();
      });
    } else {
      _showError(result['error']?.toString() ?? 'Could not add reaction');
    }
  }

  Future<void> _showReactionPicker(
    dynamic msg,
    BuildContext anchorContext, {
    bool clearSelectionOnReact = false,
  }) async {
    _reactionPickerClearSelectionOnDismiss = clearSelectionOnReact;
    _reactionPickerAnchor = anchorContext;
    _reactionPickerMsg = msg;
    _reactionPickerShowMore = false;
    _reactionPickerTopLeft = null;
    _reactionPickerAnchorSize = null;
    if (mounted) setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reactionPickerAnchor == null) return;
      final anchorBox =
          _reactionPickerAnchor!.findRenderObject() as RenderBox?;
      final stackBox =
          _chatMessageStackKey.currentContext?.findRenderObject() as RenderBox?;
      if (anchorBox == null || !anchorBox.hasSize || stackBox == null || !stackBox.hasSize) {
        return;
      }
      final globalTopLeft = anchorBox.localToGlobal(Offset.zero);
      final localTopLeft = stackBox.globalToLocal(globalTopLeft);
      setState(() {
        _reactionPickerTopLeft = localTopLeft;
        _reactionPickerAnchorSize = anchorBox.size;
      });
    });
  }

  void _dismissReactionPicker({bool clearSelection = true}) {
    if (_reactionPickerMsg == null) return;
    final shouldClear = clearSelection && _reactionPickerClearSelectionOnDismiss;
    setState(() {
      _reactionPickerMsg = null;
      _reactionPickerAnchor = null;
      _reactionPickerTopLeft = null;
      _reactionPickerAnchorSize = null;
      _reactionPickerShowMore = false;
      _reactionPickerClearSelectionOnDismiss = false;
    });
    if (shouldClear) _clearMessageSelection();
  }

  Widget? _buildReactionPickerLayer(Size layerSize) {
    if (_reactionPickerMsg == null ||
        _reactionPickerTopLeft == null ||
        _reactionPickerAnchorSize == null) {
      return null;
    }
    final msg = _reactionPickerMsg;
    return ChatReactions.pickerLayer(
      anchorTopLeft: _reactionPickerTopLeft!,
      anchorSize: _reactionPickerAnchorSize!,
      layerSize: layerSize,
      extraEmojis: kChatEmojiList,
      showMore: _reactionPickerShowMore,
      onToggleMore: () => setState(() => _reactionPickerShowMore = !_reactionPickerShowMore),
      onDismiss: () => _dismissReactionPicker(),
      onPick: (emoji) {
        unawaited(_toggleReaction(msg, emoji));
        _dismissReactionPicker(clearSelection: _reactionPickerClearSelectionOnDismiss);
      },
    );
  }

  Widget _buildReactionsRow(dynamic msg, {required bool isOwn}) {
    final raw = msg['reactions'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    return ChatReactions.badge(
      reactions: raw,
      isOwn: isOwn,
      onTap: (emoji) => unawaited(_toggleReaction(msg, emoji)),
    );
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
        _selectedUser = {
          ...Map<String, dynamic>.from(_selectedUser as Map),
          'is_online': online,
          if (online) 'last_seen': DateTime.now().toUtc().toIso8601String(),
        };
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
      if (_typingPeers.containsKey(key)) return 'typing\u2026';
      return null;
    }
    if (_selectedGroup != null) {
      final prefix = 'g:${_selectedGroup['id']}:';
      final names = _typingPeers.entries
          .where((e) => e.key.startsWith(prefix))
          .map((e) => e.value)
          .toList();
      if (names.isEmpty) return null;
      if (names.length == 1) return '${names.first} is typing\u2026';
      return '${names.length} people typing\u2026';
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

  Future<void> _loadGroups({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoadingGroups = true);
    final result = await widget.apiService.getChatGroups();
    if (result['success'] == true && mounted) {
      setState(() {
        _groups = result['data'] ?? [];
        if (_selectedGroup != null) {
          final sid = _asInt(_selectedGroup['id']);
          for (final g in _groups) {
            if (g is Map && _asInt(g['id']) == sid) {
              _selectedGroup = Map<String, dynamic>.from(g);
              break;
            }
          }
        }
        _isLoadingGroups = false;
      });
      _consumePendingChatOpen();
    } else if (mounted) {
      setState(() => _isLoadingGroups = false);
      if (!silent) _showError(result['error']?.toString() ?? 'Failed to load groups');
    }
  }

  Future<void> _selectUser(dynamic user, {bool resetQuotes = true, bool openDetails = false}) async {
    _stopTypingSignal();
    final uid = user['id'];
    setState(() {
      _selectedUser = Map<String, dynamic>.from(user as Map);
      _selectedUser['unread_count'] = 0;
      _selectedGroup = null;
      _messages = [];
      _replyTo = null;
      _selectedMessageIds.clear();
      _inChatQuery = '';
      _hasMoreMessages = false;
      _isLoadingMessages = false;
      _isLoadingMoreMessages = false;
      _loadMoreArmed = true;
      if (openDetails) _detailsOpen = true;
      if (resetQuotes) _replyQuotesByMsgId.clear();
      _typingPeers.removeWhere((k, _) => k.startsWith('g:'));
      _users = _users.map((u) {
        if (u is! Map) return u;
        if (u['id'] == uid || '${u['id']}' == '$uid') {
          return {...Map<String, dynamic>.from(u), 'unread_count': 0};
        }
        return u;
      }).toList();
    });
    ChatNotificationRouter.setActiveChat(peerId: _asInt(uid));
    _startRefresh();
    await _loadInitialMessages(scrollToEnd: true);
    unawaited(widget.apiService.markMessagesRead(user['id']));
    if (openDetails && mounted) await _revealDetailsPanel();
  }

  Future<void> _selectGroup(dynamic group, {bool resetQuotes = true, bool openDetails = false}) async {
    _stopTypingSignal();
    final gid = group['id'];
    setState(() {
      _selectedGroup = Map<String, dynamic>.from(group as Map);
      _selectedGroup['unread_count'] = 0;
      _selectedUser = null;
      _messages = [];
      _replyTo = null;
      _selectedMessageIds.clear();
      _inChatQuery = '';
      _hasMoreMessages = false;
      _isLoadingMessages = false;
      _isLoadingMoreMessages = false;
      _loadMoreArmed = true;
      if (openDetails) _detailsOpen = true;
      if (resetQuotes) _replyQuotesByMsgId.clear();
      _typingPeers.removeWhere((k, _) => k.startsWith('u:'));
      _groups = _groups.map((g) {
        if (g is! Map) return g;
        if (g['id'] == gid || '${g['id']}' == '$gid') {
          return {...Map<String, dynamic>.from(g), 'unread_count': 0};
        }
        return g;
      }).toList();
    });
    ChatNotificationRouter.setActiveChat(groupId: _asInt(gid));
    _startRefresh();
    await _loadInitialMessages(scrollToEnd: true);
    if (openDetails && mounted) await _revealDetailsPanel();
  }

  Future<void> _revealDetailsPanel() async {
    if (!_detailsOpen) setState(() => _detailsOpen = true);
    if (_selectedGroup != null) unawaited(_refreshSelectedGroupDetail());
    if (!Responsive.useChatDetailsPane(context)) {
      await _showDetailsSheet();
    }
  }

  Future<void> _toggleDetails() async {
    if (_selectedUser == null && _selectedGroup == null) return;
    if (_detailsOpen && Responsive.useChatDetailsPane(context)) {
      setState(() => _detailsOpen = false);
      return;
    }
    setState(() => _detailsOpen = true);
    if (_selectedGroup != null) unawaited(_refreshSelectedGroupDetail());
    if (!Responsive.useChatDetailsPane(context)) {
      await _showDetailsSheet();
    }
  }

  bool get _groupCanManage => _selectedGroup?['can_manage'] == true;

  Future<void> _refreshSelectedGroupDetail() async {
    final gid = _asInt(_selectedGroup?['id']);
    if (gid == null) return;
    final r = await widget.apiService.getGroupDetail(gid);
    if (!mounted || r['success'] != true || r['data'] is! Map) return;
    _applyGroupUpdate(Map<String, dynamic>.from(r['data'] as Map));
  }

  void _applyGroupUpdate(Map<String, dynamic> data) {
    final gid = _asInt(data['id'] ?? _selectedGroup?['id']);
    if (gid == null) return;
    setState(() {
      if (_selectedGroup != null) {
        _selectedGroup = {
          ...Map<String, dynamic>.from(_selectedGroup as Map),
          ...data,
        };
      }
      _groups = _groups.map((g) {
        if (g is Map && _asInt(g['id']) == gid) {
          return {...Map<String, dynamic>.from(g), ...data};
        }
        return g;
      }).toList();
    });
  }

  Future<void> _promptEditGroupName() async {
    if (!_groupCanManage) {
      _showError('Only group admins can edit this group');
      return;
    }
    final group = _selectedGroup;
    final gid = _asInt(group?['id']);
    if (group == null || gid == null) return;
    final ctrl = TextEditingController(text: group['name']?.toString() ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
        title: const Text('Group name', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Group name',
            hintStyle: TextStyle(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final r = await widget.apiService.updateGroup(gid, name: name);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is Map) {
      _applyGroupUpdate(Map<String, dynamic>.from(r['data'] as Map));
      _showSuccess('Group name updated');
    } else {
      _showError(r['error']?.toString() ?? 'Could not update group');
    }
  }

  Future<void> _promptEditGroupDescription() async {
    if (!_groupCanManage) {
      _showError('Only group admins can edit this group');
      return;
    }
    final group = _selectedGroup;
    final gid = _asInt(group?['id']);
    if (group == null || gid == null) return;
    final ctrl = TextEditingController(text: group['description']?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
        title: const Text('Group description', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Add group description',
            hintStyle: TextStyle(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final r = await widget.apiService.updateGroup(gid, description: ctrl.text.trim());
    if (!mounted) return;
    if (r['success'] == true && r['data'] is Map) {
      _applyGroupUpdate(Map<String, dynamic>.from(r['data'] as Map));
      _showSuccess('Description updated');
    } else {
      _showError(r['error']?.toString() ?? 'Could not update description');
    }
  }

  Future<void> _pickGroupPhoto() async {
    if (!_groupCanManage) {
      _showError('Only group admins can change the group photo');
      return;
    }
    final gid = _asInt(_selectedGroup?['id']);
    if (gid == null) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final r = await widget.apiService.uploadGroupAvatar(
        gid,
        bytes,
        picked.name.isNotEmpty ? picked.name : 'group.jpg',
      );
      if (!mounted) return;
      if (r['success'] == true && r['data'] is Map) {
        _applyGroupUpdate(Map<String, dynamic>.from(r['data'] as Map));
        _showSuccess('Group photo updated');
      } else {
        _showError(r['error']?.toString() ?? 'Could not upload photo');
      }
    } catch (e) {
      _showError('Could not pick image');
    }
  }

  Future<void> _promptAddGroupMembers() async {
    if (!_groupCanManage) {
      _showError('Only group admins can add members');
      return;
    }
    final groupId = _asInt(_selectedGroup?['id']);
    if (groupId == null) return;
    final membersRes = await widget.apiService.getGroupMembers(groupId);
    if (!mounted) return;
    if (membersRes['success'] != true) {
      _showError(membersRes['error']?.toString() ?? 'Could not load members');
      return;
    }
    final raw = membersRes['data'];
    final members = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final memberUserIds = members.map(_membershipUserId).whereType<int>().toSet();
    final available = _users.where((u) {
      if (u is! Map) return false;
      final id = _asInt(u['id']);
      return id != null && !memberUserIds.contains(id);
    }).toList();
    final selectedIds = <int>{};

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: AppTheme.dialogBg,
          title: const Text('Add members', style: TextStyle(color: AppTheme.textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: available.isEmpty
                ? const Text('No available members to add', style: TextStyle(color: AppTheme.textMuted))
                : Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: available.length,
                      itemBuilder: (_, i) {
                        final u = available[i] as Map;
                        final uid = _asInt(u['id']);
                        if (uid == null) return const SizedBox.shrink();
                        return CheckboxListTile(
                          dense: true,
                          value: selectedIds.contains(uid),
                          onChanged: (v) => setDState(() {
                            if (v == true) {
                              selectedIds.add(uid);
                            } else {
                              selectedIds.remove(uid);
                            }
                          }),
                          title: Text(
                            '${u['full_name'] ?? u['username'] ?? 'User'}',
                            style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.85), fontSize: 14),
                          ),
                          activeColor: AppTheme.primary,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (selectedIds.isEmpty) {
                  Navigator.pop(dialogCtx);
                  return;
                }
                final r = await widget.apiService.addGroupMembers(groupId, selectedIds.toList());
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                if (!mounted) return;
                if (r['success'] == true) {
                  _showSuccess('Members added');
                  await _loadGroups(silent: true);
                  await _refreshSelectedGroupDetail();
                } else {
                  _showError(r['error']?.toString() ?? 'Could not add members');
                }
              },
              style: AppTheme.primaryElevatedButton(),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatDetailsPanel({
    ScrollController? scrollController,
    VoidCallback? onClose,
    BuildContext? sheetContext,
  }) {
    void maybePopSheet() {
      if (sheetContext != null && Navigator.canPop(sheetContext)) {
        Navigator.pop(sheetContext);
      }
    }

    final group = _selectedGroup;
    final user = _selectedUser;
    return ChatDetailsPanel(
      isGroup: group != null,
      name: _detailsName,
      subtitle: _detailsSubtitle,
      avatarColor: _avatarColor(_detailsAvatarKey),
      initials: _initials(_detailsName),
      isOnline: _detailsOnline,
      mediaItems: _sharedMediaItems(),
      fileItems: _sharedFileItems(),
      voiceItems: _sharedVoiceItems(),
      username: user?['username']?.toString(),
      email: user?['email']?.toString(),
      designation: user?['designation']?.toString(),
      description: group?['description']?.toString(),
      photoUrl: group != null
          ? group['avatar_url']?.toString()
          : user?['profile_photo_url']?.toString(),
      memberCount: _asInt(group?['member_count']) ?? 0,
      canEdit: group != null && _groupCanManage,
      scrollController: scrollController,
      onClose: onClose ?? () => setState(() => _detailsOpen = false),
      onVideoCall: () {
        maybePopSheet();
        unawaited(_startCall(CallKind.video));
      },
      onVoiceCall: () {
        maybePopSheet();
        unawaited(_startCall(CallKind.audio));
      },
      onAddMembers: group == null
          ? null
          : () {
              maybePopSheet();
              unawaited(_promptAddGroupMembers());
            },
      onOpenMembers: group == null
          ? null
          : () {
              maybePopSheet();
              _showGroupSettings(group);
            },
      onSearchInChat: () {
        maybePopSheet();
        _promptInChatSearch();
      },
      onChangeWallpaper: () {
        maybePopSheet();
        unawaited(_showWallpaperPicker());
      },
      isPinned: () {
        final key = _openChatPinKey();
        return key != null && _isChatPinned(key);
      }(),
      onTogglePin: () {
        final id = group != null ? _asInt(group['id']) : _asInt(user?['id']);
        if (id == null) return;
        maybePopSheet();
        unawaited(_toggleChatPin(
          isGroup: group != null,
          id: id,
          name: _detailsName,
        ));
      },
      onEditName: group == null ? null : () => unawaited(_promptEditGroupName()),
      onEditDescription: group == null ? null : () => unawaited(_promptEditGroupDescription()),
      onChangePhoto: group == null ? null : () => unawaited(_pickGroupPhoto()),
      onOpenMediaUrl: (url) => unawaited(_openSharedMediaUrl(url)),
    );
  }

  Future<void> _showDetailsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.45,
        expand: false,
        builder: (ctx, scroll) => _buildChatDetailsPanel(
          scrollController: scroll,
          onClose: () => Navigator.pop(ctx),
          sheetContext: ctx,
        ),
      ),
    );
    if (mounted && !Responsive.useChatDetailsPane(context)) {
      setState(() => _detailsOpen = false);
    }
  }

  String get _detailsName {
    if (_selectedGroup != null) return (_selectedGroup['name'] ?? 'Group').toString();
    return (_selectedUser?['full_name'] ?? _selectedUser?['username'] ?? 'Chat').toString();
  }

  String get _detailsSubtitle {
    if (_selectedGroup != null) {
      final members = '${_selectedGroup['member_count'] ?? 0} members';
      if (_isPersonalGroup) return '$members Â· personal inbox';
      return members;
    }
    final online = _parseOnline(_selectedUser?['is_online']);
    return online ? 'online' : _formatLastSeen(_selectedUser?['last_seen']);
  }

  bool get _detailsOnline =>
      _selectedGroup == null && _parseOnline(_selectedUser?['is_online']);

  int get _detailsAvatarKey {
    if (_selectedUser != null) return _asInt(_selectedUser['id']) ?? 0;
    return _asInt(_selectedGroup?['id']) ?? 0;
  }

  List<Map<String, dynamic>> _sharedMediaItems() {
    return _messages
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) {
          final url = (m['image_url'] ?? '').toString();
          final type = (m['message_type'] ?? '').toString();
          return url.isNotEmpty || type == 'image';
        })
        .where((m) => (m['image_url'] ?? '').toString().isNotEmpty)
        .toList()
        .reversed
        .toList();
  }

  List<Map<String, dynamic>> _sharedFileItems() {
    return _messages
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => (m['file_url'] ?? '').toString().isNotEmpty)
        .toList()
        .reversed
        .toList();
  }

  List<Map<String, dynamic>> _sharedVoiceItems() {
    return _messages
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => (m['voice_url'] ?? '').toString().isNotEmpty)
        .toList()
        .reversed
        .toList();
  }

  void _promptInChatSearch() {
    final ctrl = TextEditingController(text: _inChatQuery);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
        title: const Text('Search in chat', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: _dialogInputDecor('Type to filter messages\u2026'),
          onSubmitted: (v) {
            setState(() => _inChatQuery = v.trim());
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _inChatQuery = '');
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _inChatQuery = ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  List<dynamic> get _visibleMessages {
    final q = _inChatQuery.trim().toLowerCase();
    if (q.isEmpty) return _messages;
    return _messages.where((m) {
      if (m is! Map) return false;
      final text = (m['message'] ?? '').toString().toLowerCase();
      final type = (m['message_type'] ?? '').toString().toLowerCase();
      final sender = (m['sender_name'] ?? m['sender_username'] ?? '').toString().toLowerCase();
      return text.contains(q) || type.contains(q) || sender.contains(q);
    }).toList();
  }

  Widget _buildDetailsPane() => _buildChatDetailsPanel();

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _silentRefresh());
  }

  int? _oldestLoadedMessageId() {
    for (final m in _messages) {
      if (m is Map) return _messageIdOf(m);
    }
    return null;
  }

  int? _newestLoadedMessageId() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m is Map) return _messageIdOf(m);
    }
    return null;
  }

  Future<void> _loadInitialMessages({bool scrollToEnd = true}) async {
    if (_selectedUser == null && _selectedGroup == null) return;
    if (mounted) {
      setState(() {
        _isLoadingMessages = true;
        _hasMoreMessages = false;
        _loadMoreArmed = true;
      });
    }

    final Map<String, dynamic> r;
    if (_selectedUser != null) {
      r = await widget.apiService.getConversation(
        _selectedUser['id'],
        limit: _chatPageSize,
      );
    } else {
      r = await widget.apiService.getGroupMessages(
        _selectedGroup['id'],
        limit: _chatPageSize,
      );
    }

    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _messages = _hydrateMessages(r['data'] ?? []);
        _hasMoreMessages = r['has_more'] == true;
        _isLoadingMessages = false;
      });
      if (scrollToEnd) _scrollToBottom();
    } else {
      setState(() => _isLoadingMessages = false);
      _showError(r['error']?.toString() ?? 'Failed to load messages');
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingMoreMessages || !_hasMoreMessages) return;
    final beforeId = _oldestLoadedMessageId();
    if (beforeId == null) return;

    final controller = _scrollController;
    final prevMax = controller.hasClients ? controller.position.maxScrollExtent : 0.0;
    final prevOffset = controller.hasClients ? controller.position.pixels : 0.0;

    if (mounted) setState(() => _isLoadingMoreMessages = true);

    final Map<String, dynamic> r;
    if (_selectedUser != null) {
      r = await widget.apiService.getConversation(
        _selectedUser['id'],
        limit: _chatPageSize,
        beforeId: beforeId,
      );
    } else {
      r = await widget.apiService.getGroupMessages(
        _selectedGroup['id'],
        limit: _chatPageSize,
        beforeId: beforeId,
      );
    }

    if (!mounted) return;
    if (r['success'] == true) {
      final older = _hydrateMessages(r['data'] ?? []);
      setState(() {
        _messages = _dedupeMessagesById([...older, ..._messages]);
        _hasMoreMessages = r['has_more'] == true;
        _isLoadingMoreMessages = false;
        _loadMoreArmed = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) return;
        final newMax = controller.position.maxScrollExtent;
        controller.jumpTo(prevOffset + (newMax - prevMax));
      });
    } else {
      setState(() {
        _isLoadingMoreMessages = false;
        _loadMoreArmed = true;
      });
      _showError(r['error']?.toString() ?? 'Could not load older messages');
    }
  }

  Future<void> _silentRefresh() async {
    if (_inMessageSelectionMode || _isLoadingMoreMessages || _isLoadingMessages) return;

    final afterId = _newestLoadedMessageId();
    if (afterId == null) {
      await _loadInitialMessages(scrollToEnd: false);
      return;
    }

    final Map<String, dynamic> r;
    if (_selectedUser != null) {
      r = await widget.apiService.getConversation(
        _selectedUser['id'],
        afterId: afterId,
        limit: 50,
      );
      if (r['success'] == true && mounted) {
        final incoming = _hydrateMessages(r['data'] ?? []);
        if (incoming.isNotEmpty) {
          setState(() {
            for (final msg in incoming) {
              if (msg is Map<String, dynamic>) {
                _messages = _upsertMessage(_messages, msg);
              } else if (msg is Map) {
                _messages = _upsertMessage(_messages, Map<String, dynamic>.from(msg));
              }
            }
          });
        }
        unawaited(widget.apiService.markMessagesRead(_selectedUser['id']));
      }
      return;
    }

    if (_selectedGroup != null) {
      r = await widget.apiService.getGroupMessages(
        _selectedGroup['id'],
        afterId: afterId,
        limit: 50,
      );
      if (r['success'] == true && mounted) {
        final incoming = _hydrateMessages(r['data'] ?? []);
        if (incoming.isNotEmpty) {
          setState(() {
            for (final msg in incoming) {
              if (msg is Map<String, dynamic>) {
                _messages = _upsertMessage(_messages, msg);
              } else if (msg is Map) {
                _messages = _upsertMessage(_messages, Map<String, dynamic>.from(msg));
              }
            }
          });
        }
      }
    }
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse('${v ?? ''}');
  }

  bool _messageExists(int? id) {
    if (id == null) return false;
    return _messages.any((m) => m is Map && _messageIdOf(m) == id);
  }

  int? _messageIdOf(dynamic msg) {
    if (msg is! Map) return null;
    return _asInt(msg['id'] ?? msg['message_id']);
  }

  bool get _inMessageSelectionMode => _selectedMessageIds.isNotEmpty;

  bool _isMessageSelected(dynamic msg) {
    final id = _messageIdOf(msg);
    return id != null && _selectedMessageIds.contains(id);
  }

  List<Map<String, dynamic>> _selectedMessages() {
    return _messages
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) {
          final id = _messageIdOf(m);
          return id != null && _selectedMessageIds.contains(id);
        })
        .toList();
  }

  Map<String, dynamic>? _singleSelectedMessage() {
    if (_selectedMessageIds.length != 1) return null;
    for (final m in _messages) {
      if (m is Map && _selectedMessageIds.contains(_messageIdOf(m))) {
        return Map<String, dynamic>.from(m);
      }
    }
    return null;
  }

  void _clearMessageSelection() {
    if (_selectedMessageIds.isEmpty && _reactionPickerMsg == null) return;
    _dismissReactionPicker(clearSelection: false);
    if (_selectedMessageIds.isEmpty) return;
    setState(() => _selectedMessageIds.clear());
  }

  void _enterMessageSelection(dynamic msg, BuildContext anchorContext) {
    final id = _messageIdOf(msg);
    if (id == null || msg['is_deleted'] == true) return;
    HapticFeedback.mediumImpact();
    setState(() => _selectedMessageIds.add(id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_showReactionPicker(msg, anchorContext, clearSelectionOnReact: true));
    });
  }

  void _toggleMessageSelection(dynamic msg) {
    final id = _messageIdOf(msg);
    if (id == null || msg['is_deleted'] == true) return;
    setState(() {
      if (_selectedMessageIds.contains(id)) {
        _selectedMessageIds.remove(id);
      } else {
        _selectedMessageIds.add(id);
      }
    });
  }

  Map<String, bool> _messageActionFlags(Map<String, dynamic> msg) {
    final isOwn = msg['is_own'] == true;
    final msgType = (msg['message_type'] ?? 'text').toString();
    final text = (msg['message'] ?? '').toString();
    final imageUrl = (msg['image_url'] ?? '').toString();
    final fileUrl = (msg['file_url'] ?? '').toString();
    final voiceUrl = (msg['voice_url'] ?? '').toString();
    final openUrl = imageUrl.isNotEmpty
        ? imageUrl
        : (fileUrl.isNotEmpty ? fileUrl : (voiceUrl.isNotEmpty ? voiceUrl : ''));
    return {
      'canCopy': (text.trim().isNotEmpty && (msgType == 'text' || msgType.isEmpty)) ||
          (msgType == 'image' && imageUrl.isNotEmpty),
      'canForward': text.trim().isNotEmpty || openUrl.isNotEmpty,
      'canEdit': isOwn && (msgType == 'text' || msg['message_type'] == null),
      'canDelete': isOwn,
      'hasImage': imageUrl.isNotEmpty,
      'hasOpenUrl': openUrl.isNotEmpty,
      'isOwn': isOwn,
    };
  }

  int? _eventMessageId(Map<String, dynamic> data) =>
      _asInt(data['message_id'] ?? data['id']);

  List<dynamic> _dedupeMessagesById(List<dynamic> list) {
    final out = <dynamic>[];
    final seen = <int>{};
    for (final item in list) {
      if (item is! Map) {
        out.add(item);
        continue;
      }
      final id = _messageIdOf(item);
      if (id != null) {
        if (seen.contains(id)) continue;
        seen.add(id);
      }
      out.add(item);
    }
    return out;
  }

  List<dynamic> _upsertMessage(List<dynamic> list, Map<String, dynamic> msg) {
    final id = _messageIdOf(msg);
    if (id != null) {
      final idx = list.indexWhere((m) => m is Map && _messageIdOf(m) == id);
      if (idx >= 0) {
        final next = [...list];
        next[idx] = {
          ...Map<String, dynamic>.from(next[idx] as Map),
          ...msg,
          'id': id,
        };
        return _dedupeMessagesById(next);
      }
    }

    // REST response + WebSocket echo race: merge same own message within a short window.
    if (msg['is_own'] == true) {
      final text = (msg['message'] ?? '').toString();
      final replyTo = _asInt(msg['reply_to'] ?? msg['reply_to_id']);
      final msgType = (msg['message_type'] ?? 'text').toString();
      final now = DateTime.now();
      for (var i = list.length - 1; i >= 0 && i >= list.length - 20; i--) {
        final existing = list[i];
        if (existing is! Map || existing['is_own'] != true) continue;
        if ((existing['message_type'] ?? 'text').toString() != msgType) continue;
        if ((existing['message'] ?? '').toString() != text) continue;
        final existingReply = _asInt(existing['reply_to'] ?? existing['reply_to_id']);
        if (replyTo != existingReply) continue;
        final ts = DateTime.tryParse(
          '${existing['created_at'] ?? existing['timestamp'] ?? ''}',
        );
        if (ts != null && now.difference(ts).inSeconds > 30) continue;
        final next = [...list];
        next[i] = {
          ...Map<String, dynamic>.from(existing),
          ...msg,
          if (id != null) 'id': id,
        };
        return _dedupeMessagesById(next);
      }
    }

    return _dedupeMessagesById([...list, msg]);
  }

  void _refocusComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _msgFocus.requestFocus();
    });
  }

  static bool _isImageFileName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (_selectedUser == null && _selectedGroup == null) return;
    if (_isSending) return;
    for (final f in files) {
      final name = f.name.isNotEmpty ? f.name : 'file';
      final path = f.path;
      if (path != null && path.isNotEmpty) {
        if (_isImageFileName(name)) {
          await _sendPickedImagePath(path, name);
        } else {
          await _sendPickedFilePath(path, name);
        }
        continue;
      }
      final bytes = await f.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        _showError('File must be under 10MB');
        continue;
      }
      await _sendPickedBytes(bytes, name);
    }
  }

  Widget _wrapChatFileDropTarget(Widget child) {
    if (!PlatformCapabilities.fileDragDrop) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _chatDragOver = true),
      onDragExited: (_) => setState(() => _chatDragOver = false),
      onDragDone: (details) async {
        setState(() => _chatDragOver = false);
        await _handleDroppedFiles(details.files);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (_chatDragOver)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.14),
                    border: Border.all(color: AppTheme.primaryBright.withValues(alpha: 0.55), width: 2),
                  ),
                  child: const Center(
                    child: Text(
                      'Drop file to send',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Map<String, dynamic> _quoteFromParent(Map<String, dynamic> parent) {
    return {
      'id': parent['id'],
      'sender_name': parent['is_own'] == true
          ? 'You'
          : (parent['sender_name'] ??
              parent['sender_full_name'] ??
              parent['sender_username'] ??
              'User'),
      'preview': _replyPreviewFromMessage(parent),
      'message_type': parent['message_type'] ?? 'text',
    };
  }

  void _cacheReplyQuote(dynamic messageId, Map<String, dynamic> quote) {
    final id = _asInt(messageId);
    if (id == null) return;
    _replyQuotesByMsgId[id] = Map<String, dynamic>.from(quote);
  }

  List<dynamic> _hydrateMessages(List<dynamic> raw) {
    final visible = raw.where((item) {
      if (item is Map) {
        return !CallService.isHiddenCallChatMessage(item['message']?.toString());
      }
      return true;
    }).toList();

    final byId = <int, Map<String, dynamic>>{};
    for (final item in visible) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = _asInt(map['id']);
      if (id != null) byId[id] = map;
    }

    return _dedupeMessagesById(visible.map((item) {
      if (item is! Map) return item;
      final map = Map<String, dynamic>.from(item);
      final mid = _asInt(map['id']);

      Map<String, dynamic>? reply;
      if (map['reply'] is Map) {
        reply = Map<String, dynamic>.from(map['reply'] as Map);
      } else if (mid != null && _replyQuotesByMsgId.containsKey(mid)) {
        reply = Map<String, dynamic>.from(_replyQuotesByMsgId[mid]!);
      } else {
        final parentId = _asInt(map['reply_to'] ?? map['reply_to_id']);
        if (parentId != null && byId.containsKey(parentId)) {
          reply = _quoteFromParent(byId[parentId]!);
        }
      }

      if (reply != null) {
        // Normalize empty preview from API.
        if ((reply['preview'] ?? '').toString().trim().isEmpty) {
          final parentId = _asInt(reply['id'] ?? map['reply_to'] ?? map['reply_to_id']);
          if (parentId != null && byId.containsKey(parentId)) {
            reply = _quoteFromParent(byId[parentId]!);
          }
        }
        map['reply'] = reply;
        map['reply_to'] = map['reply_to'] ?? reply['id'];
        if (mid != null) _cacheReplyQuote(mid, reply);
      }
      return map;
    }).toList());
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    if (_selectedUser == null && _selectedGroup == null) return;

    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    _stopTypingSignal();
    final replySnapshot = _replyTo == null ? null : Map<String, dynamic>.from(_replyTo!);
    final replyId = _replyToId;
    _msgController.clear();
    setState(() {
      _isSending = true;
      _replyTo = null;
      _emojiOpen = false;
    });

    Map<String, dynamic> result;
    if (_selectedUser != null) {
      result = await widget.apiService.sendMessage(_selectedUser['id'], text, replyToId: replyId);
    } else {
      result = await widget.apiService.sendGroupMessage(
        _selectedGroup['id'],
        text,
        replyToId: replyId,
        recipientIds: _personalRecipientIds(replySnapshot),
      );
    }

    if (!mounted) return;
    setState(() => _isSending = false);
    if (result['success'] == true) {
      final payload = result['data'];
      Map<String, dynamic> local;
      if (payload is Map) {
        local = Map<String, dynamic>.from(payload);
        final mid = _asInt(local['id'] ?? local['message_id']);
        if (mid != null) local['id'] = mid;
        local['is_own'] = true;
        local['is_read'] = payload['is_read'] == true;
      } else {
        local = {
          'message': text,
          'is_own': true,
          'is_read': false,
          'message_type': 'text',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
      // Always prefer a usable quote: API reply, else composer snapshot, else parent in thread.
      Map<String, dynamic>? quote;
      if (local['reply'] is Map) {
        quote = Map<String, dynamic>.from(local['reply'] as Map);
      } else if (replySnapshot != null) {
        quote = {
          'id': replySnapshot['id'],
          'sender_name': replySnapshot['sender_name'],
          'preview': replySnapshot['preview'],
          'message_type': replySnapshot['message_type'],
        };
      } else if (replyId != null) {
        for (final m in _messages) {
          if (m is Map && _asInt(m['id']) == replyId) {
            quote = _quoteFromParent(Map<String, dynamic>.from(m));
            break;
          }
        }
      }
      if (quote != null) {
        local['reply'] = quote;
        local['reply_to'] = replyId ?? quote['id'];
        _cacheReplyQuote(local['id'], quote);
      }
      setState(() => _messages = _upsertMessage(_messages, local));
      _scrollToBottom();
      _refocusComposer();
    } else {
      _msgController.text = text;
      _msgController.selection = TextSelection.collapsed(offset: text.length);
      if (replySnapshot != null) setState(() => _replyTo = replySnapshot);
      _showError(result['error']?.toString() ?? 'Failed to send message');
    }
  }

  bool get _hasDraft => _msgController.text.trim().isNotEmpty;
  bool get _canSend => _hasDraft;

  int? get _replyToId {
    final raw = _replyTo?['id'];
    if (raw is int) return raw;
    return int.tryParse('${raw ?? ''}');
  }

  void _setReplyTo(dynamic msg) {
    if (msg == null) return;
    final map = Map<String, dynamic>.from(msg as Map);
    final id = map['id'];
    if (id == null) {
      _showError('Cannot reply to this message');
      return;
    }
    final preview = _replyPreviewFromMessage(map);
    setState(() {
      _emojiOpen = false;
      _replyTo = {
        'id': id,
        'sender_id': map['sender_id'] ?? map['sender'],
        'sender_name': map['is_own'] == true
            ? 'You'
            : (map['sender_name'] ??
                map['sender_full_name'] ??
                map['sender_username'] ??
                'User'),
        'preview': preview,
        'message_type': map['message_type'] ?? 'text',
      };
    });
    _msgFocus.requestFocus();
  }

  void _insertTextAtCursor(String text) {
    if (text.isEmpty) return;
    final ctrl = _msgController;
    final value = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.start >= 0 ? sel.start : value.length;
    final end = sel.end >= 0 ? sel.end : value.length;
    final next = value.replaceRange(start, end, text);
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  Future<void> _previewAndSendImage(Uint8List bytes, String filename) async {
    if (_selectedUser == null && _selectedGroup == null) return;
    if (bytes.length > 10 * 1024 * 1024) {
      _showError('Image must be under 10MB');
      return;
    }
    final result = await ChatImageSendPreview.open(
      context,
      imageBytes: bytes,
      recipientName: _detailsName,
    );
    if (result == null || !mounted) return;
    final name = filename.trim().isNotEmpty ? filename : InAppImageClipboard.filename;
    await _sendImageBytes(result.bytes, name, caption: result.caption);
  }

  Future<void> _stagePastedImage(Uint8List bytes, {String filename = 'pasted.jpg'}) async {
    _lastCopiedImageBytes = bytes;
    InAppImageClipboard.store(bytes, name: filename);
    setState(() => _emojiOpen = false);
    await _previewAndSendImage(bytes, filename);
  }

  Future<void> _pasteFromClipboard() async {
    if (_selectedUser == null && _selectedGroup == null) return;
    final image = await ChatClipboard.readImage(fallback: _lastCopiedImageBytes);
    if (image != null) {
      final name = InAppImageClipboard.filename != 'image.jpg'
          ? InAppImageClipboard.filename
          : 'pasted_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _stagePastedImage(image, filename: name);
      return;
    }
    final text = await ChatClipboard.readText();
    if (text != null) {
      _insertTextAtCursor(text);
    } else if (mounted) {
      final hasImage = await ChatClipboard.hasImage();
      AppToast.info(
        context,
        hasImage ? 'Could not read copied image — try again' : 'Nothing to paste',
      );
    }
  }

  Future<void> _copyMessageContent(Map<String, dynamic> msg) async {
    final msgType = (msg['message_type'] ?? 'text').toString();
    final text = (msg['message'] ?? '').toString();
    final imageUrl = (msg['image_url'] ?? '').toString();
    if (msgType == 'image' && imageUrl.isNotEmpty) {
      final bytes = await widget.apiService.downloadAuthedBytes(imageUrl) ??
          await ChatClipboard.downloadImageBytes(imageUrl);
      if (bytes != null && bytes.isNotEmpty) {
        _lastCopiedImageBytes = bytes;
        InAppImageClipboard.store(bytes, name: 'chat_image.jpg');
        final ok = await ChatClipboard.writeImage(bytes);
        if (mounted) {
          if (ok) {
            _showSuccess('Image copied — tap Paste to send');
          } else {
            _showSuccess('Image ready — tap Paste in chat');
          }
        }
        return;
      }
      if (mounted) _showError('Could not copy image');
      return;
    }
    if (text.trim().isEmpty) return;
    await ChatClipboard.writeText(text);
    if (mounted) _showSuccess('Copied');
  }

  List<Map<String, dynamic>> _chatImageMessages() {
    return _messages
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) {
          if (m['is_deleted'] == true) return false;
          return (m['image_url'] ?? '').toString().trim().isNotEmpty;
        })
        .toList();
  }

  Future<void> _openChatImageViewer(Map msg, {String? preferUrl}) async {
    final images = _chatImageMessages();
    if (images.isEmpty) {
      final url = preferUrl ?? (msg['image_url'] ?? '').toString();
      if (url.isNotEmpty) await _openFileUrl(url);
      return;
    }
    var initial = images.indexWhere((m) => _asInt(m['id']) == _asInt(msg['id']));
    if (initial < 0 && preferUrl != null && preferUrl.isNotEmpty) {
      initial = images.indexWhere((m) => (m['image_url'] ?? '').toString() == preferUrl);
    }
    if (initial < 0) initial = 0;

    await ChatImageViewer.open(
      context,
      images: images,
      initialIndex: initial,
      onReply: (m) async => _setReplyTo(m),
      onForward: (m) async => _forwardMessage(m),
      onDelete: (m) async => _deleteMessage(m),
      onInfo: (m) => _showMessageInfo(m),
      onOpenExternal: (url) => _openFileUrl(url),
    );
  }

  Future<void> _openSharedMediaUrl(String url) async {
    final images = _chatImageMessages();
    final idx = images.indexWhere((m) => (m['image_url'] ?? '').toString() == url);
    if (idx >= 0) {
      await _openChatImageViewer(images[idx], preferUrl: url);
      return;
    }
    await openChatMediaUrl(url);
  }

  void _toggleEmojiPanel() {
    if (_isSending) return;
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      _msgFocus.requestFocus();
      return;
    }
    // Remember keyboard height, then replace keyboard with emoji panel.
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > 120) _emojiPanelHeight = inset;
    _msgFocus.unfocus();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      setState(() => _emojiOpen = true);
    });
  }

  void _insertEmoji(String emoji) {
    final t = _msgController.text;
    final sel = _msgController.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    final next = t.replaceRange(start, end, emoji);
    _msgController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    setState(() {});
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
    return text.length > 100 ? '${text.substring(0, 100)}\u2026' : text;
  }

  Future<void> _startCall(CallKind kind) async {
    if (_selectedUser == null || !PlatformCapabilities.voiceVideoCall) return;
    if (CallService.instance.isInCall) {
      _showError('Already in a call');
      return;
    }
    final peerId = _selectedUser['id'] is int
        ? _selectedUser['id'] as int
        : int.tryParse('${_selectedUser['id']}');
    if (peerId == null) return;

    final name = _selectedUser['full_name']?.toString().trim().isNotEmpty == true
        ? _selectedUser['full_name'].toString()
        : (_selectedUser['username']?.toString() ?? 'Contact');

    if (widget.notificationService == null) {
      _showError('Call service unavailable');
      return;
    }
    if (_myUserId == null) await _loadMyUserId();
    if (_myUserId == null) {
      _showError('Could not start call');
      return;
    }
    CallService.instance.bind(
      notificationService: widget.notificationService!,
      apiService: widget.apiService,
      myUserId: _myUserId!,
    );

    final err = await CallService.instance.startOutgoing(
      peerId: peerId,
      peerName: name,
      kind: kind,
    );
    if (err != null) {
      _showError(err);
      return;
    }
    if (!mounted) return;
    await CallNavigation.openCallPageIfNeeded();
  }

  // â”€â”€â”€ Voice recording (Android/iOS: record package, Windows: PowerShell) â”€â”€â”€
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

  // â”€â”€â”€ Attach (WhatsApp paperclip sheet) â”€â”€â”€
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
                        icon: Icons.content_paste_rounded,
                        label: 'Paste',
                        color: const Color(0xFF00A884),
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(_pasteFromClipboard());
                        },
                      ),
                    ),
                  if (mobile) const SizedBox(width: 10),
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
                      label: mobile ? 'Gallery' : 'Photo',
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

  Future<void> _sendImageBytes(List<int> bytes, String name, {String caption = ''}) async {
    if (_selectedUser == null && _selectedGroup == null) return;
    if (bytes.length > 10 * 1024 * 1024) {
      _showError('Image must be under 10MB');
      return;
    }
    final replySnapshot = _replyTo == null ? null : Map<String, dynamic>.from(_replyTo!);
    final replyId = _replyToId;
    setState(() {
      _isSending = true;
      _replyTo = null;
      _emojiOpen = false;
    });
    final filename = name.isNotEmpty ? name : 'photo.jpg';
    Map<String, dynamic> r;
    if (_selectedUser != null) {
      r = await widget.apiService.sendImageMessage(
        _selectedUser['id'],
        bytes,
        filename,
        message: caption,
        replyToId: replyId,
      );
    } else {
      r = await widget.apiService.sendGroupImageMessage(
        _selectedGroup['id'],
        bytes,
        filename,
        message: caption,
        replyToId: replyId,
        recipientIds: _personalRecipientIds(replySnapshot),
      );
    }
    if (!mounted) return;
    setState(() => _isSending = false);
    if (r['success'] == true) {
      final payload = r['data'];
      if (payload is Map) {
        final local = Map<String, dynamic>.from(payload);
        local['is_own'] = true;
        if (replySnapshot != null) {
          _cacheReplyQuote(local['id'], {
            'id': replySnapshot['id'],
            'sender_name': replySnapshot['sender_name'],
            'preview': replySnapshot['preview'],
            'message_type': replySnapshot['message_type'],
          });
          local['reply'] = {
            'id': replySnapshot['id'],
            'sender_name': replySnapshot['sender_name'],
            'preview': replySnapshot['preview'],
            'message_type': replySnapshot['message_type'],
          };
        }
        setState(() => _messages = _upsertMessage(_messages, local));
        _scrollToBottom();
        _refocusComposer();
      } else {
        _refreshMessages();
      }
    } else {
      if (replySnapshot != null) setState(() => _replyTo = replySnapshot);
      _showError(r['error']?.toString() ?? 'Failed to send image');
    }
  }

  Future<void> _sendPickedImagePath(String path, String name) async {
    if (_selectedUser == null && _selectedGroup == null) return;
    final file = File(path);
    if (!await file.exists()) {
      _showError('Could not read image');
      return;
    }
    final bytes = await file.readAsBytes();
    await _previewAndSendImage(bytes, name.isNotEmpty ? name : 'photo.jpg');
  }

  Future<void> _sendPickedFilePath(String path, String name) async {
    if (_selectedUser == null && _selectedGroup == null) return;
    final file = File(path);
    if (!await file.exists()) {
      _showError('Could not read file');
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      _showError('File must be under 10MB');
      return;
    }
    await _sendPickedBytes(bytes, name);
  }

  Future<void> _sendPickedBytes(List<int> bytes, String name) async {
    if (_selectedUser == null && _selectedGroup == null) return;
    final replySnapshot = _replyTo == null ? null : Map<String, dynamic>.from(_replyTo!);
    final replyId = _replyToId;
    setState(() {
      _isSending = true;
      _replyTo = null;
    });
    Map<String, dynamic> r;
    if (_selectedUser != null) {
      r = await widget.apiService.sendFileMessage(
        _selectedUser['id'],
        bytes,
        name,
        replyToId: replyId,
      );
    } else {
      r = await widget.apiService.sendGroupFileMessage(
        _selectedGroup['id'],
        bytes,
        name,
        replyToId: replyId,
        recipientIds: _personalRecipientIds(replySnapshot),
      );
    }
    if (!mounted) return;
    setState(() => _isSending = false);
    if (r['success'] == true) {
      final payload = r['data'];
      if (payload is Map && replySnapshot != null) {
        _cacheReplyQuote(payload['id'], {
          'id': replySnapshot['id'],
          'sender_name': replySnapshot['sender_name'],
          'preview': replySnapshot['preview'],
          'message_type': replySnapshot['message_type'],
        });
      }
      _refreshMessages();
    } else {
      if (replySnapshot != null) setState(() => _replyTo = replySnapshot);
      _showError(r['error']?.toString() ?? 'Failed to send file');
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
    await _sendPickedFilePath(pf.path!, pf.name);
  }

  // â”€â”€â”€ Play Voice â”€â”€â”€
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
    unawaited(_loadInitialMessages(scrollToEnd: false));
  }

  Widget _buildLoadOlderHeader() {
    if (_isLoadingMessages) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBright)),
      );
    }
    if (!_hasMoreMessages) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Center(
        child: _isLoadingMoreMessages
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBright),
              )
            : TextButton.icon(
                onPressed: () => unawaited(_loadOlderMessages()),
                icon: const Icon(Icons.expand_less_rounded, size: 18, color: AppTheme.primaryBright),
                label: const Text(
                  'Load earlier messages',
                  style: TextStyle(color: AppTheme.primaryBright, fontSize: 13),
                ),
              ),
      ),
    );
  }

  Future<void> _createGroup(
    String name,
    String desc,
    List<int> memberIds, {
    String visibilityMode = 'shared',
  }) async {
    final result = await widget.apiService.createGroup(
      name,
      desc,
      memberIds,
      visibilityMode: visibilityMode,
    );
    if (result['success'] == true) {
      _loadGroups();
      _showSuccess('Group created');
    } else {
      _showError(result['error']?.toString() ?? 'Failed to create group');
    }
  }

  /// Personal groups: reply targets the other person so only they (+ admins) see it.
  List<int>? _personalRecipientIds(Map<String, dynamic>? replySnapshot) {
    final mode =
        (_selectedGroup is Map ? _selectedGroup['visibility_mode'] : null)?.toString() ??
            'shared';
    if (mode != 'personal') return null;
    final replySender = _chatInt(
      replySnapshot?['sender_id'] ?? replySnapshot?['sender'],
    );
    if (replySender != null && replySender != _myUserId) {
      return [replySender];
    }
    return null;
  }

  bool get _isPersonalGroup =>
      (_selectedGroup is Map ? _selectedGroup['visibility_mode'] : null)?.toString() ==
      'personal';

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

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  /// Logo â†’ dashboard (home tab). Used when immersive chrome hides the main top bar.
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
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  @override
  Widget build(BuildContext context) {
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalW = constraints.maxWidth;
            final isWide = Responsive.useChatSplit(context);
            final hasChat = _selectedUser != null || _selectedGroup != null;
            if (!isWide) {
              return hasChat ? _buildChatArea() : _buildSidebar();
            }

            final showDetails = hasChat &&
                _detailsOpen &&
                totalW >= Responsive.chatDetailsMinWidth;
            final detailsW = showDetails
                ? Responsive.chatDetailsPaneWidthFor(totalW)
                : 0.0;
            final listW = Responsive.chatListPaneWidthFor(totalW, reserved: detailsW);
            // Keep chat pane from collapsing under list + details.
            final minChat = 280.0;
            final cappedList = listW.clamp(
              200.0,
              (totalW - detailsW - minChat - 2).clamp(200.0, listW),
            );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: cappedList,
                  child: ClipRect(child: _buildSidebar()),
                ),
                Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
                Expanded(
                  child: hasChat ? _buildChatArea() : _buildEmptyState(),
                ),
                if (showDetails) ...[
                  Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
                  SizedBox(
                    width: detailsW,
                    child: ClipRect(child: _buildDetailsPane()),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // â”€â”€â”€ LEFT SIDEBAR (WhatsApp-style unified inbox) â”€â”€â”€
  Widget _buildSidebar() {
    final immersive = PlatformCapabilities.immersiveChatChrome;
    // Sidebar-local padding â€” never use full-window pagePadding (that squeezes search).
    const sidePad = 12.0;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            immersive ? 4 : sidePad,
            immersive ? 4 : 8,
            immersive ? 4 : 8,
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
              const Expanded(
                child: Text(
                  'Chats',
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'New group',
                onPressed: _showCreateGroupDialog,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.group_add_rounded, color: AppTheme.primaryBright, size: 22),
              ),
              if (immersive) _dashboardLogoButton(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(sidePad, 4, sidePad, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search\u2026',
              hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.75), fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMuted.withValues(alpha: 0.9), size: 20),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              isDense: true,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.07),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.45)),
              ),
            ),
          ),
        ),
        Expanded(child: _buildInboxList()),
      ],
    );
  }

  List<Map<String, dynamic>> _inboxRows() {
    final rows = <Map<String, dynamic>>[];
    for (final u in _users) {
      if (u is! Map) continue;
      final name = (u['full_name'] ?? u['username'] ?? 'User').toString();
      if (_searchQuery.isNotEmpty && !name.toLowerCase().contains(_searchQuery)) continue;
      final unread = u['unread_count'];
      final id = _asInt(u['id']) ?? 0;
      rows.add({
        'kind': 'user',
        'data': u,
        'name': name,
        'unread': unread is int ? unread : int.tryParse('$unread') ?? 0,
        'at': DateTime.tryParse('${u['last_message_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        'pinKey': ChatPinPrefs.chatKey(isGroup: false, id: id),
      });
    }
    for (final g in _groups) {
      if (g is! Map) continue;
      final name = (g['name'] ?? 'Group').toString();
      if (_searchQuery.isNotEmpty && !name.toLowerCase().contains(_searchQuery)) continue;
      final unread = g['unread_count'];
      final id = _asInt(g['id']) ?? 0;
      rows.add({
        'kind': 'group',
        'data': g,
        'name': name,
        'unread': unread is int ? unread : int.tryParse('$unread') ?? 0,
        'at': DateTime.tryParse('${g['last_message_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        'pinKey': ChatPinPrefs.chatKey(isGroup: true, id: id),
      });
    }
    rows.sort((a, b) {
      final pinA = _pinnedChatKeys.indexOf(a['pinKey'] as String);
      final pinB = _pinnedChatKeys.indexOf(b['pinKey'] as String);
      final aPinned = pinA >= 0;
      final bPinned = pinB >= 0;
      if (aPinned && bPinned) return pinA.compareTo(pinB);
      if (aPinned) return -1;
      if (bPinned) return 1;
      return (b['at'] as DateTime).compareTo(a['at'] as DateTime);
    });
    return rows;
  }

  Widget _buildInboxList() {
    if (_isLoadingUsers && _users.isEmpty) return _buildLoader('Loading chats...');
    final rows = _inboxRows();
    if (rows.isEmpty) return _buildEmpty('No chats yet');
    final immersive = PlatformCapabilities.immersiveChatChrome;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(immersive ? 4 : 8, 0, immersive ? 4 : 8, 8),
      itemCount: rows.length,
      separatorBuilder: (_, i) => Divider(
        height: 1,
        indent: 76,
        color: Colors.white.withValues(alpha: 0.06),
      ),
      itemBuilder: (_, i) {
        final row = rows[i];
        final isGroup = row['kind'] == 'group';
        final data = row['data'] as Map;
        final name = row['name'] as String;
        final unread = row['unread'] as int;
        final id = isGroup
            ? (_asInt(data['id']) ?? 0)
            : (_asInt(data['id']) ?? 0);
        final isSelected = isGroup
            ? (_selectedGroup != null && _asInt(_selectedGroup['id']) == id)
            : (_selectedUser != null && _asInt(_selectedUser['id']) == id);
        final isOnline = !isGroup && _parseOnline(data['is_online']);
        final typingKey = isGroup ? 'g:$id' : 'u:$id';
        final isTyping = isGroup
            ? _typingPeers.keys.any((k) => k == 'g:$id' || k.startsWith('g:$id:'))
            : _typingPeers.containsKey(typingKey);
        final preview = isTyping
            ? 'typing\u2026'
            : (isGroup
                ? ((data['last_message'] ?? '').toString().trim().isEmpty
                    ? '${data['member_count'] ?? 0} members'
                    : data['last_message'].toString())
                : _chatPreviewText(Map<String, dynamic>.from(data)));
        final timeLabel = _formatChatListTime(data['last_message_at']);
        final pinKey = row['pinKey'] as String;
        final isPinned = _isChatPinned(pinKey);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => isGroup ? _selectGroup(data) : _selectUser(data),
            onLongPress: () => unawaited(_showInboxChatOptions(
              isGroup: isGroup,
              id: id,
              name: name,
            )),
            onSecondaryTap: () => unawaited(_showInboxChatOptions(
              isGroup: isGroup,
              id: id,
              name: name,
            )),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              color: isSelected ? AppTheme.primary.withValues(alpha: 0.14) : Colors.transparent,
              child: Row(
                children: [
                  ChatAvatar(
                    photoUrl: isGroup
                        ? data['avatar_url']?.toString()
                        : data['profile_photo_url']?.toString(),
                    name: name,
                    initials: _initials(name),
                    backgroundColor: isGroup ? AppTheme.primary : _avatarColor(id),
                    isGroup: isGroup,
                    radius: 20,
                    showOnlineIndicator: !isGroup,
                    isOnline: isOnline,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (timeLabel.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              if (isPinned) ...[
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 14,
                                  color: AppTheme.textMuted.withValues(alpha: 0.85),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                timeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: unread > 0 ? AppTheme.accent : AppTheme.textMuted,
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
                                  color: isTyping
                                      ? AppTheme.accent
                                      : unread > 0
                                          ? AppTheme.textPrimary.withValues(alpha: 0.88)
                                          : AppTheme.textMuted,
                                  fontWeight: isTyping || unread > 0 ? FontWeight.w500 : FontWeight.w400,
                                  fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                                ),
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                decoration: const BoxDecoration(
                                  color: AppTheme.accent,
                                  borderRadius: BorderRadius.all(Radius.circular(9)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  unread > 99 ? '99+' : '$unread',
                                  style: const TextStyle(
                                    color: Color(0xFF0A1628),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Details',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      if (isGroup) {
                        unawaited(_selectGroup(data, openDetails: true));
                      } else {
                        unawaited(_selectUser(data, openDetails: true));
                      }
                    },
                    icon: Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: isSelected ? AppTheme.primaryBright : AppTheme.textMuted,
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

  // â”€â”€â”€ Users List â”€â”€â”€
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
                  ChatAvatar(
                    photoUrl: user['profile_photo_url']?.toString(),
                    name: name,
                    initials: _initials(name),
                    backgroundColor: _avatarColor(uid),
                    radius: immersive ? 24 : 20,
                    showOnlineIndicator: true,
                    isOnline: isOnline,
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

  // â”€â”€â”€ Groups List â”€â”€â”€
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
                        final isPersonal = (group['visibility_mode'] ?? '').toString() == 'personal';
                        final preview = (group['last_message'] ?? '').toString().trim();
                        final subtitle = preview.isNotEmpty
                            ? preview
                            : (isPersonal ? '$members members Â· personal' : '$members members');
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
                                ChatAvatar(
                                  photoUrl: group['avatar_url']?.toString(),
                                  name: name,
                                  initials: name.length >= 2
                                      ? name.substring(0, 2).toUpperCase()
                                      : name.toUpperCase(),
                                  backgroundColor: AppTheme.primary,
                                  isGroup: true,
                                  radius: 20,
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

  // â”€â”€â”€ Chat Area (Right Side) â”€â”€â”€
  Widget _buildChatArea() {
    final isWide = Responsive.useChatSplit(context);
    final isGroup = _selectedGroup != null;
    final name = isGroup
        ? (_selectedGroup['name'] ?? 'Group')
        : (_selectedUser['full_name'] ?? _selectedUser['username'] ?? 'Chat');
    final isOnline = !isGroup && _parseOnline(_selectedUser?['is_online']);
    final typingLabel = _activeTypingLabel();
    final subtitle = typingLabel ??
        (isGroup
            ? (_isPersonalGroup
                ? '${_selectedGroup['member_count'] ?? 0} members Â· personal inbox'
                : '${_selectedGroup['member_count'] ?? 0} members')
            : (isOnline ? 'online' : _formatLastSeen(_selectedUser?['last_seen'])));
    final subtitleColor = typingLabel != null
        ? const Color(0xFF34D399)
        : (isOnline ? const Color(0xFF34D399) : AppTheme.textMuted);
    final headerUid = !isGroup && _selectedUser != null
        ? (_selectedUser['id'] is int ? _selectedUser['id'] as int : int.tryParse('${_selectedUser['id']}') ?? 0)
        : 0;
    final openPinKey = _openChatPinKey();
    final chatPinned = openPinKey != null && _isChatPinned(openPinKey);
    final chatPinId = isGroup ? _asInt(_selectedGroup['id']) : _asInt(_selectedUser['id']);

    return PopScope(
      canPop: !_inMessageSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _clearMessageSelection();
      },
      child: _wrapChatFileDropTarget(Column(
      children: [
        LayoutBuilder(
          builder: (context, headerConstraints) {
            final headerW = headerConstraints.maxWidth;
            final compact = headerW < 420;
            final veryCompact = headerW < 340;
            if (_inMessageSelectionMode) {
              return _buildMessageSelectionHeader(compact: compact, isWide: isWide);
            }
            final avatarSize = compact ? 36.0 : 44.0;
            final showCalls = !isGroup &&
                PlatformCapabilities.voiceVideoCall &&
                !veryCompact;
            final showLogo = PlatformCapabilities.immersiveChatChrome && !compact;
            final showSettings = isGroup && !veryCompact;

            return Container(
              height: PlatformCapabilities.immersiveChatChrome ? 66 : 74,
              padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 6),
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
                        if (_inMessageSelectionMode) {
                          _clearMessageSelection();
                          return;
                        }
                        _stopTypingSignal();
                        ChatNotificationRouter.clearActiveThread();
                        setState(() {
                          _selectedUser = null;
                          _selectedGroup = null;
                          _replyTo = null;
                          _emojiOpen = false;
                          _detailsOpen = false;
                          _inChatQuery = '';
                          _refreshTimer?.cancel();
                        });
                      },
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
                    ),
                  Expanded(
                    child: InkWell(
                      onTap: () => unawaited(_toggleDetails()),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: Row(
                          children: [
                            ChatAvatar(
                              photoUrl: isGroup
                                  ? _selectedGroup!['avatar_url']?.toString()
                                  : _selectedUser!['profile_photo_url']?.toString(),
                              name: name,
                              initials: _initials(name),
                              backgroundColor: isGroup ? AppTheme.primary : _avatarColor(headerUid),
                              isGroup: isGroup,
                              radius: avatarSize / 2,
                              showOnlineIndicator: !isGroup,
                              isOnline: isOnline,
                              onlineIndicatorSize: 13,
                              onlineBorderColor: const Color(0xFF0B1220),
                            ),
                            SizedBox(width: compact ? 8 : 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: compact ? 15 : 16.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: -0.2,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: compact ? 11.5 : 12.5,
                                      fontWeight: typingLabel != null ? FontWeight.w600 : FontWeight.w400,
                                      fontStyle: typingLabel != null ? FontStyle.italic : FontStyle.normal,
                                      color: subtitleColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (showCalls) ...[
                    IconButton(
                      tooltip: 'Video call',
                      onPressed: _selectedUser == null ? null : () => _startCall(CallKind.video),
                      icon: const Icon(Icons.videocam_rounded, color: Color(0xFFE9EDEF), size: 24),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: 'Voice call',
                      onPressed: _selectedUser == null ? null : () => _startCall(CallKind.audio),
                      icon: const Icon(Icons.call_rounded, color: Color(0xFFE9EDEF), size: 22),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  if (!veryCompact && chatPinId != null)
                    IconButton(
                      tooltip: chatPinned ? 'Unpin chat' : 'Pin chat',
                      onPressed: () => unawaited(_toggleChatPin(
                        isGroup: isGroup,
                        id: chatPinId,
                        name: name.toString(),
                      )),
                      icon: Icon(
                        chatPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        color: chatPinned ? AppTheme.primaryBright : const Color(0xFFE9EDEF),
                        size: 22,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    tooltip: 'Wallpaper',
                    onPressed: () => unawaited(_showWallpaperPicker()),
                    icon: const Icon(Icons.wallpaper_rounded, color: Color(0xFFE9EDEF), size: 22),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: 'Search in chat',
                    onPressed: _promptInChatSearch,
                    icon: const Icon(Icons.search_rounded, color: Color(0xFFE9EDEF), size: 22),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: 'Contact info',
                    onPressed: () => unawaited(_toggleDetails()),
                    icon: Icon(
                      _detailsOpen ? Icons.info_rounded : Icons.info_outline_rounded,
                      color: _detailsOpen ? AppTheme.primaryBright : const Color(0xFFE9EDEF),
                      size: 22,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (showSettings)
                    IconButton(
                      tooltip: 'Group settings',
                      onPressed: () => _showGroupSettings(_selectedGroup),
                      icon: const Icon(Icons.settings_outlined, color: AppTheme.textMuted, size: 22),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (showLogo) _dashboardLogoButton(),
                  if (veryCompact && (isGroup || (!isGroup && PlatformCapabilities.voiceVideoCall)))
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert_rounded, color: Color(0xFFE9EDEF), size: 22),
                      color: AppTheme.surface2,
                      onSelected: (v) {
                        if (v == 'settings') _showGroupSettings(_selectedGroup);
                        if (v == 'video') _startCall(CallKind.video);
                        if (v == 'audio') _startCall(CallKind.audio);
                        if (v == 'wallpaper') unawaited(_showWallpaperPicker());
                        if (v == 'pin' && chatPinId != null) {
                          unawaited(_toggleChatPin(
                            isGroup: isGroup,
                            id: chatPinId,
                            name: name.toString(),
                          ));
                        }
                      },
                      itemBuilder: (_) => [
                        if (chatPinId != null)
                          PopupMenuItem(
                            value: 'pin',
                            child: Text(chatPinned ? 'Unpin chat' : 'Pin chat'),
                          ),
                        const PopupMenuItem(value: 'wallpaper', child: Text('Wallpaper')),
                        if (!isGroup && PlatformCapabilities.voiceVideoCall) ...[
                          const PopupMenuItem(value: 'video', child: Text('Video call')),
                          const PopupMenuItem(value: 'audio', child: Text('Voice call')),
                        ],
                        if (isGroup)
                          const PopupMenuItem(value: 'settings', child: Text('Group settings')),
                      ],
                    ),
                ],
              ),
            );
          },
        ),

        Expanded(
          child: Stack(
            key: _chatMessageStackKey,
            fit: StackFit.expand,
            children: [
              ChatWallpaperBackground(
                kind: _wallpaperKind,
                solidColor: _wallpaperSolid,
                imagePath: _wallpaperImagePath,
              ),
              Column(
                  children: [
                    if (_inChatQuery.isNotEmpty)
                      Material(
                        color: const Color(0xFF1F2C34),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.search_rounded, color: AppTheme.primaryBright, size: 20),
                          title: Text(
                            'Filter: $_inChatQuery',
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                          ),
                          trailing: IconButton(
                            tooltip: 'Clear',
                            onPressed: () => setState(() => _inChatQuery = ''),
                            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 18),
                          ),
                        ),
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _chatThreadWidth = constraints.maxWidth;
                          final picker = _buildReactionPickerLayer(constraints.biggest);
                          if (_visibleMessages.isEmpty && !_isLoadingMessages) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildEmpty(_inChatQuery.isNotEmpty
                                    ? 'No messages match\n"\u201C$_inChatQuery\u201D"'
                                    : 'No messages yet\nStart the conversation!'),
                                if (picker != null) picker,
                              ],
                            );
                          }
                          final showLoadHeader = _hasMoreMessages || _isLoadingMoreMessages || _isLoadingMessages;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                                itemCount: _visibleMessages.length + (showLoadHeader ? 1 : 0),
                                itemBuilder: (_, i) {
                                  if (showLoadHeader && i == 0) return _buildLoadOlderHeader();
                                  final idx = i - (showLoadHeader ? 1 : 0);
                                  return _buildMessageBubble(_visibleMessages[idx]);
                                },
                              ),
                              if (picker != null) picker,
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ),

        if (_isRecording)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2C34),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: SafeArea(
              top: false,
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF5252)),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Recording',
                  style: TextStyle(color: Color(0xFFE9EDEF), fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_recordSeconds}s',
                  style: const TextStyle(color: Color(0xFF8696A0), fontSize: 14),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _stopAndSendRecording,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00A884).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ]),
            ),
          )
        else
          _buildMessageComposer(),
      ],
    )),
    );
  }

  Widget _composerIconBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    double size = 22,
    Color? color,
  }) {
    final tint = color ?? const Color(0xFF8696A0);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: size,
              color: onPressed == null ? tint.withValues(alpha: 0.35) : tint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageComposer() {
    final mobile = Responsive.isMobile(context);
    final desktop = PlatformCapabilities.isDesktop;
    final canSend = _canSend;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard > 120) {
      _emojiPanelHeight = keyboard;
    }
    const waGreen = Color(0xFF00A884);
    const waBarBg = Color(0xFF1F2C34);
    const waInputBg = Color(0xFF2A3942);
    const waIcon = Color(0xFF8696A0);
    const waHint = Color(0xFF667781);

    return ColoredBox(
      color: waBarBg,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 420;
                final padH = mobile || narrow ? 6.0 : 10.0;
                final hint = desktop
                    ? (narrow ? 'Message' : 'Message · Enter to send')
                    : 'Message';
                return Padding(
                  padding: EdgeInsets.fromLTRB(padH, 7, padH, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_replyTo != null) _buildReplyComposerBar(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _composerIconBtn(
                            tooltip: _emojiOpen ? 'Keyboard' : 'Emoji',
                            onPressed: _isSending ? null : _toggleEmojiPanel,
                            icon: _emojiOpen
                                ? Icons.keyboard_alt_outlined
                                : Icons.emoji_emotions_outlined,
                            size: narrow ? 23 : 24,
                            color: _emojiOpen ? waGreen : waIcon,
                          ),
                          Expanded(
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 44, maxHeight: 132),
                              decoration: BoxDecoration(
                                color: waInputBg,
                                borderRadius: BorderRadius.circular(26),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: CallbackShortcuts(
                                      bindings: {
                                        const SingleActivator(LogicalKeyboardKey.enter, control: true): _sendMessage,
                                        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _sendMessage,
                                        SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
                                          unawaited(_pasteFromClipboard());
                                        },
                                        SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
                                          unawaited(_pasteFromClipboard());
                                        },
                                      },
                                      child: Focus(
                                        onKeyEvent: desktop
                                            ? (node, event) {
                                                if (event is! KeyDownEvent ||
                                                    event.logicalKey != LogicalKeyboardKey.enter) {
                                                  return KeyEventResult.ignored;
                                                }
                                                if (HardwareKeyboard.instance.isShiftPressed) {
                                                  return KeyEventResult.ignored;
                                                }
                                                _sendMessage();
                                                return KeyEventResult.handled;
                                              }
                                            : null,
                                        child: TextField(
                                          controller: _msgController,
                                          focusNode: _msgFocus,
                                          minLines: 1,
                                          maxLines: 6,
                                          keyboardType: TextInputType.multiline,
                                          textInputAction: desktop
                                              ? TextInputAction.send
                                              : TextInputAction.newline,
                                          textCapitalization: TextCapitalization.sentences,
                                          style: const TextStyle(
                                            color: Color(0xFFE9EDEF),
                                            fontSize: 16,
                                            height: 1.32,
                                            letterSpacing: 0.1,
                                          ),
                                          cursorColor: waGreen,
                                          onTap: () {
                                            if (_emojiOpen) setState(() => _emojiOpen = false);
                                          },
                                          contextMenuBuilder: (context, editableTextState) {
                                            final defaults = editableTextState.contextMenuButtonItems
                                                .where((item) => item.type != ContextMenuButtonType.paste)
                                                .toList();
                                            return AdaptiveTextSelectionToolbar.buttonItems(
                                              anchors: editableTextState.contextMenuAnchors,
                                              buttonItems: <ContextMenuButtonItem>[
                                                ContextMenuButtonItem(
                                                  label: 'Paste',
                                                  onPressed: () {
                                                    ContextMenuController.removeAny();
                                                    unawaited(_pasteFromClipboard());
                                                  },
                                                ),
                                                ...defaults,
                                              ],
                                            );
                                          },
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: hint,
                                            hintStyle: const TextStyle(color: waHint, fontSize: 15.5),
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.fromLTRB(4, 11, 0, 11),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  _composerIconBtn(
                                    tooltip: 'Attach file',
                                    onPressed: _isSending
                                        ? null
                                        : () {
                                            if (_emojiOpen) setState(() => _emojiOpen = false);
                                            unawaited(_showAttachSheet());
                                          },
                                    icon: Icons.attach_file_rounded,
                                    size: 22,
                                  ),
                                  if (!canSend && !desktop)
                                    _composerIconBtn(
                                      tooltip: 'Camera',
                                      onPressed: _isSending
                                          ? null
                                          : () {
                                              if (_emojiOpen) setState(() => _emojiOpen = false);
                                              unawaited(_takePhoto());
                                            },
                                      icon: Icons.photo_camera_outlined,
                                      size: 22,
                                    ),
                                  const SizedBox(width: 2),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _isSending ? null : (canSend ? _sendMessage : _toggleRecording),
                              child: Ink(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: canSend ? waGreen : waGreen.withValues(alpha: 0.92),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: waGreen.withValues(alpha: 0.28),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: _isSending
                                    ? const Padding(
                                        padding: EdgeInsets.all(13),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        canSend ? Icons.send_rounded : Icons.mic_rounded,
                                        color: Colors.white,
                                        size: canSend ? 21 : 23,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            if (_emojiOpen)
              SizedBox(
                height: _emojiPanelHeight.clamp(250, 360),
                child: ColoredBox(
                  color: const Color(0xFF0B141A),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Emoji',
                              style: TextStyle(
                                color: Color(0xFF8696A0),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => setState(() => _emojiOpen = false),
                              child: const Icon(Icons.keyboard_alt_outlined, color: Color(0xFF8696A0), size: 22),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                          itemCount: kChatEmojiList.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 8,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemBuilder: (_, i) {
                            final emoji = kChatEmojiList[i];
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _insertEmoji(emoji),
                                borderRadius: BorderRadius.circular(8),
                                child: Center(child: _emojiText(emoji, size: 26)),
                              ),
                            );
                          },
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

  Widget _buildReplyComposerBar() {
    final reply = _replyTo!;
    const accent = Color(0xFF00A884);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A3942),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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

  /// Max bubble width relative to the chat pane (not the full window).
  double _bubbleMaxWidth(BuildContext context) {
    final chatW = _chatThreadWidth.clamp(200.0, 2000.0);
    return (chatW * 0.72).clamp(120.0, 420.0);
  }

  // â”€â”€â”€ Message Bubble (WhatsApp: shrink-wrap, sent right / received left) â”€â”€â”€
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
    final replyRaw = msg['reply'];
    Map<String, dynamic>? reply;
    if (replyRaw is Map) {
      reply = Map<String, dynamic>.from(replyRaw);
    } else {
      final mid = _asInt(msg['id']);
      if (mid != null && _replyQuotesByMsgId.containsKey(mid)) {
        reply = Map<String, dynamic>.from(_replyQuotesByMsgId[mid]!);
      } else {
        final parentId = _asInt(msg['reply_to'] ?? msg['reply_to_id']);
        if (parentId != null) {
          for (final m in _messages) {
            if (m is Map && _asInt(m['id']) == parentId) {
              reply = _quoteFromParent(Map<String, dynamic>.from(m));
              if (mid != null) _cacheReplyQuote(mid, reply);
              break;
            }
          }
        }
      }
    }
    if (reply != null &&
        (reply['preview'] ?? '').toString().trim().isEmpty &&
        (reply['sender_name'] ?? '').toString().trim().isEmpty) {
      reply = null;
    }

    const ownBubble = Color(0xFF005C4B);
    const otherBubble = Color(0xFF1F2C33);
    final maxW = _bubbleMaxWidth(context);
    final bubbleShape = chatBubbleRadius(isOwn: isOwn);
    final isPlainText = !isDeleted &&
        msgType == 'text' &&
        reply == null &&
        imageUrl == null &&
        fileUrl == null &&
        voiceUrl == null;
    final isImageMessage = !isDeleted && msgType == 'image' && imageUrl != null;
    final isImageOnly = isImageMessage && text.toString().trim().isEmpty;

    Widget metaRow({Color? timeColor}) {
      final tint = timeColor ?? Colors.white.withValues(alpha: 0.58);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEdited)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                'edited',
                style: _bubbleMetaStyle.copyWith(
                  fontStyle: FontStyle.italic,
                  color: tint,
                ),
              ),
            ),
          Text(time, style: _bubbleMetaStyle.copyWith(color: tint)),
          if (isOwn && !isGroup && !isDeleted) ...[
            const SizedBox(width: 3),
            Icon(
              Icons.done_all_rounded,
              size: 14,
              color: msg['is_read'] == true
                  ? const Color(0xFF53BDEB)
                  : Colors.white.withValues(alpha: 0.5),
            ),
          ],
        ],
      );
    }

    Widget bodyContent() {
      if (isDeleted) {
        return Text(
          'This message was deleted',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        );
      }
      if (msgType == 'voice' && voiceUrl != null) {
        return GestureDetector(
          onTap: () => _playVoice(voiceUrl),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _playingUrl == voiceUrl ? Icons.stop_circle : Icons.play_circle_fill,
                color: isOwn ? const Color(0xFF06CF9C) : AppTheme.accent,
                size: 28,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Voice message',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _playingUrl == voiceUrl ? 'Playing\u2026' : 'Tap to play',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        );
      }
      if (msgType == 'image' && imageUrl != null) {
        final imgW = (maxW - 12).clamp(140.0, 280.0);
        final hasCaption = text.toString().trim().isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => unawaited(_openChatImageViewer(Map<String, dynamic>.from(msg as Map))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Image.network(
                      imageUrl,
                      width: imgW,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: imgW,
                        height: 120,
                        color: Colors.white10,
                        child: const Icon(Icons.broken_image, color: Colors.white38),
                      ),
                    ),
                    if (!hasCaption)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 44,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (!hasCaption)
                      Positioned(
                        right: 8,
                        bottom: 6,
                        child: metaRow(timeColor: Colors.white.withValues(alpha: 0.92)),
                      ),
                  ],
                ),
              ),
            ),
            if (hasCaption) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(text.toString(), style: _bubbleTextStyle),
              ),
            ],
          ],
        );
      }
      if (msgType == 'file' && fileUrl != null) {
        return GestureDetector(
          onTap: () => _openFileUrl(fileUrl),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF53BDEB), size: 24),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW - 70),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName.toString(),
                      style: const TextStyle(
                        color: Color(0xFFE9EDEF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      PlatformCapabilities.isDesktop ? 'Click to open' : 'Tap to open',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      return Text(
        text.toString(),
        softWrap: true,
        style: _bubbleTextStyle,
      );
    }

    final hasReactions = msg['reactions'] is List && (msg['reactions'] as List).isNotEmpty;
    final swipeReplyEnabled = !isDeleted && Responsive.isMobile(context) && !_inMessageSelectionMode;
    final isSelected = _isMessageSelected(msg);

    return SwipeToReply(
      enabled: swipeReplyEnabled,
      onReply: () => _setReplyTo(msg),
      child: Padding(
      padding: EdgeInsets.only(
        left: isOwn ? 56 : 6,
        right: isOwn ? 6 : 56,
        bottom: hasReactions ? 20 : 2,
        top: 1,
      ),
      child: Align(
        alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
        child: IntrinsicWidth(
          child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Builder(
            builder: (bubbleCtx) {
              void openOptions([Offset? globalPos]) {
                if (isDeleted) return;
                unawaited(_showMessageOptions(
                  msg,
                  globalPosition: globalPos,
                  anchorContext: bubbleCtx,
                ));
              }

              Widget metaWithMenu() {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isDeleted && PlatformCapabilities.isDesktop)
                      GestureDetector(
                        onTap: () => openOptions(),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.38),
                          ),
                        ),
                      ),
                    metaRow(),
                  ],
                );
              }

              Widget bubbleBody() {
                if (isPlainText) {
                  final display = isDeleted
                      ? 'This message was deleted'
                      : text.toString();
                  return Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        display,
                        style: isDeleted
                            ? _bubbleTextStyle.copyWith(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontStyle: FontStyle.italic,
                              )
                            : _bubbleTextStyle,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: metaWithMenu(),
                      ),
                    ],
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bodyContent(),
                    if (!isImageOnly) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: metaWithMenu(),
                      ),
                    ],
                  ],
                );
              }

              final bubble = Material(
                color: Colors.transparent,
                child: InkWell(
                  onLongPress: !isDeleted
                      ? () => _enterMessageSelection(msg, bubbleCtx)
                      : null,
                  onTap: _inMessageSelectionMode && !isDeleted
                      ? () => _toggleMessageSelection(msg)
                      : null,
                  onSecondaryTapDown: !isDeleted && !_inMessageSelectionMode
                      ? (details) => openOptions(details.globalPosition)
                      : null,
                  onDoubleTap: !isDeleted && !_inMessageSelectionMode ? () => _setReplyTo(msg) : null,
                  borderRadius: bubbleShape,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Color.alphaBlend(
                              const Color(0xFF00A884).withValues(alpha: 0.28),
                              isOwn ? ownBubble : otherBubble,
                            )
                          : (isOwn ? ownBubble : otherBubble),
                      borderRadius: bubbleShape,
                      border: isSelected
                          ? Border.all(color: const Color(0xFF00A884).withValues(alpha: 0.55), width: 1.5)
                          : (isOwn
                              ? null
                              : Border.all(color: Colors.white.withValues(alpha: 0.05))),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: isImageMessage
                          ? EdgeInsets.fromLTRB(3, 3, 3, hasReactions ? 10 : 3)
                          : EdgeInsets.fromLTRB(8, 5, 8, hasReactions ? 8 : 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isOwn && isGroup)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2, left: 1),
                              child: Text(
                                senderName.toString(),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                  color: Color(0xFF53BDEB),
                                ),
                              ),
                            ),
                          if (reply != null) ...[
                            _buildQuotedReply(reply, isOwn: isOwn, maxWidth: maxW - 24),
                            const SizedBox(height: 4),
                          ],
                          bubbleBody(),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  bubble,
                  if (hasReactions)
                    Positioned(
                      bottom: -7,
                      right: isOwn ? 12 : null,
                      left: isOwn ? null : 12,
                      child: _buildReactionsRow(msg, isOwn: isOwn),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
      ),
    );
  }

  Widget _buildQuotedReply(Map<String, dynamic> reply, {required bool isOwn, double maxWidth = 240}) {
    final accent = isOwn ? const Color(0xFF06CF9C) : const Color(0xFF53BDEB);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3.5,
              height: 36,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: (maxWidth - 20).clamp(80.0, maxWidth)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${reply['sender_name'] ?? 'Message'}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${reply['preview'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
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

  Widget _buildMessageSelectionHeader({required bool compact, required bool isWide}) {
    final count = _selectedMessageIds.length;
    final single = _singleSelectedMessage();
    final flags = single != null ? _messageActionFlags(single) : <String, bool>{};
    final allStarred = _selectedMessages().every((m) {
      final id = _messageIdOf(m);
      return id != null && _starredMessageIds.contains(id);
    });
    const iconColor = Color(0xFFE9EDEF);

    Future<void> runAndClear(Future<void> Function() action) async {
      await action();
      if (mounted) _clearMessageSelection();
    }

    void runSyncAndClear(void Function() action) {
      action();
      _clearMessageSelection();
    }

    return KeyedSubtree(
      key: _selectionHeaderKey,
      child: Container(
      height: PlatformCapabilities.immersiveChatChrome ? 66 : 74,
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancel',
            onPressed: _clearMessageSelection,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: iconColor, size: 20),
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (single != null)
            IconButton(
              tooltip: 'Reply',
              onPressed: () => runSyncAndClear(() => _setReplyTo(single)),
              icon: const Icon(Icons.reply_rounded, color: iconColor, size: 24),
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            tooltip: allStarred ? 'Unstar' : 'Star',
            onPressed: _toggleStarSelected,
            icon: Icon(
              allStarred ? Icons.star_rounded : Icons.star_outline_rounded,
              color: allStarred ? const Color(0xFFFFC107) : iconColor,
              size: 24,
            ),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => unawaited(runAndClear(_deleteSelectedMessages)),
            icon: const Icon(Icons.delete_outline_rounded, color: iconColor, size: 24),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Forward',
            onPressed: () => unawaited(runAndClear(_forwardSelectedMessages)),
            icon: const Icon(Icons.shortcut_rounded, color: iconColor, size: 24),
            visualDensity: VisualDensity.compact,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, color: iconColor, size: 24),
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onSelected: (action) async {
              if (single == null) {
                if (action == 'copy') {
                  await _copySelectedMessages();
                  _clearMessageSelection();
                }
                return;
              }
              switch (action) {
                case 'info':
                  _showMessageInfo(single);
                  _clearMessageSelection();
                  break;
                case 'share':
                  await _shareMessage(single);
                  _clearMessageSelection();
                  break;
                case 'copy':
                  await _copyMessageContent(single);
                  _clearMessageSelection();
                  break;
                case 'view':
                  await _openChatImageViewer(single);
                  _clearMessageSelection();
                  break;
                case 'open':
                  final imageUrl = (single['image_url'] ?? '').toString();
                  final fileUrl = (single['file_url'] ?? '').toString();
                  final voiceUrl = (single['voice_url'] ?? '').toString();
                  final openUrl = imageUrl.isNotEmpty
                      ? imageUrl
                      : (fileUrl.isNotEmpty ? fileUrl : voiceUrl);
                  if (openUrl.isNotEmpty) await _openFileUrl(openUrl);
                  _clearMessageSelection();
                  break;
                case 'edit':
                  _showEditDialog(single);
                  _clearMessageSelection();
                  break;
                case 'pin':
                  AppToast.info(context, 'Pin is not available yet');
                  break;
              }
            },
            itemBuilder: (_) {
              final items = <PopupMenuEntry<String>>[];
              if (single != null) {
                items.add(const PopupMenuItem(value: 'info', child: Text('Info')));
                items.add(const PopupMenuItem(value: 'share', child: Text('Share')));
              }
              if (single != null && flags['canCopy'] == true) {
                items.add(const PopupMenuItem(value: 'copy', child: Text('Copy')));
              } else if (single == null) {
                items.add(const PopupMenuItem(value: 'copy', child: Text('Copy')));
              }
              if (single != null && flags['hasImage'] == true) {
                items.add(const PopupMenuItem(value: 'view', child: Text('View')));
              }
              if (single != null && flags['hasOpenUrl'] == true) {
                items.add(const PopupMenuItem(value: 'open', child: Text('Open externally')));
              }
              if (single != null && flags['canEdit'] == true) {
                items.add(const PopupMenuItem(value: 'edit', child: Text('Edit')));
              }
              if (single != null) {
                items.add(const PopupMenuItem(value: 'pin', child: Text('Pin')));
              }
              return items;
            },
          ),
          if (isWide) const SizedBox(width: 4),
        ],
      ),
      ),
    );
  }

  void _toggleStarSelected() {
    final msgs = _selectedMessages();
    if (msgs.isEmpty) return;
    final allStarred = msgs.every((m) {
      final id = _messageIdOf(m);
      return id != null && _starredMessageIds.contains(id);
    });
    setState(() {
      for (final m in msgs) {
        final id = _messageIdOf(m);
        if (id == null) continue;
        if (allStarred) {
          _starredMessageIds.remove(id);
        } else {
          _starredMessageIds.add(id);
        }
      }
    });
    AppToast.success(context, allStarred ? 'Unstarred' : 'Starred');
  }

  Future<void> _copySelectedMessages() async {
    final msgs = _selectedMessages();
    if (msgs.isEmpty) return;
    if (msgs.length == 1) {
      await _copyMessageContent(msgs.first);
      return;
    }
    final parts = <String>[];
    for (final m in msgs) {
      final text = (m['message'] ?? '').toString().trim();
      if (text.isNotEmpty) parts.add(text);
    }
    if (parts.isEmpty) {
      _showError('Nothing to copy');
      return;
    }
    await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
    if (mounted) AppToast.success(context, 'Copied ${parts.length} messages');
  }

  Future<void> _shareMessage(Map<String, dynamic> msg) async {
    final text = (msg['message'] ?? '').toString().trim();
    final imageUrl = (msg['image_url'] ?? '').toString();
    final fileUrl = (msg['file_url'] ?? '').toString();
    final voiceUrl = (msg['voice_url'] ?? '').toString();
    final payload = text.isNotEmpty
        ? text
        : (imageUrl.isNotEmpty
            ? imageUrl
            : (fileUrl.isNotEmpty ? fileUrl : voiceUrl));
    if (payload.isEmpty) {
      _showError('Nothing to share');
      return;
    }
    await Clipboard.setData(ClipboardData(text: payload));
    if (mounted) AppToast.success(context, 'Copied — paste to share');
  }

  Future<void> _deleteSelectedMessages() async {
    final msgs = _selectedMessages();
    if (msgs.isEmpty) return;
    final label = msgs.length == 1 ? 'Delete this message?' : 'Delete ${msgs.length} messages?';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(label, style: const TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    var failed = 0;
    for (final m in msgs) {
      final r = await widget.apiService.deleteMessage(m['id']);
      if (r['success'] != true) failed++;
    }
    if (!mounted) return;
    _silentRefresh();
    if (failed == 0) {
      _showSuccess(msgs.length == 1 ? 'Message deleted' : 'Messages deleted');
    } else {
      _showError('Deleted ${msgs.length - failed} of ${msgs.length}');
    }
  }

  Future<void> _forwardSelectedMessages() async {
    final msgs = _selectedMessages();
    if (msgs.isEmpty) return;
    if (msgs.length == 1) {
      await _forwardMessage(msgs.first);
      return;
    }
    final peer = await _pickForwardContact();
    if (peer == null) return;
    final peerId = _asInt(peer['id']);
    if (peerId == null) return;
    var ok = 0;
    for (final msg in msgs) {
      final sent = await _forwardMessageTo(msg, peerId);
      if (sent) ok++;
    }
    if (!mounted) return;
    if (ok > 0) {
      _showSuccess('Forwarded $ok message${ok == 1 ? '' : 's'}');
    } else {
      _showError('Forward failed');
    }
  }

  Future<Map?> _pickForwardContact() async {
    final contacts = _users.whereType<Map>().toList();
    if (contacts.isEmpty) {
      _showError('No contacts to forward to');
      return null;
    }
    return showDialog<Map>(
      context: context,
      builder: (ctx) {
        final filter = TextEditingController();
        var q = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = contacts.where((u) {
              final name = '${u['full_name'] ?? ''} ${u['username'] ?? ''}'.toLowerCase();
              return q.isEmpty || name.contains(q);
            }).toList();
            return AlertDialog(
              backgroundColor: AppTheme.dialogBg,
              title: const Text('Forward to…', style: TextStyle(color: AppTheme.textPrimary)),
              content: SizedBox(
                width: 360,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: filter,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: _dialogInputDecor('Search contacts…'),
                      onChanged: (v) => setLocal(() => q = v.toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final u = filtered[i];
                          final name = (u['full_name'] ?? u['username'] ?? 'User').toString();
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _avatarColor(_asInt(u['id']) ?? 0),
                              child: Text(_initials(name), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                            title: Text(name, style: const TextStyle(color: AppTheme.textPrimary)),
                            onTap: () => Navigator.pop(ctx, u),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _forwardMessageTo(dynamic msg, int peerId) async {
    if (msg is! Map) return false;
    final text = (msg['message'] ?? '').toString().trim();
    final imageUrl = (msg['image_url'] ?? '').toString();
    final fileUrl = (msg['file_url'] ?? '').toString();
    final voiceUrl = (msg['voice_url'] ?? '').toString();
    if (imageUrl.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 45));
        if (resp.statusCode < 200 || resp.statusCode >= 300) return false;
        final lower = imageUrl.toLowerCase();
        final filename = lower.contains('.png')
            ? 'forwarded.png'
            : (lower.contains('.webp') ? 'forwarded.webp' : 'forwarded.jpg');
        final result = await widget.apiService.sendImageMessage(
          peerId,
          resp.bodyBytes,
          filename,
          message: text,
        );
        return result['success'] == true;
      } catch (_) {
        return false;
      }
    }
    var forwardBody = text;
    if (forwardBody.isEmpty) {
      if (fileUrl.isNotEmpty) {
        forwardBody = 'Forwarded file: $fileUrl';
      } else if (voiceUrl.isNotEmpty) {
        forwardBody = 'Forwarded voice: $voiceUrl';
      }
    } else {
      forwardBody = 'Forwarded:\n$forwardBody';
    }
    if (forwardBody.isEmpty) return false;
    final result = await widget.apiService.sendMessage(peerId, forwardBody);
    return result['success'] == true;
  }

  // â”€â”€â”€ Message Options (Reply / Copy / Forward / Open / Info / Edit / Delete) â”€â”€â”€
  Future<void> _showMessageOptions(
    dynamic msg, {
    Offset? globalPosition,
    BuildContext? anchorContext,
  }) async {
    if (msg is! Map) return;
    final isOwn = msg['is_own'] == true;
    final msgType = (msg['message_type'] ?? 'text').toString();
    final text = (msg['message'] ?? '').toString();
    final imageUrl = (msg['image_url'] ?? '').toString();
    final fileUrl = (msg['file_url'] ?? '').toString();
    final voiceUrl = (msg['voice_url'] ?? '').toString();
    final openUrl = imageUrl.isNotEmpty
        ? imageUrl
        : (fileUrl.isNotEmpty ? fileUrl : (voiceUrl.isNotEmpty ? voiceUrl : ''));
    final canCopy = (text.trim().isNotEmpty && (msgType == 'text' || msgType.isEmpty)) ||
        (msgType == 'image' && imageUrl.isNotEmpty);
    final canEdit = isOwn && (msgType == 'text' || msg['message_type'] == null);
    final canForward = text.trim().isNotEmpty || openUrl.isNotEmpty;
    final desktop = PlatformCapabilities.isDesktop;

    Future<void> runAction(String action) async {
      switch (action) {
        case 'reply':
          _setReplyTo(msg);
          break;
        case 'copy':
          await _copyMessageContent(Map<String, dynamic>.from(msg));
          break;
        case 'forward':
          await _forwardMessage(msg);
          break;
        case 'view':
          if (imageUrl.isNotEmpty) {
            await _openChatImageViewer(Map<String, dynamic>.from(msg));
          }
          break;
        case 'open':
          if (openUrl.isNotEmpty) await _openFileUrl(openUrl);
          break;
        case 'info':
          _showMessageInfo(msg);
          break;
        case 'edit':
          _showEditDialog(msg);
          break;
        case 'delete':
          await _deleteMessage(msg);
          break;
      }
    }

    final menuItems = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'reply',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.reply_rounded, color: AppTheme.primaryBright),
          title: Text('Reply', style: TextStyle(color: AppTheme.textPrimary)),
        ),
      ),
      if (canCopy)
        const PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.copy_rounded, color: AppTheme.textMuted),
            title: Text('Copy', style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ),
      if (canForward)
        const PopupMenuItem(
          value: 'forward',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.shortcut_rounded, color: AppTheme.accent),
            title: Text('Forward', style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ),
      if (imageUrl.isNotEmpty)
        const PopupMenuItem(
          value: 'view',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.fullscreen_rounded, color: AppTheme.primaryBright),
            title: Text('View', style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ),
      if (openUrl.isNotEmpty)
        const PopupMenuItem(
          value: 'open',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.open_in_new_rounded, color: AppTheme.primary),
            title: Text('Open externally', style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ),
      const PopupMenuItem(
        value: 'info',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.info_outline_rounded, color: AppTheme.textMuted),
          title: Text('Message info', style: TextStyle(color: AppTheme.textPrimary)),
        ),
      ),
      if (canEdit)
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit, color: AppTheme.primary),
            title: Text('Edit', style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ),
      if (isOwn)
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete, color: AppTheme.danger),
            title: Text('Delete', style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ),
    ];

    if (desktop) {
      final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
      RelativeRect position;
      if (globalPosition != null && overlay != null) {
        position = RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
          Offset.zero & overlay.size,
        );
      } else if (anchorContext != null) {
        final box = anchorContext.findRenderObject() as RenderBox?;
        if (box != null && overlay != null) {
          final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
          position = RelativeRect.fromLTRB(
            topLeft.dx,
            topLeft.dy + box.size.height,
            overlay.size.width - topLeft.dx - box.size.width,
            overlay.size.height - topLeft.dy - box.size.height,
          );
        } else {
          position = const RelativeRect.fromLTRB(80, 120, 80, 120);
        }
      } else {
        position = const RelativeRect.fromLTRB(80, 120, 80, 120);
      }

      final selected = await showMenu<String>(
        context: context,
        position: position,
        color: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        items: menuItems,
      );
      if (selected != null) await runAction(selected);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.dialogBg,
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
                unawaited(runAction('reply'));
              },
            ),
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: AppTheme.textMuted),
                title: const Text('Copy', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(runAction('copy'));
                },
              ),
            if (canForward)
              ListTile(
                leading: const Icon(Icons.shortcut_rounded, color: AppTheme.accent),
                title: const Text('Forward', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(runAction('forward'));
                },
              ),
            if (imageUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.fullscreen_rounded, color: AppTheme.primaryBright),
                title: const Text('View', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(runAction('view'));
                },
              ),
            if (openUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded, color: AppTheme.primary),
                title: const Text('Open externally', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(runAction('open'));
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: AppTheme.textMuted),
              title: const Text('Message info', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                unawaited(runAction('info'));
              },
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit, color: AppTheme.primary),
                title: const Text('Edit Message', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(runAction('edit'));
                },
              ),
            if (isOwn)
              ListTile(
                leading: const Icon(Icons.delete, color: AppTheme.danger),
                title: const Text('Delete Message', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(runAction('delete'));
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showMessageInfo(dynamic msg) {
    if (msg is! Map) return;
    final type = (msg['message_type'] ?? 'text').toString();
    final when = (msg['created_at'] ?? msg['timestamp'] ?? '').toString();
    final sender = msg['is_own'] == true
        ? 'You'
        : (msg['sender_name'] ?? msg['sender_full_name'] ?? msg['sender_username'] ?? 'User').toString();
    final read = msg['is_read'] == true ? 'Read' : 'Delivered';
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Message info', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogInfoLine('From', sender),
            _dialogInfoLine('Type', type),
            _dialogInfoLine('Time', when),
            if (msg['is_own'] == true) _dialogInfoLine('Status', read),
            if ((msg['message'] ?? '').toString().trim().isNotEmpty)
              _dialogInfoLine('Text', msg['message'].toString()),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _dialogInfoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _forwardMessage(dynamic msg) async {
    if (msg is! Map) return;
    final text = (msg['message'] ?? '').toString().trim();
    final imageUrl = (msg['image_url'] ?? '').toString();
    final fileUrl = (msg['file_url'] ?? '').toString();
    final voiceUrl = (msg['voice_url'] ?? '').toString();
    final isImageForward = imageUrl.isNotEmpty;

    var forwardBody = text;
    if (!isImageForward) {
      if (forwardBody.isEmpty) {
        if (fileUrl.isNotEmpty) {
          forwardBody = 'Forwarded file: $fileUrl';
        } else if (voiceUrl.isNotEmpty) {
          forwardBody = 'Forwarded voice: $voiceUrl';
        }
      } else {
        forwardBody = 'Forwarded:\n$forwardBody';
      }
      if (forwardBody.isEmpty) {
        _showError('Nothing to forward');
        return;
      }
    }

    final contacts = _users.whereType<Map>().toList();
    if (contacts.isEmpty) {
      _showError('No contacts to forward to');
      return;
    }

    final selected = await showDialog<Map>(
      context: context,
      builder: (ctx) {
        final filter = TextEditingController();
        var q = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = contacts.where((u) {
              final name = '${u['full_name'] ?? ''} ${u['username'] ?? ''}'.toLowerCase();
              return q.isEmpty || name.contains(q);
            }).toList();
            return AlertDialog(
              backgroundColor: AppTheme.dialogBg,
              title: const Text('Forward to…', style: TextStyle(color: AppTheme.textPrimary)),
              content: SizedBox(
                width: 360,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: filter,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: _dialogInputDecor('Search contacts…'),
                      onChanged: (v) => setLocal(() => q = v.toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final u = filtered[i];
                          final name = (u['full_name'] ?? u['username'] ?? 'User').toString();
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _avatarColor(_asInt(u['id']) ?? 0),
                              child: Text(_initials(name), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                            title: Text(name, style: const TextStyle(color: AppTheme.textPrimary)),
                            onTap: () => Navigator.pop(ctx, u),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ],
            );
          },
        );
      },
    );
    if (selected == null) return;
    final peerId = _asInt(selected['id']);
    if (peerId == null) return;

    if (isImageForward) {
      try {
        final resp = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 45));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          _showError('Could not download image to forward');
          return;
        }
        final lower = imageUrl.toLowerCase();
        final filename = lower.contains('.png')
            ? 'forwarded.png'
            : (lower.contains('.webp') ? 'forwarded.webp' : 'forwarded.jpg');
        final result = await widget.apiService.sendImageMessage(
          peerId,
          resp.bodyBytes,
          filename,
          message: text,
        );
        if (!mounted) return;
        if (result['success'] == true) {
          _showSuccess('Photo forwarded');
        } else {
          _showError(result['error']?.toString() ?? 'Forward failed');
        }
      } catch (e) {
        if (mounted) _showError('Forward failed: $e');
      }
      return;
    }

    final result = await widget.apiService.sendMessage(peerId, forwardBody);
    if (!mounted) return;
    if (result['success'] == true) {
      _showSuccess('Forwarded');
    } else {
      _showError(result['error']?.toString() ?? 'Forward failed');
    }
  }

  void _showEditDialog(dynamic msg) {
    final controller = TextEditingController(text: msg['message'] ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
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
            filled: true, fillColor: AppTheme.surface.withValues(alpha: 0.85),
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
            style: AppTheme.primaryElevatedButton(),
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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

  // â”€â”€â”€ Create Group Dialog â”€â”€â”€
  void _showCreateGroupDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final selectedIds = <int>{};
    var personalInbox = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
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
                  SizedBox(height: 12),
                    SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: personalInbox,
                    onChanged: (v) => setDialogState(() => personalInbox = v),
                    activeThumbColor: AppTheme.primary,
                    title: Text(
                      'Personal inbox',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Members only see messages they sent or received. Creator/admins/managers see everything.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('Add Members', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Container(
                    constraints: BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _users.length,
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        final uid = _chatInt(u is Map ? u['id'] : null);
                        if (uid == null) return const SizedBox.shrink();
                        final uname = (u is Map ? (u['full_name'] ?? u['username']) : null) ?? 'User';
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
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) { _showError('Group name is required'); return; }
                Navigator.pop(context);
                _createGroup(
                  nameCtrl.text.trim(),
                  descCtrl.text.trim(),
                  selectedIds.toList(),
                  visibilityMode: personalInbox ? 'personal' : 'shared',
                );
              },
              style: AppTheme.primaryButton(radius: 12),
              child: const Text('Create Group'),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
    filled: true, fillColor: AppTheme.surface.withValues(alpha: 0.85),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary)),
  );

  // â”€â”€â”€ Group Settings â”€â”€â”€
  void _showGroupSettings(dynamic group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.dialogBg,
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
            setState(() {
              _selectedGroup = null;
              _messages = [];
              _detailsOpen = false;
              _refreshTimer?.cancel();
            });
          },
        ),
      ),
    );
  }

  // â”€â”€â”€ Helpers â”€â”€â”€
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


// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// Group Settings Bottom Sheet
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  bool _saving = false;
  int? _currentUserId;
  bool _isCompanyManager = false;

  bool get _canManage {
    if (_isCompanyManager) return true;
    final createdBy = _chatInt(widget.group is Map ? widget.group['created_by'] : null);
    if (createdBy != null && createdBy == _currentUserId) return true;
    for (final m in _members) {
      if (_membershipUserId(m) == _currentUserId) {
        final role = (m['role'] ?? '').toString().toLowerCase();
        return role == 'admin';
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final id = int.tryParse(await UserDataService.getUserId());
    final manager = await UserDataService.isManagerOrAbove();
    if (mounted) {
      setState(() {
        _currentUserId = id;
        _isCompanyManager = manager;
      });
    }
    await _loadMembers();
  }

  List<Map<String, dynamic>> _asMemberList(dynamic raw) {
    Iterable list;
    if (raw is List) {
      list = raw;
    } else if (raw is Map && raw['results'] is List) {
      list = raw['results'] as List;
    } else if (raw is Map && raw['members'] is List) {
      list = raw['members'] as List;
    } else {
      return [];
    }
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _loadMembers() async {
    final groupId = _chatInt(widget.group is Map ? widget.group['id'] : widget.group);
    if (groupId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final r = await widget.apiService.getGroupMembers(groupId);
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _members = _asMemberList(r['data']);
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      AppToast.error(context, r['error']?.toString() ?? 'Could not load members');
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

        // â”€â”€â”€ Group Info â”€â”€â”€
        _settingsCard([
          _infoRow('Group Name', group['name'] ?? ''),
          _infoRow('Description', group['description'] ?? 'No description'),
          _infoRow('Created', group['created_at'] ?? ''),
          if (group['project_name'] != null)
            _infoRow('Project', group['project_name']),
        ], action: _canManage
            ? TextButton.icon(
                onPressed: _saving ? null : () => _showEditGroup(),
                icon: Icon(Icons.edit, size: 14, color: AppTheme.primary),
                label: Text('Edit', style: TextStyle(color: AppTheme.primary, fontSize: 12)),
              )
            : null),
        SizedBox(height: 16),

        // â”€â”€â”€ Members â”€â”€â”€
        _settingsCard([
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Members (${_members.length})', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              if (_canManage)
                TextButton.icon(
                  onPressed: _saving ? null : _showAddMembers,
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

        // â”€â”€â”€ Danger Zone â”€â”€â”€
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
                onPressed: _canManage && !_saving ? _confirmDeleteGroup : null,
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

  Widget _memberTile(Map<String, dynamic> m) {
    final name = (m['full_name'] ?? m['username'] ?? 'User').toString();
    final role = (m['role'] ?? 'member').toString();
    final uid = _membershipUserId(m);
    final createdBy = _chatInt(widget.group is Map ? widget.group['created_by'] : null);
    final isCreator = uid != null && uid == createdBy;
    final canRemove = _canManage && uid != null && uid != createdBy && uid != _currentUserId;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.35),
            child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
              Text(
                isCreator ? 'creator' : role,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ]),
          ),
          if (_canManage && uid != null && !isCreator)
            PopupMenuButton<String>(
              enabled: !_saving,
              icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 20),
              color: AppTheme.surface2,
              onSelected: (value) {
                if (value == 'admin' || value == 'member') {
                  _setMemberRole(uid, value);
                } else if (value == 'remove' && canRemove) {
                  _removeMember(m);
                }
              },
              itemBuilder: (_) => [
                if (role != 'admin')
                  const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                if (role == 'admin')
                  const PopupMenuItem(value: 'member', child: Text('Make member')),
                if (canRemove)
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove', style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            )
          else if (canRemove)
            IconButton(
              tooltip: 'Remove',
              onPressed: _saving ? null : () => _removeMember(m),
              icon: const Icon(Icons.remove_circle_outline, color: AppTheme.danger, size: 20),
            ),
        ],
      ),
    );
  }

  int? get _groupId => _chatInt(widget.group is Map ? widget.group['id'] : widget.group);

  void _showEditGroup() {
    if (!_canManage) {
      AppToast.error(context, 'Only group admins can edit this group');
      return;
    }
    final nameCtrl = TextEditingController(text: widget.group['name']?.toString() ?? '');
    final descCtrl = TextEditingController(text: widget.group['description']?.toString() ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Group', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Group Name',
              labelStyle: const TextStyle(color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.surface2.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Description',
              labelStyle: const TextStyle(color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.surface2.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () async {
              final groupId = _groupId;
              final name = nameCtrl.text.trim();
              if (groupId == null || name.isEmpty) return;
              final r = await widget.apiService.updateGroup(
                groupId,
                name: name,
                description: descCtrl.text.trim(),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              if (r['success'] == true) {
                AppToast.success(context, 'Group updated');
                widget.onGroupUpdated();
              } else {
                AppToast.error(context, r['error']?.toString() ?? 'Could not update group');
              }
            },
            style: AppTheme.primaryElevatedButton(),
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showAddMembers() {
    if (!_canManage) {
      AppToast.error(context, 'Only group admins can add members');
      return;
    }
    final memberUserIds = _members.map(_membershipUserId).whereType<int>().toSet();
    final available = widget.users.where((u) {
      if (u is! Map) return false;
      final id = _chatInt(u['id']);
      return id != null && !memberUserIds.contains(id);
    }).toList();
    final selectedIds = <int>{};

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: AppTheme.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Members', style: TextStyle(color: AppTheme.textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: available.isEmpty
                ? const Text('No available members to add', style: TextStyle(color: AppTheme.textMuted))
                : Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: available.length,
                      itemBuilder: (_, i) {
                        final u = available[i] as Map;
                        final uid = _chatInt(u['id']);
                        if (uid == null) return const SizedBox.shrink();
                        return CheckboxListTile(
                          dense: true,
                          value: selectedIds.contains(uid),
                          onChanged: (v) => setDState(() {
                            if (v == true) {
                              selectedIds.add(uid);
                            } else {
                              selectedIds.remove(uid);
                            }
                          }),
                          title: Text(
                            '${u['full_name'] ?? u['username'] ?? 'User'}',
                            style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.85), fontSize: 14),
                          ),
                          activeColor: AppTheme.primary,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
            ElevatedButton(
              onPressed: () async {
                if (selectedIds.isEmpty) {
                  Navigator.pop(dialogCtx);
                  return;
                }
                final groupId = _groupId;
                if (groupId == null) return;
                setState(() => _saving = true);
                final r = await widget.apiService.addGroupMembers(groupId, selectedIds.toList());
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                if (!mounted) return;
                setState(() => _saving = false);
                if (r['success'] == true) {
                  AppToast.success(context, 'Members added');
                  await _loadMembers();
                  widget.onGroupUpdated();
                } else {
                  AppToast.error(context, r['error']?.toString() ?? 'Could not add members');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Members', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setMemberRole(int userId, String role) async {
    final groupId = _groupId;
    if (groupId == null) return;
    setState(() => _saving = true);
    final r = await widget.apiService.updateGroupMemberRole(groupId, userId, role);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      AppToast.success(context, role == 'admin' ? 'Made admin' : 'Role updated');
      await _loadMembers();
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Could not update member');
    }
  }

  Future<void> _removeMember(Map<String, dynamic> m) async {
    final uid = _membershipUserId(m);
    final groupId = _groupId;
    if (uid == null || groupId == null) {
      AppToast.error(context, 'Invalid member');
      return;
    }
    final name = (m['full_name'] ?? m['username'] ?? 'this member').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
        title: const Text('Remove member?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Remove $name from this group?', style: const TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final r = await widget.apiService.removeGroupMember(groupId, uid);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      AppToast.success(context, 'Member removed');
      await _loadMembers();
      widget.onGroupUpdated();
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Could not remove member');
    }
  }

  void _confirmDeleteGroup() {
    if (!_canManage) {
      AppToast.error(context, 'Only group admins can delete this group');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Group?', style: TextStyle(color: AppTheme.danger)),
        content: const Text('This action cannot be undone.', style: TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () async {
              final groupId = _groupId;
              if (groupId == null) return;
              final r = await widget.apiService.deleteGroup(groupId);
              if (ctx.mounted) Navigator.pop(ctx);
              if (!mounted) return;
              if (r['success'] == true) {
                Navigator.pop(context);
                widget.onGroupDeleted();
                AppToast.success(context, 'Group deleted');
              } else {
                AppToast.error(context, r['error']?.toString() ?? 'Could not delete group');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
