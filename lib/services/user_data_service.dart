// user_data_service.dart - User Data Management Service

import 'package:shared_preferences/shared_preferences.dart';

class UserDataService {
  // Get all user data
  static Future<Map<String, dynamic>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'auth_token': prefs.getString('auth_token') ?? '',
      'refresh_token': prefs.getString('refresh_token') ?? '',
      'username': prefs.getString('username') ?? '',
      'user_id': prefs.getString('user_id') ?? '',
      'email': prefs.getString('email') ?? '',
      'full_name': prefs.getString('full_name') ?? '',
      'designation': prefs.getString('designation') ?? '',
      'company_id': prefs.getString('company_id') ?? '',
      'company_name': prefs.getString('company_name') ?? '',
      'subscription_plan': prefs.getString('subscription_plan') ?? '',
      'subscription_status': prefs.getString('subscription_status') ?? '',
      'profile_photo_url': prefs.getString('profile_photo_url') ?? '',
      'screenshot_monitoring_consent':
          prefs.getBool('screenshot_monitoring_consent') ?? false,
      'notification_sound_enabled':
          prefs.getBool('notification_sound_enabled') ?? true,
    };
  }
  
  // Get auth token
  static Future<String> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? '';
  }
  
  // Get refresh token
  static Future<String> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token') ?? '';
  }
  
  // Get username
  static Future<String> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username') ?? '';
  }
  
  // Get full name
  static Future<String> getFullName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('full_name') ?? '';
  }
  
  // Get company name
  static Future<String> getCompanyName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('company_name') ?? '';
  }
  
  // Get designation
  static Future<String> getDesignation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('designation') ?? '';
  }
  
  // Get email
  static Future<String> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('email') ?? '';
  }
  
  // Get user ID
  static Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? '';
  }
  
  // Get company ID
  static Future<String> getCompanyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('company_id') ?? '';
  }
  
  // Get subscription plan
  static Future<String> getSubscriptionPlan() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('subscription_plan') ?? '';
  }
  
  // Get subscription status
  static Future<String> getSubscriptionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('subscription_status') ?? '';
  }
  
  // Check if user is admin
  static Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_admin') ?? false;
  }
  
  // Check if access is granted
  static Future<bool> isAccessGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('access_granted') ?? false;
  }
  
  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final accessGranted = prefs.getBool('access_granted') ?? false;
    return token != null && token.isNotEmpty && accessGranted;
  }
  
  // Clear all data (logout)
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    print('🗑️ All user data cleared');
  }
  
  // Print user data for debugging
  static Future<void> printUserData() async {
    final data = await getUserData();
    print('👤 Current User Data:');
    data.forEach((key, value) {
      if (key == 'auth_token' || key == 'refresh_token') return;
      if (value is String && value.isEmpty) return;
      print('  $key: $value');
    });
    
    final isAdmin = await UserDataService.isAdmin();
    final accessGranted = await UserDataService.isAccessGranted();
    print('  is_admin: $isAdmin');
    print('  access_granted: $accessGranted');
  }
}

