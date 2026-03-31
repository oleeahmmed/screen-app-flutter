import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';

// ═══════════════════════════════════════════════════════════════
// Colors matching Django glassmorphism theme
// ═══════════════════════════════════════════════════════════════
class _C {
  static const bgDark = Color(0xFF0F172A);
  static const blue = Color(0xFF3B82F6);
  static const blueDark = Color(0xFF2563EB);
  static const textMain = Color(0xFFF8FAFC);
  static const textMuted = Color(0xFF94A3B8);
  static const inputBg = Color(0x990F172A);
  static const inputBorder = Color(0x1AFFFFFF);
  static const red = Color(0xFFEF4444);
  static const green = Color(0xFF22C55E);
  static const glassBorder = Color(0x14FFFFFF);
}

class ChatPage extends StatefulWidget {
  final ApiService apiService;
  const ChatPage({required this.apiService});
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
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  Process? _recProcess;
  String? _recPath;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingUrl;

  final _msgController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _recordTimer?.cancel();
    _recProcess?.kill();
    _audioPlayer.dispose();
    _msgController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Data Loading ───
  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    final result = await widget.apiService.getChatUsers();
    if (result['success']) {
      setState(() { _users = result['data'] ?? []; _isLoadingUsers = false; });
    } else {
      setState(() => _isLoadingUsers = false);
      _showError('Failed to load users');
    }
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
    if (text.isEmpty) return;
    _msgController.clear();
    setState(() => _isSending = true);

    Map<String, dynamic> result;
    if (_selectedUser != null) {
      result = await widget.apiService.sendMessage(_selectedUser['id'], text);
    } else if (_selectedGroup != null) {
      result = await widget.apiService.sendGroupMessage(_selectedGroup['id'], text);
    } else {
      return;
    }

    setState(() => _isSending = false);
    if (result['success']) {
      setState(() {
        _messages.add(result['data'] ?? {
          'message': text, 'is_own': true,
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
      _scrollToBottom();
    } else {
      _showError('Failed to send message');
    }
  }

  // ─── Voice Recording (Windows PowerShell) ───
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndSendRecording();
    } else {
      final dir = await getTemporaryDirectory();
      _recPath = '${dir.path}\\voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      // Use PowerShell with .NET to record audio via MCI in a single script
      // The script records until a stop file is created
      final stopFile = '${dir.path}\\stop_rec.flag';
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
    setState(() { _isRecording = false; });
    
    // Create stop flag file to signal PowerShell to stop
    final dir = await getTemporaryDirectory();
    final stopFile = File('${dir.path}\\stop_rec.flag');
    await stopFile.writeAsString('stop');
    
    // Wait for PowerShell to save the file
    await Future.delayed(Duration(seconds: 2));
    _recProcess?.kill();
    
    if (_recPath != null && _selectedUser != null) {
      final file = File(_recPath!);
      if (await file.exists() && await file.length() > 1000) {
        setState(() => _isSending = true);
        final bytes = await file.readAsBytes();
        print('🎤 Voice file: ${bytes.length} bytes');
        final result = await widget.apiService.sendVoiceMessage(
          _selectedUser['id'], bytes, 'voice_${DateTime.now().millisecondsSinceEpoch}.wav');
        setState(() => _isSending = false);
        if (result['success']) {
          print('✅ Voice sent successfully');
          _refreshMessages();
        } else {
          print('❌ Voice send failed: ${result['error']}');
          _showError('Failed to send voice');
        }
        await file.delete().catchError((_) {});
      } else {
        print('❌ Voice file not found or too small');
        _showError('Recording failed - try again');
      }
    }
    setState(() => _recordSeconds = 0);
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
    if (_playingUrl == url) { await _audioPlayer.stop(); setState(() => _playingUrl = null); return; }
    setState(() => _playingUrl = url);
    await _audioPlayer.play(UrlSource(url));
    _audioPlayer.onPlayerComplete.listen((_) { if (mounted) setState(() => _playingUrl = null); });
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
        SnackBar(content: Text(msg), backgroundColor: _C.red),
      );
    }
  }

  void _showSuccess(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: _C.green),
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
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    final hasChat = _selectedUser != null || _selectedGroup != null;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.bgDark, Color(0xFF1E293B), Color(0xFF162032)],
        ),
      ),
      child: SafeArea(
        child: isWide
            ? Row(children: [
                SizedBox(width: MediaQuery.of(context).size.width * 0.35, child: _buildSidebar()),
                Container(width: 1, color: _C.glassBorder),
                Expanded(child: hasChat ? _buildChatArea() : _buildEmptyState()),
              ])
            : hasChat ? _buildChatArea() : _buildSidebar(),
      ),
    );
  }

  // ─── LEFT SIDEBAR ───
  Widget _buildSidebar() {
    return Column(
      children: [
        // Tabs: Direct | Groups
        Container(
          decoration: BoxDecoration(
            color: Color(0x80111827),
            border: Border(bottom: BorderSide(color: _C.glassBorder)),
          ),
          child: Row(
            children: [
              _buildTab('Direct', Icons.person, 'direct'),
              _buildTab('Groups', Icons.group, 'group'),
            ],
          ),
        ),
        // Search
        Padding(
          padding: EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            style: TextStyle(color: _C.textMain, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: TextStyle(color: _C.textMuted, fontSize: 14),
              filled: true,
              fillColor: _C.inputBg,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _C.inputBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _C.inputBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _C.blue),
              ),
              prefixIcon: Icon(Icons.search, color: _C.textMuted, size: 20),
            ),
          ),
        ),
        // List
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
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? _C.blue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isActive ? _C.blue : _C.textMuted),
              SizedBox(width: 8),
              Text(label, style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: isActive ? _C.blue : _C.textMuted,
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

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final user = filtered[i];
        final isSelected = _selectedUser != null && _selectedUser['id'] == user['id'];
        final isOnline = user['is_online'] == true;
        final unread = user['unread_count'] ?? 0;
        final name = user['full_name'] ?? user['username'] ?? 'User';
        final designation = user['designation'] ?? 'Employee';

        return GestureDetector(
          onTap: () => _selectUser(user),
          child: Container(
            margin: EdgeInsets.only(bottom: 4),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Color(0x333B82F6) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Color(0x4D3B82F6) : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                // Avatar with online dot
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Color(0xFF334155),
                      child: Text(name[0].toUpperCase(),
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: isOnline ? _C.green : _C.textMuted,
                          shape: BoxShape.circle,
                          border: Border.all(color: _C.bgDark, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Color(0xFFCBD5E1),
                      ), overflow: TextOverflow.ellipsis),
                      Text(designation, style: TextStyle(
                        fontSize: 12, color: _C.textMuted,
                      ), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (unread > 0)
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(color: _C.red, shape: BoxShape.circle),
                    child: Center(child: Text('$unread',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Groups List ───
  Widget _buildGroupsList() {
    return Column(
      children: [
        // Create Group button
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showCreateGroupDialog,
              icon: Icon(Icons.add, size: 18),
              label: Text('Create Group', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
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
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                            margin: EdgeInsets.only(bottom: 4),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? Color(0x333B82F6) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Color(0x4D3B82F6) : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Group avatar
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [_C.blue, _C.blueDark],
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
                                        color: isSelected ? Colors.white : Color(0xFFCBD5E1),
                                      ), overflow: TextOverflow.ellipsis),
                                      Text('$members members', style: TextStyle(
                                        fontSize: 12, color: _C.textMuted,
                                      )),
                                    ],
                                  ),
                                ),
                                if (unread > 0)
                                  Container(
                                    width: 20, height: 20,
                                    decoration: BoxDecoration(color: _C.red, shape: BoxShape.circle),
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
    final isWide = MediaQuery.of(context).size.width > 600;
    final isGroup = _selectedGroup != null;
    final name = isGroup
        ? (_selectedGroup['name'] ?? 'Group')
        : (_selectedUser['full_name'] ?? _selectedUser['username'] ?? 'Chat');
    final subtitle = isGroup
        ? '${_selectedGroup['member_count'] ?? 0} members'
        : (_selectedUser['designation'] ?? 'Employee');

    return Column(
      children: [
        // ─── Chat Header ───
        Container(
          height: 72,
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Color(0x1A1E293B),
            border: Border(bottom: BorderSide(color: _C.glassBorder)),
          ),
          child: Row(
            children: [
              if (!isWide)
                GestureDetector(
                  onTap: () => setState(() { _selectedUser = null; _selectedGroup = null; _refreshTimer?.cancel(); }),
                  child: Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.arrow_back_ios, color: _C.textMuted, size: 20),
                  ),
                ),
              // Avatar
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isGroup ? null : Color(0xFF475569),
                  gradient: isGroup ? LinearGradient(colors: [_C.blue, _C.blueDark]) : null,
                  shape: BoxShape.circle,
                ),
                child: Center(child: Icon(
                  isGroup ? Icons.group : Icons.person,
                  color: Colors.white, size: 20,
                )),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white,
                    ), overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: _C.textMuted)),
                  ],
                ),
              ),
              if (isGroup)
                GestureDetector(
                  onTap: () => _showGroupSettings(_selectedGroup),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                    ),
                    child: Icon(Icons.settings, color: _C.textMuted, size: 20),
                  ),
                ),
            ],
          ),
        ),

        // ─── Messages ───
        Expanded(
          child: _messages.isEmpty
              ? _buildEmpty('No messages yet\nStart the conversation!')
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _buildMessageBubble(_messages[i]),
                ),
        ),

        // ─── Input ───
        if (_isRecording) Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(color: Color(0x331E293B), border: Border(top: BorderSide(color: _C.glassBorder))),
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: _C.red),
              child: null),
            SizedBox(width: 8),
            Text('Recording ${_recordSeconds}s', style: TextStyle(color: _C.red, fontSize: 14, fontWeight: FontWeight.w600)),
            Spacer(),
            GestureDetector(onTap: _stopAndSendRecording, child: Container(width: 44, height: 44,
              decoration: BoxDecoration(color: _C.red, shape: BoxShape.circle),
              child: Icon(Icons.stop, color: Colors.white, size: 22))),
          ]),
        ) else Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0x331E293B),
            border: Border(top: BorderSide(color: _C.glassBorder)),
          ),
          child: Row(
            children: [
              // Attachment buttons
              GestureDetector(onTap: _pickImage, child: Padding(padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.image, color: _C.textMuted, size: 22))),
              GestureDetector(onTap: _pickFile, child: Padding(padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.attach_file, color: _C.textMuted, size: 22))),
              Expanded(
                child: TextField(
                  controller: _msgController,
                  enabled: !_isSending,
                  style: TextStyle(color: _C.textMain, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: _C.textMuted, fontSize: 14),
                    filled: true,
                    fillColor: _C.inputBg,
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: _C.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: _C.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: _C.blue),
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(width: 12),
              GestureDetector(
                onTap: _isSending ? null : (_msgController.text.trim().isEmpty ? _toggleRecording : _sendMessage),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _C.blue,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0x4D3B82F6), blurRadius: 12)],
                  ),
                  child: _isSending
                      ? Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_msgController.text.trim().isEmpty ? Icons.mic : Icons.send, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Message Bubble ───
  Widget _buildMessageBubble(dynamic msg) {
    final isOwn = msg['is_own'] == true;
    final isGroup = _selectedGroup != null;
    final senderName = msg['sender_username'] ?? msg['sender_full_name'] ?? '';
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
        margin: EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: GestureDetector(
          onLongPress: isOwn && !isDeleted ? () => _showMessageOptions(msg) : null,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: isOwn
                  ? LinearGradient(colors: [_C.blue, _C.blueDark], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
              color: isOwn ? null : Color(0x1AFFFFFF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: isOwn ? Radius.circular(18) : Radius.zero,
                bottomRight: isOwn ? Radius.zero : Radius.circular(18),
              ),
              border: isOwn ? null : Border.all(color: Color(0x0DFFFFFF)),
              boxShadow: isOwn ? [BoxShadow(color: Color(0x4D2563EB), blurRadius: 12)] : null,
            ),
            child: Column(
              crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isOwn && isGroup)
                  Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(senderName, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.75),
                    )),
                  ),
                // Message content based on type
                if (isDeleted) Text('🗑️ This message was deleted', style: TextStyle(color: Colors.white54, fontSize: 14, fontStyle: FontStyle.italic))
                else if (msgType == 'voice' && voiceUrl != null) GestureDetector(
                  onTap: () => _playVoice(voiceUrl),
                  child: Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_playingUrl == voiceUrl ? Icons.stop_circle : Icons.play_circle_fill, color: isOwn ? Colors.white : _C.blue, size: 28),
                      SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Voice Message', style: TextStyle(color: isOwn ? Colors.white : Color(0xFFE2E8F0), fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(_playingUrl == voiceUrl ? 'Playing...' : 'Tap to play', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      ]),
                    ])))
                else if (msgType == 'image' && imageUrl != null) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: Image.network(imageUrl, width: 200, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 200, height: 100, color: Colors.white10, child: Icon(Icons.broken_image, color: Colors.white38)))),
                  if (text.isNotEmpty) ...[SizedBox(height: 6), Text(text, style: TextStyle(color: isOwn ? Colors.white : Color(0xFFE2E8F0), fontSize: 14))],
                ])
                else if (msgType == 'file' && fileUrl != null) Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.insert_drive_file, color: _C.blue, size: 24),
                    SizedBox(width: 8),
                    Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(fileName, style: TextStyle(color: isOwn ? Colors.white : Color(0xFFE2E8F0), fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Tap to download', style: TextStyle(color: Colors.white54, fontSize: 10)),
                    ])),
                  ]))
                else Text(text, style: TextStyle(color: isOwn ? Colors.white : Color(0xFFE2E8F0), fontSize: 14, height: 1.5)),
                SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isEdited)
                      Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Text('edited', style: TextStyle(
                          fontSize: 10, color: Colors.white.withOpacity(0.5), fontStyle: FontStyle.italic,
                        )),
                      ),
                    Text(time, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Message Options (Edit/Delete) ───
  void _showMessageOptions(dynamic msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: _C.textMuted, borderRadius: BorderRadius.circular(2))),
            if (msg['message_type'] == 'text' || msg['message_type'] == null)
              ListTile(
                leading: Icon(Icons.edit, color: _C.blue),
                title: Text('Edit Message', style: TextStyle(color: _C.textMain)),
                onTap: () { Navigator.pop(context); _showEditDialog(msg); },
              ),
            ListTile(
              leading: Icon(Icons.delete, color: _C.red),
              title: Text('Delete Message', style: TextStyle(color: _C.textMain)),
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
        backgroundColor: Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Message', style: TextStyle(color: _C.textMain)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: _C.textMain),
          decoration: InputDecoration(
            filled: true, fillColor: _C.inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.inputBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.inputBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.blue)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _C.textMuted))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await widget.apiService.editMessage(msg['id'], controller.text);
              if (result['success']) { _silentRefresh(); _showSuccess('Message edited'); }
              else { _showError('Failed to edit'); }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _C.blue),
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
          backgroundColor: Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Create New Group', style: TextStyle(color: _C.textMain, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Group Name', style: TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: _C.textMain, fontSize: 14),
                    decoration: _dialogInputDecor('e.g., Development Team'),
                  ),
                  SizedBox(height: 16),
                  Text('Description (Optional)', style: TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    style: TextStyle(color: _C.textMain, fontSize: 14),
                    maxLines: 3,
                    decoration: _dialogInputDecor("What's this group about?"),
                  ),
                  SizedBox(height: 16),
                  Text('Add Members', style: TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Container(
                    constraints: BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: _C.inputBg,
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
                          title: Text(uname, style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14)),
                          activeColor: _C.blue,
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
              child: Text('Cancel', style: TextStyle(color: _C.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) { _showError('Group name is required'); return; }
                Navigator.pop(context);
                _createGroup(nameCtrl.text.trim(), descCtrl.text.trim(), selectedIds.toList());
              },
              style: ElevatedButton.styleFrom(backgroundColor: _C.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text('Create Group'),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: _C.textMuted, fontSize: 14),
    filled: true, fillColor: _C.inputBg,
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.inputBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.inputBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.blue)),
  );

  // ─── Group Settings ───
  void _showGroupSettings(dynamic group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Color(0xFF1E293B),
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
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: _C.textMuted, strokeWidth: 2),
      SizedBox(height: 12),
      Text(text, style: TextStyle(color: _C.textMuted, fontSize: 14)),
    ]),
  );

  Widget _buildEmpty(String text) => Center(
    child: Text(text, textAlign: TextAlign.center,
      style: TextStyle(color: _C.textMuted, fontSize: 14)),
  );

  Widget _buildEmptyState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.chat_bubble_outline, size: 48, color: _C.textMuted),
      SizedBox(height: 12),
      Text('Select a chat to start messaging',
        style: TextStyle(color: _C.textMuted, fontSize: 14)),
    ]),
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
          decoration: BoxDecoration(color: _C.textMuted, borderRadius: BorderRadius.circular(2)))),

        Text('Group Settings', style: TextStyle(color: _C.textMain, fontSize: 20, fontWeight: FontWeight.bold)),
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
          icon: Icon(Icons.edit, size: 14, color: _C.blue),
          label: Text('Edit', style: TextStyle(color: _C.blue, fontSize: 12)),
        )),
        SizedBox(height: 16),

        // ─── Members ───
        _settingsCard([
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Members (${_members.length})', style: TextStyle(color: _C.textMain, fontSize: 16, fontWeight: FontWeight.w600)),
              TextButton.icon(
                onPressed: _showAddMembers,
                icon: Icon(Icons.person_add, size: 14, color: _C.green),
                label: Text('Add', style: TextStyle(color: _C.green, fontSize: 12)),
              ),
            ],
          ),
          if (_loading)
            Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _C.textMuted)))
          else
            ..._members.map((m) => _memberTile(m)),
        ]),
        SizedBox(height: 16),

        // ─── Danger Zone ───
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0x1AEF4444),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(0x33EF4444)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Danger Zone', style: TextStyle(color: _C.red, fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('These actions cannot be undone.', style: TextStyle(color: _C.textMuted, fontSize: 13)),
              SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _confirmDeleteGroup,
                icon: Icon(Icons.delete, size: 16),
                label: Text('Delete Group'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.red,
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
      Text(label, style: TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      SizedBox(height: 4),
      Text(value, style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14)),
    ]),
  );

  Widget _memberTile(dynamic m) {
    final name = m['full_name'] ?? m['username'] ?? 'User';
    final role = m['role'] ?? 'member';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(radius: 16, backgroundColor: Color(0xFF334155),
            child: Text(name[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: 12))),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(color: _C.textMain, fontSize: 14)),
            Text(role, style: TextStyle(color: _C.textMuted, fontSize: 12)),
          ])),
          if (role != 'admin')
            GestureDetector(
              onTap: () => _removeMember(m),
              child: Icon(Icons.remove_circle_outline, color: _C.red, size: 20),
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
        backgroundColor: Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Group', style: TextStyle(color: _C.textMain)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: _C.textMain),
            decoration: InputDecoration(labelText: 'Group Name', labelStyle: TextStyle(color: _C.textMuted),
              filled: true, fillColor: _C.inputBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.inputBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.inputBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.blue)))),
          SizedBox(height: 12),
          TextField(controller: descCtrl, style: TextStyle(color: _C.textMain), maxLines: 3,
            decoration: InputDecoration(labelText: 'Description', labelStyle: TextStyle(color: _C.textMuted),
              filled: true, fillColor: _C.inputBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.inputBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.inputBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.blue)))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: _C.textMuted))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final r = await widget.apiService.updateGroup(widget.group['id'], nameCtrl.text.trim(), descCtrl.text.trim());
              if (r['success']) { widget.onGroupUpdated(); if (mounted) Navigator.pop(context); }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _C.blue),
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
          backgroundColor: Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Add Members', style: TextStyle(color: _C.textMain)),
          content: SizedBox(
            width: double.maxFinite,
            child: available.isEmpty
                ? Text('No available members to add', style: TextStyle(color: _C.textMuted))
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
                            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14)),
                          activeColor: _C.blue,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: _C.textMuted))),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                if (selectedIds.isNotEmpty) {
                  await widget.apiService.addGroupMembers(widget.group['id'], selectedIds.toList());
                  _loadMembers();
                  widget.onGroupUpdated();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _C.green),
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
        backgroundColor: Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Group?', style: TextStyle(color: _C.red)),
        content: Text('This action cannot be undone.', style: TextStyle(color: _C.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: _C.textMuted))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close settings sheet
              await widget.apiService.deleteGroup(widget.group['id']);
              widget.onGroupDeleted();
            },
            style: ElevatedButton.styleFrom(backgroundColor: _C.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }
}
