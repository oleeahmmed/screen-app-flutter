// api_service.dart - API Service

import 'dart:async';
import 'package:http/http.dart' as http;
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
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to toggle task'};
    } catch (e) {
      return {'success': false, 'error': 'Toggle error: $e'};
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
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'description': description,
        'priority': priority,
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
      return {'success': false, 'error': 'Failed to update task'};
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
      return {'success': false, 'error': 'Failed to delete task'};
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
    String? dueDate,
  }) async {
    try {
      final body = <String, dynamic>{
        'summary': summary,
        'description': description,
        'priority': priority,
      };
      if (dueDate != null) body['due_date'] = dueDate;

      final response = await http
          .post(Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/'), headers: _getHeaders(), body: jsonEncode(body))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to create subtask'};
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
      return {'success': false, 'error': 'Failed to update subtask'};
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
          .post(Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/toggle/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to toggle subtask'};
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
  Future<Map<String, dynamic>> getProjects() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.projectsUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load projects'};
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
          .post(Uri.parse('${AppConfig.tasksUrl}$taskId/move/'), headers: _getHeaders(), body: jsonEncode({'stage_id': stageId}))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to move task'};
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
      
      var response = await request.send().timeout(Duration(seconds: 30));
      final responseBody = await response.stream.bytesToString();
      
      print('📊 Upload response: ${response.statusCode}');
      print('📝 Response body: $responseBody');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': responseBody};
      } else {
        return {'success': false, 'error': 'Upload failed: ${response.statusCode} - $responseBody'};
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

      request.headers.addAll(_getHeaders());
      
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
}

