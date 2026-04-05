// login_page.dart - Login Page

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../app_session.dart';
import '../services/api_service.dart';

class LoginPage extends StatefulWidget {
  final ApiService apiService;
  final Function(String, String) onLoginSuccess;

  const LoginPage({
    required this.apiService,
    required this.onLoginSuccess,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await widget.apiService.login(
      _usernameController.text,
      _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      final data = result['data'];
      
      // Check if access is granted
      if (data['access_granted'] == false) {
        setState(() => _errorMessage = data['message'] ?? 'Access denied');
        return;
      }
      
      // Extract user data
      final username = data['user']?['username'] ?? 'User';
      final token = data['access'] ?? '';
      
      print('✅ Login successful:');
      print('  User: $username');
      print('  Access Granted: ${data['access_granted']}');
      
      // Save all login data using UserDataService
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await prefs.setString('refresh_token', data['refresh'] ?? '');
      await prefs.setString('username', username);
      await prefs.setString('user_id', data['user']?['id']?.toString() ?? '');
      await prefs.setString('email', data['user']?['email'] ?? '');
      await prefs.setString('full_name', data['user']?['full_name'] ?? username);
      await prefs.setString('designation', data['employee']?['designation'] ?? '');
      await prefs.setBool('is_admin', data['employee']?['is_admin'] ?? false);
      await prefs.setString('company_id', data['company']?['id']?.toString() ?? '');
      await prefs.setString('company_name', data['company']?['name'] ?? '');
      await prefs.setString('subscription_plan', data['subscription']?['plan'] ?? '');
      await prefs.setString('subscription_status', data['subscription']?['status'] ?? '');
      await prefs.setBool('access_granted', data['access_granted'] ?? false);
      final emp = data['employee'];
      final consent = emp?['screenshot_monitoring_consent'] == true;
      await prefs.setBool('screenshot_monitoring_consent', consent);
      AppSession.setConsent(consent);
      int intVal(dynamic v, int d) {
        if (v is int) return v;
        if (v is String) return int.tryParse(v) ?? d;
        return d;
      }
      final sv = intVal(data['data_privacy_notice_version'], AppConfig.dataPrivacyNoticeVersion);
      await prefs.setInt('data_privacy_notice_server_version', sv);
      if (emp is Map) {
        await prefs.setInt(
          'data_privacy_notice_accepted_version',
          intVal(emp['data_privacy_notice_accepted_version'], 0),
        );
      } else {
        await prefs.setInt('data_privacy_notice_accepted_version', sv);
      }
      final p = data['profile_photo']?.toString();
      if (p != null && p.isNotEmpty) {
        await prefs.setString('profile_photo_url', p);
      }
      
      print('💾 User data saved to SharedPreferences');
      
      widget.onLoginSuccess(username, token);
    } else {
      setState(() => _errorMessage = result['error'] ?? 'Login failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'iGenHR',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Employee Monitoring System',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(height: 50),
                if (_errorMessage != null) ...[
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color(int.parse('0xFFE74C3C')).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Color(int.parse('0xFFE74C3C')),
                      ),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Color(int.parse('0xFFE74C3C')),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                ],
                TextField(
                  controller: _usernameController,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    hintText: 'Username',
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Color(int.parse('0xFF2196F3')),
                      ),
                    ),
                    hintStyle: TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.person, color: Colors.white54),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  enabled: !_isLoading,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Color(int.parse('0xFF2196F3')),
                      ),
                    ),
                    hintStyle: TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.lock, color: Colors.white54),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
                SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(int.parse('0xFF2196F3')),
                      disabledBackgroundColor:
                          Color(int.parse('0xFF2196F3')).withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            'Login',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
