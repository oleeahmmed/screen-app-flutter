// api_service.dart - API Service

import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import '../config.dart';
import 'user_data_service.dart';

class ApiService {
  String? _token;

  // Initialize token from storage
  Future<void> initToken() async {
    _token = await UserDataService.getAuthToken();
    if (_token != null && _token!.isNotEmpty) {
      print('🔑 Token loaded from storage');
    }
  }

  void setToken(String token) {
    _token = token;
  }

  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
    };
  }

  Map<String, String> _authHeaderOnly() {
    return {
      if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
    };
  }

  /// DRF JSON: `{ "error": "..." }` or field errors `{"summary":["..."]}`.
  String _parseApiErrorBody(String body, int code) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) {
        final e = d['error'] ?? d['detail'];
        if (e != null) return e is String ? e : e.toString();
        final buf = StringBuffer();
        d.forEach((k, v) {
          if (v is List) {
            buf.write('$k: ${v.join(", ")} ');
          } else if (v != null) {
            buf.write('$k: $v ');
          }
        });
        if (buf.isNotEmpty) return buf.toString().trim();
      }
    } catch (_) {}
    return 'Request failed ($code)';
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      print('🔐 Logging in with: $email');
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/token/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': email, 'password': password}),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Login response: ${response.statusCode}');
      print('📝 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access'];
        
        // Check access_granted
        if (data['access_granted'] == false) {
          return {
            'success': false,
            'error': data['message'] ?? 'Access denied'
          };
        }
        
        return {'success': true, 'data': data};
      } else if (response.statusCode == 401) {
        return {'success': false, 'error': 'Invalid email or password'};
      }
      return {'success': false, 'error': 'Login failed: ${response.statusCode}'};
    } catch (e) {
      print('❌ Login error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> checkIn() async {
    try {
      print('✅ Checking in...');
      final response = await http
          .post(
            Uri.parse(AppConfig.checkInUrl),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Check-in response: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Check-in failed: ${response.statusCode}'};
    } catch (e) {
      print('❌ Check-in error: $e');
      return {'success': false, 'error': 'Check-in error: $e'};
    }
  }

  Future<Map<String, dynamic>> checkOut() async {
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
        print('❌ Checking out... (Attempt ${retryCount + 1}/$maxRetries)');
        
        var response = await http
            .post(
              Uri.parse(AppConfig.checkOutUrl),
              headers: _getHeaders(),
            )
            .timeout(Duration(seconds: 15));

        print('📊 Check-out response: ${response.statusCode}');
        print('📝 Response body: ${response.body}');

        // If 401, token might be expired
        if (response.statusCode == 401) {
          print('⚠️ Token expired, attempting refresh...');
          return {'success': false, 'error': 'Session expired - please login again'};
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          print('✅ Check-out successful');
          return {'success': true, 'data': data};
        } else if (response.statusCode == 400) {
          try {
            final data = jsonDecode(response.body);
            return {'success': false, 'error': data['message'] ?? 'No active check-in found'};
          } catch (e) {
            return {'success': false, 'error': 'No active check-in found'};
          }
        } else if (response.statusCode == 403) {
          return {'success': false, 'error': 'Access denied - subscription expired'};
        }
        
        // For other errors, retry
        retryCount++;
        if (retryCount < maxRetries) {
          print('⚠️ Retrying in 2 seconds...');
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
        
        return {'success': false, 'error': 'Check-out failed: ${response.statusCode}'};
        
      } on http.ClientException catch (e) {
        print('❌ Network error: $e');
        retryCount++;
        
        if (retryCount < maxRetries) {
          print('⚠️ Retrying in 2 seconds...');
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
        
        return {
          'success': false,
          'error': 'Network connection failed. Please check:\n'
              '1. Django server is running\n'
              '2. Server URL is correct (${AppConfig.checkOutUrl})\n'
              '3. Your internet connection'
        };
      } on TimeoutException catch (e) {
        print('❌ Timeout error: $e');
        retryCount++;
        
        if (retryCount < maxRetries) {
          print('⚠️ Retrying in 2 seconds...');
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
        
        return {
          'success': false,
          'error': 'Server timeout. Please check if Django server is running.'
        };
      } catch (e) {
        print('❌ Check-out error: $e');
        retryCount++;
        
        if (retryCount < maxRetries) {
          print('⚠️ Retrying in 2 seconds...');
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
        
        return {
          'success': false,
          'error': 'Check-out error: ${e.toString()}'
        };
      }
    }
    
    return {
      'success': false,
      'error': 'Failed after $maxRetries attempts. Please try again.'
    };
  }

  Future<Map<String, dynamic>> getTasks() async {
    try {
      print('📋 Loading tasks...');
      final response = await http
          .get(
            Uri.parse(AppConfig.tasksUrl),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Tasks response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load tasks'};
    } catch (e) {
      print('❌ Tasks error: $e');
      return {'success': false, 'error': 'Tasks error: $e'};
    }
  }

  Future<Map<String, dynamic>> toggleTask(int taskId) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.tasksUrl}$taskId/toggle/'),
            headers: _getHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      var err = 'Failed to toggle task';
      try {
        final d = jsonDecode(response.body);
        if (d is Map && d['error'] != null) err = d['error'].toString();
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': 'Toggle error: $e'};
    }
  }

  Future<Map<String, dynamic>> getTaskAttachments(int taskId) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.tasksUrl}$taskId/attachments/'),
            headers: _getHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data is List ? data : <dynamic>[]};
      }
      return {'success': false, 'error': 'Failed to load attachments'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> uploadTaskAttachment(
    int taskId,
    List<int> bytes,
    String filename,
  ) async {
    try {
      final uri = Uri.parse('${AppConfig.tasksUrl}$taskId/attachments/');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_authHeaderOnly());
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      var err = 'Upload failed';
      try {
        final d = jsonDecode(response.body);
        if (d is Map && d['error'] != null) err = d['error'].toString();
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getSubTaskAttachments(int taskId, int subtaskId) async {
    try {
      final url =
          '${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/attachments/';
      final response = await http
          .get(Uri.parse(url), headers: _getHeaders())
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data is List ? data : <dynamic>[]};
      }
      return {'success': false, 'error': 'Failed to load attachments'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> uploadSubTaskAttachment(
    int taskId,
    int subtaskId,
    List<int> bytes,
    String filename,
  ) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/attachments/',
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_authHeaderOnly());
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      var err = 'Upload failed';
      try {
        final d = jsonDecode(response.body);
        if (d is Map && d['error'] != null) err = d['error'].toString();
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getChatUsers() async {
    try {
      print('👥 Loading chat users...');
      print('🔗 URL: ${AppConfig.chatUsersUrl}');
      print('🔑 Token: ${_token != null && _token!.isNotEmpty ? "Present" : "Missing"}');
      
      final response = await http
          .get(
            Uri.parse(AppConfig.chatUsersUrl),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Chat users response: ${response.statusCode}');
      print('📝 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Successfully loaded ${(data as List).length} users');
        return {'success': true, 'data': data};
      } else if (response.statusCode == 401) {
        return {'success': false, 'error': 'Unauthorized - please login again'};
      } else if (response.statusCode == 403) {
        return {'success': false, 'error': 'Access denied - check subscription'};
      }
      return {'success': false, 'error': 'Failed to load users (${response.statusCode})'};
    } catch (e) {
      print('❌ Chat users error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> getConversation(int userId) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.chatConversationUrl}$userId/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load conversation'};
    } catch (e) {
      return {'success': false, 'error': 'Conversation error: $e'};
    }
  }

  Future<Map<String, dynamic>> sendMessage(int userId, String message) async {
    try {
      print('💬 Sending message to user $userId: $message');
      final response = await http
          .post(
            Uri.parse(AppConfig.chatSendUrl),
            headers: _getHeaders(),
            body: jsonEncode({
              'receiver_id': userId,
              'message': message,
            }),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Send message response: ${response.statusCode}');
      print('📝 Response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to send message: ${response.statusCode}'};
    } catch (e) {
      print('❌ Send message error: $e');
      return {'success': false, 'error': 'Send error: $e'};
    }
  }

  // ─── Mark Messages Read ───
  Future<Map<String, dynamic>> sendVoiceMessage(int userId, List<int> audioBytes, String filename) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(AppConfig.chatSendUrl));
      final headers = _getHeaders(); headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.fields['receiver_id'] = userId.toString();
      request.fields['message'] = '';
      request.files.add(http.MultipartFile.fromBytes('voice_message', audioBytes, filename: filename));
      var response = await request.send().timeout(Duration(seconds: 30));
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
      return {'success': false, 'error': 'Failed: ${response.statusCode}'};
    } catch (e) { return {'success': false, 'error': '$e'}; }
  }

  Future<Map<String, dynamic>> sendImageMessage(int userId, List<int> imageBytes, String filename, {String message = ''}) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(AppConfig.chatSendUrl));
      final headers = _getHeaders(); headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.fields['receiver_id'] = userId.toString();
      request.fields['message'] = message;
      request.files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: filename, contentType: MediaType('image', filename.endsWith('.png') ? 'png' : 'jpeg')));
      var response = await request.send().timeout(Duration(seconds: 30));
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
      return {'success': false, 'error': 'Failed: ${response.statusCode}'};
    } catch (e) { return {'success': false, 'error': '$e'}; }
  }

  Future<Map<String, dynamic>> sendFileMessage(int userId, List<int> fileBytes, String filename, {String message = ''}) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(AppConfig.chatSendUrl));
      final headers = _getHeaders(); headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.fields['receiver_id'] = userId.toString();
      request.fields['message'] = message;
      // Detect content type from filename extension
      final ext = filename.split('.').last.toLowerCase();
      final mimeTypes = {
        'pdf': 'application/pdf', 'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'txt': 'text/plain', 'csv': 'text/csv', 'json': 'application/json',
        'zip': 'application/zip', 'rar': 'application/x-rar-compressed',
        '7z': 'application/x-7z-compressed', 'gz': 'application/gzip',
        'mp4': 'video/mp4', 'mp3': 'audio/mpeg', 'wav': 'audio/wav',
        'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
        'gif': 'image/gif', 'webp': 'image/webp',
      };
      final mime = mimeTypes[ext] ?? 'application/octet-stream';
      final parts = mime.split('/');
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename,
        contentType: MediaType(parts[0], parts[1])));
      var response = await request.send().timeout(Duration(seconds: 60));
      final body = await response.stream.bytesToString();
      print('📎 File upload response: ${response.statusCode} - $body');
      if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
      return {'success': false, 'error': 'Failed: ${response.statusCode} - $body'};
    } catch (e) {
      print('❌ File send error: $e');
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> markMessagesRead(int senderId) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.chatMarkReadUrl),
            headers: _getHeaders(),
            body: jsonEncode({'sender_id': senderId}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to mark read'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Unread Count ───
  Future<Map<String, dynamic>> getUnreadCount() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.chatUnreadUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Edit Message ───
  Future<Map<String, dynamic>> editMessage(int messageId, String newText) async {
    try {
      final response = await http
          .patch(
            Uri.parse('${AppConfig.chatMessageDetailUrl}$messageId/'),
            headers: _getHeaders(),
            body: jsonEncode({'message': newText}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to edit message'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Delete Message ───
  Future<Map<String, dynamic>> deleteMessage(int messageId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.chatMessageDetailUrl}$messageId/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to delete message'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Group Chat APIs ───
  Future<Map<String, dynamic>> getChatGroups() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.chatGroupsUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load groups'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> createGroup(String name, String description, List<int> memberIds) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.chatGroupsUrl),
            headers: _getHeaders(),
            body: jsonEncode({
              'name': name,
              'description': description,
              'member_ids': memberIds,
            }),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to create group'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getGroupMessages(int groupId) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/messages/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load group messages'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> sendGroupMessage(int groupId, String message) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/messages/'),
            headers: _getHeaders(),
            body: jsonEncode({'message': message}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to send group message'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getGroupMembers(int groupId) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/members/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load members'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> addGroupMembers(int groupId, List<int> memberIds) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/members/'),
            headers: _getHeaders(),
            body: jsonEncode({'member_ids': memberIds}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to add members'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> removeGroupMember(int groupId, int memberId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/members/$memberId/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to remove member'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteGroup(int groupId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to delete group'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateGroup(int groupId, String name, String description) async {
    try {
      final response = await http
          .patch(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/'),
            headers: _getHeaders(),
            body: jsonEncode({'name': name, 'description': description}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to update group'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Create Task ───
  Future<Map<String, dynamic>> createTask({
    required String name,
    String description = '',
    String priority = 'medium',
    String? dueDate,
    int? projectId,
    int? stageId,
    bool isAttachmentRequired = false,
    List<int>? attachmentBytes,
    String? attachmentName,
  }) async {
    try {
      if (attachmentBytes != null && attachmentName != null) {
        // Multipart upload
        var request = http.MultipartRequest('POST', Uri.parse(AppConfig.tasksUrl));
        final headers = _getHeaders(); headers.remove('Content-Type');
        request.headers.addAll(headers);
        request.fields['name'] = name;
        request.fields['description'] = description;
        request.fields['priority'] = priority;
        request.fields['is_attachment_required'] = isAttachmentRequired.toString();
        if (dueDate != null) request.fields['due_date'] = dueDate;
        if (projectId != null) request.fields['project'] = projectId.toString();
        if (stageId != null) request.fields['stage'] = stageId.toString();
        request.files.add(http.MultipartFile.fromBytes('attachment', attachmentBytes, filename: attachmentName));
        var response = await request.send().timeout(Duration(seconds: 30));
        final body = await response.stream.bytesToString();
        if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
        return {'success': false, 'error': 'Failed: ${response.statusCode} - $body'};
      } else {
        final body = <String, dynamic>{
          'name': name,
          'description': description,
          'priority': priority,
          'is_attachment_required': isAttachmentRequired,
        };
        if (dueDate != null) body['due_date'] = dueDate;
        if (projectId != null) body['project'] = projectId;
        if (stageId != null) body['stage'] = stageId;

        final response = await http
            .post(Uri.parse(AppConfig.tasksUrl), headers: _getHeaders(), body: jsonEncode(body))
            .timeout(Duration(seconds: 10));
        if (response.statusCode == 200 || response.statusCode == 201) {
          return {'success': true, 'data': jsonDecode(response.body)};
        }
        return {'success': false, 'error': 'Failed to create task: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Update Task ───
  Future<Map<String, dynamic>> updateTask(int taskId, Map<String, dynamic> data) async {
    try {
      final response = await http
          .patch(Uri.parse('${AppConfig.tasksUrl}$taskId/'), headers: _getHeaders(), body: jsonEncode(data))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final err = body['error'] ?? body['detail'];
        if (err != null) {
          return {'success': false, 'error': err is String ? err : err.toString()};
        }
      } catch (_) {}
      return {'success': false, 'error': 'Failed to update task (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Delete Task ───
  Future<Map<String, dynamic>> deleteTask(int taskId) async {
    try {
      final response = await http
          .delete(Uri.parse('${AppConfig.tasksUrl}$taskId/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final err = body['error'] ?? body['detail'];
        if (err != null) {
          return {'success': false, 'error': err is String ? err : err.toString()};
        }
      } catch (_) {}
      return {'success': false, 'error': 'Failed to delete task (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── SubTask APIs ───
  Future<Map<String, dynamic>> getSubTasks(int taskId) async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load subtasks'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> createSubTask(int taskId, {
    required String summary,
    String description = '',
    String priority = 'medium',
    String status = 'to_do',
    int? assigneeId,
    String? dueDate,
    bool isAttachmentRequired = false,
    List<int>? attachmentBytes,
    String? attachmentName,
  }) async {
    try {
      if (attachmentBytes != null && attachmentName != null) {
        var request = http.MultipartRequest('POST', Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/'));
        final headers = _getHeaders(); headers.remove('Content-Type');
        request.headers.addAll(headers);
        request.fields['summary'] = summary;
        request.fields['description'] = description;
        request.fields['priority'] = priority;
        request.fields['status'] = status;
        request.fields['is_attachment_required'] = isAttachmentRequired.toString();
        if (dueDate != null) request.fields['due_date'] = dueDate;
        if (assigneeId != null) request.fields['assignee_id'] = assigneeId.toString();
        request.files.add(http.MultipartFile.fromBytes('attachment', attachmentBytes, filename: attachmentName));
        var response = await request.send().timeout(Duration(seconds: 30));
        final body = await response.stream.bytesToString();
        if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
        return {'success': false, 'error': _parseApiErrorBody(body, response.statusCode)};
      } else {
        final body = <String, dynamic>{
          'summary': summary,
          'description': description,
          'priority': priority,
          'status': status,
          'is_attachment_required': isAttachmentRequired,
        };
        if (dueDate != null) body['due_date'] = dueDate;
        if (assigneeId != null) body['assignee_id'] = assigneeId;

        final response = await http
            .post(Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/'), headers: _getHeaders(), body: jsonEncode(body))
            .timeout(Duration(seconds: 10));
        if (response.statusCode == 200 || response.statusCode == 201) {
          return {'success': true, 'data': jsonDecode(response.body)};
        }
        return {'success': false, 'error': _parseApiErrorBody(response.body, response.statusCode)};
      }
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateSubTask(int taskId, int subtaskId, Map<String, dynamic> data) async {
    try {
      final response = await http
          .patch(Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/'), headers: _getHeaders(), body: jsonEncode(data))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final err = body['error'] ?? body['detail'];
        if (err != null) {
          return {'success': false, 'error': err is String ? err : err.toString()};
        }
      } catch (_) {}
      return {'success': false, 'error': 'Failed to update subtask (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteSubTask(int taskId, int subtaskId) async {
    try {
      final response = await http
          .delete(Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to delete subtask'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> toggleSubTask(int taskId, int subtaskId) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/toggle/'),
            headers: _getHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      var err = 'Failed to toggle subtask';
      try {
        final d = jsonDecode(response.body);
        if (d is Map && d['error'] != null) err = d['error'].toString();
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Notification APIs ───
  Future<Map<String, dynamic>> getNotifications() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.notificationsUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load notifications'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getNotificationUnreadCount() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.notificationsUnreadUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> markAllNotificationsRead() async {
    try {
      final response = await http
          .post(Uri.parse(AppConfig.notificationsMarkAllReadUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Company APIs ───
  Future<Map<String, dynamic>> getCompanyDashboard() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.companyDashboardUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load company info'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getSubscriptionUsage() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.subscriptionUsageUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load usage'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Project APIs ───
  Future<Map<String, dynamic>> getProjectFiltersMeta() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.projectsMetaUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as Map<String, dynamic>};
      }
      return {'success': false, 'error': 'Failed to load filter options'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  /// Query params mirror web monitor: archived, customer_id, user_id, project_department_id, status, priority, search, sort.
  Future<Map<String, dynamic>> getProjects({
    bool archived = false,
    int? customerId,
    int? userId,
    int? projectDepartmentId,
    String? status,
    String? priority,
    String? search,
    String sort = 'newest',
  }) async {
    try {
      final params = <String, String>{'sort': sort};
      if (archived) params['archived'] = '1';
      if (customerId != null) params['customer_id'] = '$customerId';
      if (userId != null) params['user_id'] = '$userId';
      if (projectDepartmentId != null) {
        params['project_department_id'] = '$projectDepartmentId';
      }
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (priority != null && priority.isNotEmpty) params['priority'] = priority;
      if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();

      final uri = Uri.parse(AppConfig.projectsUrl).replace(queryParameters: params);
      final response = await http
          .get(uri, headers: _getHeaders())
          .timeout(Duration(seconds: 15));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load projects'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> archiveProject(int projectId) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.projectArchiveUrl(projectId)),
            headers: _getHeaders(),
            body: jsonEncode({}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> restoreProject(int projectId) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.projectRestoreUrl(projectId)),
            headers: _getHeaders(),
            body: jsonEncode({}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getProjectDetail(int projectId) async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.projectsUrl}$projectId/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load project'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Project CRUD ───
  Future<Map<String, dynamic>> createProject({
    required String name,
    String description = '',
    String priority = 'medium',
    List<Map<String, dynamic>>? stages,
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'description': description,
        'priority': priority,
      };
      if (stages != null) body['stages'] = stages;
      final response = await http
          .post(Uri.parse('${AppConfig.projectsUrl}create/'), headers: _getHeaders(), body: jsonEncode(body))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to create project'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateProject(int projectId, Map<String, dynamic> data) async {
    try {
      final response = await http
          .patch(Uri.parse('${AppConfig.projectsUrl}$projectId/update/'), headers: _getHeaders(), body: jsonEncode(data))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to update project'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteProject(int projectId) async {
    try {
      final response = await http
          .delete(Uri.parse('${AppConfig.projectsUrl}$projectId/update/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to delete project'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Stage CRUD ───
  Future<Map<String, dynamic>> createStage(int projectId, {required String name, String color = '#3B82F6'}) async {
    try {
      final response = await http
          .post(Uri.parse('${AppConfig.projectsUrl}$projectId/stages/'), headers: _getHeaders(), body: jsonEncode({'name': name, 'color': color}))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to create stage'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateStage(int projectId, int stageId, Map<String, dynamic> data) async {
    try {
      final response = await http
          .patch(Uri.parse('${AppConfig.projectsUrl}$projectId/stages/$stageId/'), headers: _getHeaders(), body: jsonEncode(data))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to update stage'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteStage(int projectId, int stageId) async {
    try {
      final response = await http
          .delete(Uri.parse('${AppConfig.projectsUrl}$projectId/stages/$stageId/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to delete stage'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> reorderStages(int projectId, List<int> stageIds) async {
    try {
      final response = await http
          .post(Uri.parse('${AppConfig.projectsUrl}$projectId/stages/reorder/'), headers: _getHeaders(), body: jsonEncode({'order': stageIds}))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to reorder stages'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> moveTask(int taskId, int stageId) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.tasksUrl}$taskId/move/'),
            headers: _getHeaders(),
            body: jsonEncode({'stage_id': stageId}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      var err = 'Failed to move task';
      try {
        final d = jsonDecode(response.body);
        if (d is Map && d['error'] != null) err = d['error'].toString();
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Access Check (verify token is still valid) ───
  Future<Map<String, dynamic>> accessCheck() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.accessCheckUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else if (response.statusCode == 403) {
        // Access denied but token is valid - return the error data
        return {'success': false, 'data': jsonDecode(response.body), 'error': 'Access denied'};
      }
      return {'success': false, 'error': 'Access check failed: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  /// Accept current data & monitoring notice (JWT). Sets server-side accepted version + optional screenshot consent.
  Future<Map<String, dynamic>> acceptPrivacyNotice({bool screenshotMonitoringConsent = true}) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.privacyNoticeAcceptUrl),
            headers: _getHeaders(),
            body: jsonEncode({'screenshot_monitoring_consent': screenshotMonitoringConsent}),
          )
          .timeout(const Duration(seconds: 15));
      final raw = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200 && raw is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(raw)};
      }
      final errMap = raw is Map ? raw : null;
      return {
        'success': false,
        'error': errMap != null ? (errMap['error'] ?? errMap['detail'] ?? 'Request failed') : 'Request failed',
      };
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> uploadScreenshot(
    List<int> imageBytes, {
    bool isIdle = false,
    int idleDuration = 0,
    String? lastActivityAt,
  }) async {
    try {
      print('📤 Uploading screenshot (${imageBytes.length} bytes)...');
      print('   Activity Status: ${isIdle ? "IDLE" : "ACTIVE"}');
      if (isIdle) {
        print('   Idle Duration: ${idleDuration}m');
      }
      
      // Create relative path with timestamp
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final time = '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final relativePath = '$date/screen1/$time.png';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.screenshotUploadUrl),
      );

      // Remove Content-Type from headers for multipart request
      final headers = _getHeaders();
      headers.remove('Content-Type');
      request.headers.addAll(headers);
      
      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: '$time.png',
          contentType: MediaType('image', 'png'),
        ),
      );
      
      // Add fields
      request.fields['relative_path'] = relativePath;
      request.fields['is_idle'] = isIdle.toString();
      request.fields['idle_duration'] = idleDuration.toString();
      if (lastActivityAt != null) {
        request.fields['last_activity_at'] = lastActivityAt;
      }
      
      print('📋 Upload URL: ${AppConfig.screenshotUploadUrl}');
      print('📋 Relative path: $relativePath');
      print('📋 File size: ${imageBytes.length} bytes');
      print('📋 Is Idle: $isIdle');
      print('📋 Idle Duration: ${idleDuration}m');
      
      var response = await request.send().timeout(Duration(seconds: 60));
      final responseBody = await response.stream.bytesToString();
      
      print('📊 Upload response: ${response.statusCode}');
      print('📝 Response body: ${responseBody.length > 200 ? responseBody.substring(0, 200) : responseBody}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': responseBody};
      } else {
        // Extract error message - handle both JSON and HTML responses
        String errorMsg = 'Upload failed: ${response.statusCode}';
        try {
          final json = jsonDecode(responseBody);
          errorMsg = json['error'] ?? json['errors']?.toString() ?? errorMsg;
        } catch (_) {
          // HTML error page - just use status code
        }
        return {'success': false, 'error': errorMsg};
      }
    } catch (e) {
      print('❌ Upload error: $e');
      return {'success': false, 'error': 'Upload error: $e'};
    }
  }

  Future<Map<String, dynamic>> updateActivityStatus(bool isActive) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/attendance/activity/'),
            headers: _getHeaders(),
            body: jsonEncode({'is_active': isActive}),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Activity update failed: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': 'Activity error: $e'};
    }
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      print('👤 Getting user profile...');
      final response = await http
          .get(
            Uri.parse(AppConfig.profileUrl),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Profile response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load profile: ${response.statusCode}'};
    } catch (e) {
      print('❌ Profile error: $e');
      return {'success': false, 'error': 'Profile error: $e'};
    }
  }

  Future<Map<String, dynamic>> patchUserProfile(Map<String, dynamic> body) async {
    try {
      final response = await http
          .patch(
            Uri.parse(AppConfig.profileUrl),
            headers: _getHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      String err = 'Update failed (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          err = '${decoded['error']}';
        } else if (decoded is Map && decoded['detail'] != null) {
          err = '${decoded['detail']}';
        }
      } catch (_) {
        if (response.body.isNotEmpty) err = response.body;
      }
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateUserProfile({
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    try {
      print('✏️ Updating user profile...');
      final response = await http
          .put(
            Uri.parse(AppConfig.profileUrl),
            headers: _getHeaders(),
            body: jsonEncode({
              'email': email,
              'first_name': firstName ?? '',
              'last_name': lastName ?? '',
            }),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Update profile response: ${response.statusCode}');
      print('📝 Response: ${response.body}');

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to update profile: ${response.statusCode}'};
    } catch (e) {
      print('❌ Update profile error: $e');
      return {'success': false, 'error': 'Update error: $e'};
    }
  }

  Future<Map<String, dynamic>> uploadProfilePhoto(List<int> imageBytes) async {
    try {
      print('📤 Uploading profile photo...');
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.uploadPhotoUrl),
      );

      request.headers.addAll(_authHeaderOnly());
      
      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'profile_photo',
          imageBytes,
          filename: 'profile.jpg',
        ),
      );

      var response = await request.send().timeout(Duration(seconds: 30));
      
      print('📊 Upload photo response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        print('✅ Profile photo uploaded: $responseBody');
        return {'success': true, 'data': jsonDecode(responseBody)};
      } else {
        final responseBody = await response.stream.bytesToString();
        print('❌ Upload failed: ${response.statusCode} - $responseBody');
        return {'success': false, 'error': 'Upload failed: ${response.statusCode}'};
      }
    } catch (e) {
      print('❌ Upload photo error: $e');
      return {'success': false, 'error': 'Upload error: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Peer-to-Peer File Transfer APIs
  // ═══════════════════════════════════════════════════════════════

  String? get token => _token;

  Future<Map<String, dynamic>> p2pCreateSession({String fileName = '', int fileSize = 0, int? receiverId}) async {
    try {
      final body = <String, dynamic>{
        'file_name': fileName,
        'file_size': fileSize,
      };
      if (receiverId != null) body['receiver_id'] = receiverId;

      final response = await http
          .post(Uri.parse(AppConfig.p2pCreateSessionUrl), headers: _getHeaders(), body: jsonEncode(body))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to create session: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> p2pJoinSession(String sessionId) async {
    try {
      final response = await http
          .post(Uri.parse(AppConfig.p2pJoinSessionUrl), headers: _getHeaders(), body: jsonEncode({'session_id': sessionId}))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      final body = jsonDecode(response.body);
      return {'success': false, 'error': body['error'] ?? 'Failed to join'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> p2pGetSession(String sessionId) async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.p2pSessionDetailUrl}$sessionId/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Session not found'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }
}

