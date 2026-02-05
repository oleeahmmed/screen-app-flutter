// chat_page.dart - Chat Page with Fixed Endpoints

import 'package:flutter/material.dart';
import '../config.dart';
import '../services/api_service.dart';

class ChatPage extends StatefulWidget {
  final ApiService apiService;

  const ChatPage({required this.apiService});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<dynamic> _users = [];
  dynamic _selectedUser;
  List<dynamic> _messages = [];
  final _messageController = TextEditingController();
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final result = await widget.apiService.getChatUsers();
    if (result['success']) {
      setState(() {
        _users = result['data'] ?? [];
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load users: ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadConversation(dynamic user) async {
    final result = await widget.apiService.getConversation(user['id']);
    if (result['success']) {
      setState(() {
        _selectedUser = user;
        _messages = result['data'] ?? [];
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load conversation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty || _selectedUser == null) return;

    final msg = _messageController.text;
    _messageController.clear();

    setState(() => _isSending = true);

    print('📤 Sending message to ${_selectedUser['username']}: $msg');

    final result =
        await widget.apiService.sendMessage(_selectedUser['id'], msg);
    
    setState(() => _isSending = false);

    if (result['success']) {
      print('✅ Message sent successfully');
      // Add message to local list immediately
      setState(() {
        _messages.add({
          'message': msg,
          'is_own': true,
          'timestamp': DateTime.now().toString(),
          'sender_username': 'You',
        });
      });
      _scrollToBottom();
    } else {
      print('❌ Failed to send: ${result['error']}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(Duration(milliseconds: 100), () {
      // Scroll to bottom if needed
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(int.parse('0xFF2563eb')),
            Color(int.parse('0xFF1e40af')),
            Color(int.parse('0xFF1e3a5f')),
            Color(int.parse('0xFF0f172a')),
          ],
        ),
      ),
      child: SafeArea(
        child: _selectedUser == null ? _buildUsersList() : _buildChatView(),
      ),
    );
  }

  Widget _buildUsersList() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CHAT',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              GestureDetector(
                onTap: _loadUsers,
                child: Icon(Icons.refresh, color: Colors.white54, size: 24),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : _users.isEmpty
                  ? Center(
                      child: Text(
                        'No users available',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(20),
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return GestureDetector(
                          onTap: () => _loadConversation(user),
                          child: Container(
                            margin: EdgeInsets.only(bottom: 12),
                            padding: EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor:
                                      Color(int.parse('0xFF2196F3')),
                                  child: Text(
                                    (user['username'] ?? 'U')[0]
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user['username'] ?? 'User',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (user['full_name'] != null)
                                        Text(
                                          user['full_name'],
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white54,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios,
                                    color: Colors.white54, size: 16),
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

  Widget _buildChatView() {
    return Column(
      children: [
        // Header
        Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedUser = null),
                child: Icon(Icons.arrow_back, color: Colors.white, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedUser['username'] ?? 'Chat',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (_selectedUser['full_name'] != null)
                      Text(
                        _selectedUser['full_name'],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    'No messages yet\nStart the conversation!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isOwn = msg['is_own'] ?? (msg['sender_username'] == 'You');
                    return Align(
                      alignment: isOwn
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: EdgeInsets.only(bottom: 12),
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width * 0.65,
                        ),
                        decoration: BoxDecoration(
                          color: isOwn
                              ? Color(int.parse('0xFF10B981'))
                              : Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: isOwn
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['message'] ?? '',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              _formatTime(msg['timestamp'] ?? ''),
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Message Input
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  enabled: !_isSending,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: Color(int.parse('0xFF2196F3')),
                      ),
                    ),
                    hintStyle: TextStyle(color: Colors.white54),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                  maxLines: null,
                  onChanged: (value) {
                    setState(() {}); // Update send button state
                  },
                ),
              ),
              SizedBox(width: 12),
              GestureDetector(
                onTap: (_isSending || _messageController.text.isEmpty)
                    ? null
                    : _sendMessage,
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_isSending || _messageController.text.isEmpty)
                        ? Colors.white.withOpacity(0.2)
                        : Color(int.parse('0xFF10B981')),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: _isSending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(String timestamp) {
    try {
      if (timestamp.isEmpty) return '';
      final dt = DateTime.parse(timestamp);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}
