import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
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
  StreamSubscription<Map<String, dynamic>>? _presenceSub;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  Process? _recProcess;
  String? _recPath;
  VoiceRecorderService? _voiceRecorder;
  AudioPlayer? _audioPlayer;
  String? _playingUrl;

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
    _loadUsers();
    _usersPollTimer = Timer.periodic(const Duration(seconds: 25), (_) => _loadUsers(silent: true));
    _presenceSub = widget.notificationService?.presenceStream.listen(_onPresenceUpdate);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _usersPollTimer?.cancel();
    _presenceSub?.cancel();
    _recordTimer?.cancel();
    _recProcess?.kill();
    _voiceRecorder?.dispose();
    _audioPlayer?.dispose();
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
        _users = result['data'] ?? [];
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
    setState(() { _selectedUser = user; _selectedGroup = null; _messages = []; });
    _startRefresh();
    final result = await widget.apiService.getConversation(user['id']);
    if (result['success']) {
      setState(() => _messages = result['data'] ?? []);
      _scrollToBottom();
      widget.apiService.markMessagesRead(user['id']);
    }
  }

  Future<void> _selectGroup(dynamic group) async {
    setState(() { _selectedGroup = group; _selectedUser = null; _messages = []; });
    _startRefresh();
    final result = await widget.apiService.getGroupMessages(group['id']);
    if (result['success']) {
      setState(() => _messages = result['data'] ?? []);
      _scrollToBottom();
    }
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) => _silentRefresh());
  }

  Future<void> _silentRefresh() async {
    if (_selectedUser != null) {
      final r = await widget.apiService.getConversation(_selectedUser['id']);
      if (r['success'] && mounted) setState(() => _messages = r['data'] ?? []);
    } else if (_selectedGroup != null) {
      final r = await widget.apiService.getGroupMessages(_selectedGroup['id']);
      if (r['success'] && mounted) setState(() => _messages = r['data'] ?? []);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;
    if (_selectedUser == null && _selectedGroup == null) return;

    _msgController.clear();
    setState(() => _isSending = true);

    Map<String, dynamic> result;
    if (_selectedUser != null) {
      result = await widget.apiService.sendMessage(_selectedUser['id'], text);
    } else {
      result = await widget.apiService.sendGroupMessage(_selectedGroup['id'], text);
    }

    if (!mounted) return;
    setState(() => _isSending = false);
    if (result['success'] == true) {
      setState(() {
        _messages.add(result['data'] ?? {
          'message': text,
          'is_own': true,
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

  // ─── Pick & Send Image ───
  Future<void> _pickImage() async {
    if (_selectedUser == null) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      final file = File(result.files.first.path!);
      setState(() => _isSending = true);
      final bytes = await file.readAsBytes();
      final r = await widget.apiService.sendImageMessage(_selectedUser['id'], bytes, result.files.first.name);
      setState(() => _isSending = false);
      if (r['success']) { _refreshMessages(); } else { _showError('Failed to send image'); }
    }
  }

  // ─── Pick & Send File ───
  Future<void> _pickFile() async {
    if (_selectedUser == null) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      final pf = result.files.first;
      if (pf.size > 10 * 1024 * 1024) { _showError('File must be under 10MB'); return; }
      final file = File(pf.path!);
      setState(() => _isSending = true);
      final bytes = await file.readAsBytes();
      final r = await widget.apiService.sendFileMessage(_selectedUser['id'], bytes, pf.name);
      setState(() => _isSending = false);
      if (r['success']) { _refreshMessages(); } else { _showError(r['error'] ?? 'Failed to send file'); }
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
        final designation = user['designation'] ?? 'Employee';
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
                        Text(name, style: TextStyle(
                          fontSize: immersive ? 16 : 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.textPrimary.withValues(alpha: 0.92),
                        ), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(designation, style: TextStyle(
                          fontSize: 13, color: AppTheme.textMuted.withValues(alpha: 0.9),
                        ), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (unread > 0)
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
                                      Text(name, style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w600,
                                        color: isSelected ? Colors.white : AppTheme.textPrimary.withValues(alpha: 0.85),
                                      ), overflow: TextOverflow.ellipsis),
                                      Text('$members members', style: TextStyle(
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
    final subtitle = isGroup
        ? '${_selectedGroup['member_count'] ?? 0} members'
        : (isOnline ? 'Online' : 'Offline');
    final headerUid = !isGroup && _selectedUser != null
        ? (_selectedUser['id'] is int ? _selectedUser['id'] as int : int.tryParse('${_selectedUser['id']}') ?? 0)
        : 0;

    return Column(
      children: [
        Container(
          height: PlatformCapabilities.immersiveChatChrome ? 64 : 72,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xE60F172A),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Row(
            children: [
              if (!isWide)
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => setState(() {
                    _selectedUser = null;
                    _selectedGroup = null;
                    _refreshTimer?.cancel();
                  }),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
                ),
              if (isGroup)
                Container(
                  width: 42, height: 42,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.primaryBright]),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(child: Icon(Icons.group, color: Colors.white, size: 20)),
                )
              else
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: _avatarColor(headerUid),
                      child: Text(_initials(name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
                    ), overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: TextStyle(
                      fontSize: 12,
                      color: isOnline ? const Color(0xFF34D399) : AppTheme.textMuted,
                    )),
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF20B1220),
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.2,
                colors: [
                  AppTheme.primary.withValues(alpha: 0.07),
                  Colors.transparent,
                ],
              ),
            ),
            child: _messages.isEmpty
                ? _buildEmpty('No messages yet\nStart the conversation!')
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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

  /// WhatsApp-style multi-line composer (Enter = newline; send via button / Ctrl+Enter).
  Widget _buildMessageComposer() {
    final mobile = Responsive.isMobile(context);
    final hasText = _hasDraft;

    return Container(
      padding: EdgeInsets.fromLTRB(mobile ? 8 : 14, 8, mobile ? 8 : 14, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.42),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (mobile)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: PopupMenuButton<String>(
                  tooltip: 'Attach',
                  icon: Icon(Icons.add_circle_rounded, color: AppTheme.textMuted.withValues(alpha: 0.95), size: 28),
                  color: AppTheme.surface2,
                  onSelected: (v) {
                    if (v == 'image') _pickImage();
                    else if (v == 'file') _pickFile();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'image',
                      child: Row(children: [
                        Icon(Icons.photo_outlined, size: 18, color: AppTheme.textPrimary),
                        SizedBox(width: 10),
                        Text('Photo', style: TextStyle(color: AppTheme.textPrimary)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'file',
                      child: Row(children: [
                        Icon(Icons.attach_file_rounded, size: 18, color: AppTheme.textPrimary),
                        SizedBox(width: 10),
                        Text('Document', style: TextStyle(color: AppTheme.textPrimary)),
                      ]),
                    ),
                  ],
                ),
              )
            else ...[
              IconButton(
                onPressed: _pickImage,
                tooltip: 'Photo',
                icon: const Icon(Icons.photo_outlined, color: AppTheme.textMuted, size: 22),
              ),
              IconButton(
                onPressed: _pickFile,
                tooltip: 'Document',
                icon: const Icon(Icons.attach_file_rounded, color: AppTheme.textMuted, size: 22),
              ),
            ],
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter, control: true): _sendMessage,
                  const SingleActivator(LogicalKeyboardKey.enter, meta: true): _sendMessage,
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44, maxHeight: 140),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _msgFocus.hasFocus
                          ? AppTheme.primaryBright.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: TextField(
                    controller: _msgController,
                    focusNode: _msgFocus,
                    enabled: !_isSending,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      height: 1.35,
                    ),
                    cursorColor: AppTheme.primaryBright,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Message',
                      hintStyle: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.65),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isSending
                      ? null
                      : (hasText ? _sendMessage : _toggleRecording),
                  customBorder: const CircleBorder(),
                  child: Ink(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: hasText
                            ? const [Color(0xFF5B9CFF), Color(0xFF2563EB)]
                            : [AppTheme.primary.withValues(alpha: 0.9), AppTheme.primary],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _isSending
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(
                            hasText ? Icons.send_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
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

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        child: GestureDetector(
          onLongPress: isOwn && !isDeleted ? () => _showMessageOptions(msg) : null,
          child: Column(
            crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isOwn ? const Color(0xFF2563EB) : const Color(0xE00F172A),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isOwn ? 18 : 4),
                    bottomRight: Radius.circular(isOwn ? 4 : 18),
                  ),
                  border: isOwn ? null : Border.all(color: const Color(0x1F93C5FD)),
                  boxShadow: isOwn
                      ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.25), blurRadius: 12)]
                      : [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8)],
                ),
                child: Column(
                  crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (!isOwn && isGroup)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(senderName, style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.75),
                        )),
                      ),
                    if (isDeleted)
                      Text('🗑️ This message was deleted', style: TextStyle(color: Colors.white.withValues(alpha: 0.54), fontSize: 14, fontStyle: FontStyle.italic))
                    else if (msgType == 'voice' && voiceUrl != null)
                      GestureDetector(
                        onTap: () => _playVoice(voiceUrl),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_playingUrl == voiceUrl ? Icons.stop_circle : Icons.play_circle_fill, color: isOwn ? Colors.white : AppTheme.primary, size: 28),
                          const SizedBox(width: 8),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Voice Message', style: TextStyle(color: isOwn ? Colors.white : AppTheme.textPrimary.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600)),
                            Text(_playingUrl == voiceUrl ? 'Playing...' : 'Tap to play', style: TextStyle(color: Colors.white.withValues(alpha: 0.54), fontSize: 10)),
                          ]),
                        ]),
                      )
                    else if (msgType == 'image' && imageUrl != null)
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(imageUrl, width: 220, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 220, height: 100, color: Colors.white10, child: const Icon(Icons.broken_image, color: Colors.white38))),
                        ),
                        if (text.isNotEmpty) ...[const SizedBox(height: 6), Text(text, style: TextStyle(color: isOwn ? Colors.white : AppTheme.textPrimary.withValues(alpha: 0.9), fontSize: 14))],
                      ])
                    else if (msgType == 'file' && fileUrl != null)
                      GestureDetector(
                        onTap: () => _openFileUrl(fileUrl),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.insert_drive_file, color: AppTheme.primaryBright, size: 24),
                          const SizedBox(width: 8),
                          Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(fileName, style: TextStyle(color: isOwn ? Colors.white : AppTheme.textPrimary.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('Tap to download', style: TextStyle(color: Colors.white.withValues(alpha: 0.54), fontSize: 10)),
                          ])),
                        ]),
                      )
                    else
                      Text(
                        text.toString(),
                        softWrap: true,
                        style: TextStyle(
                          color: isOwn ? Colors.white : const Color(0xFFE4E4E7),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    if (isOwn) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isEdited)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text('edited', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5), fontStyle: FontStyle.italic)),
                            ),
                          Text(time, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.65))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!isOwn) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(time, style: TextStyle(fontSize: 10, color: AppTheme.textMuted.withValues(alpha: 0.9))),
                ),
              ],
            ],
          ),
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

  // ─── Message Options (Edit/Delete) ───
  void _showMessageOptions(dynamic msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppTheme.textMuted, borderRadius: BorderRadius.circular(2))),
            if (msg['message_type'] == 'text' || msg['message_type'] == null)
              ListTile(
                leading: Icon(Icons.edit, color: AppTheme.primary),
                title: Text('Edit Message', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () { Navigator.pop(context); _showEditDialog(msg); },
              ),
            ListTile(
              leading: Icon(Icons.delete, color: AppTheme.danger),
              title: Text('Delete Message', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () { Navigator.pop(context); _deleteMessage(msg); },
            ),
            SizedBox(height: 8),
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
