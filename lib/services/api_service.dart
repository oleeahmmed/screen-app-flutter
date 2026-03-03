// api_service.dart - API Service

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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
    try {
      print('❌ Checking out...');
      
      // Do checkout directly
      var response = await http
          .post(
            Uri.parse(AppConfig.checkOutUrl),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Check-out response: ${response.statusCode}');
      print('📝 Response body: ${response.body}');

      // If 401, token might be expired - try to refresh
      if (response.statusCode == 401) {
        print('⚠️ Token expired, attempting refresh...');
        // For now, just return error - user needs to login again
        return {'success': false, 'error': 'Session expired - please login again'};
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
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
      return {'success': false, 'error': 'Check-out failed: ${response.statusCode}'};
    } catch (e) {
      print('❌ Check-out error: $e');
      return {'success': false, 'error': 'Check-out error: $e'};
    }
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

  Future<Map<String, dynamic>> uploadScreenshot(List<int> imageBytes) async {
    try {
      print('📤 Uploading screenshot...');
      
      // Create relative path with timestamp
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final time = '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final relativePath = '$date/screen1/$time.png';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.screenshotUploadUrl),
      );

      request.headers.addAll(_getHeaders());
      
      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: '$time.png',
        ),
      );
      
      // Add relative_path
      request.fields['relative_path'] = relativePath;

      print('📝 Relative path: $relativePath');
      
      var response = await request.send().timeout(Duration(seconds: 30));
      
      print('📊 Upload response: ${response.statusCode}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseBody = await response.stream.bytesToString();
        print('✅ Screenshot uploaded: $responseBody');
        return {'success': true, 'data': responseBody};
      } else {
        final responseBody = await response.stream.bytesToString();
        print('❌ Upload failed: ${response.statusCode} - $responseBody');
        return {'success': false, 'error': 'Upload failed: ${response.statusCode}'};
      }
    } catch (e) {
      print('❌ Upload error: $e');
      return {'success': false, 'error': 'Upload error: $e'};
    }
  }

  Future<Map<String, dynamic>> updateActivityStatus(bool isActive) async {
    try {
      print('📊 Updating activity status: ${isActive ? 'ACTIVE' : 'IDLE'}');
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/attendance/activity/'),
            headers: _getHeaders(),
            body: jsonEncode({'is_active': isActive}),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Activity update response: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Activity update failed: ${response.statusCode}'};
    } catch (e) {
      print('❌ Activity update error: $e');
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

