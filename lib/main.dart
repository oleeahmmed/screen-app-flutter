// main.dart - Main App with Fixed Window Size

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'config.dart';
import 'services/api_service.dart';
import 'services/screenshot_service.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/tasks_page.dart';
import 'pages/chat_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iGenHR',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen();

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late ApiService _apiService;
  late ScreenshotService _screenshotService;
  bool _isLoggedIn = false;
  String _username = '';
  int _currentIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _screenshotService = ScreenshotService(_apiService);
    _initializeApp();
    _setWindowSize();
  }
  
  Future<void> _initializeApp() async {
    // Initialize API service with saved token
    await _apiService.initToken();
    // Check login status
    await _checkLoginStatus();
  }

  void _setWindowSize() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        print('🖥️ Desktop app - Window size: 620x720');
      });
    }
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final username = prefs.getString('username');

    print('🔍 Checking login status...');
    print('  Token exists: ${token != null && token.isNotEmpty}');
    print('  Username: $username');

    if (token != null && username != null && token.isNotEmpty) {
      _apiService.setToken(token);
      setState(() {
        _isLoggedIn = true;
        _username = username;
        _isLoading = false;
      });
      print('✅ User already logged in: $username');
      // Screenshot will start when user clicks Clock In;
    } else {
      print('❌ No saved login found');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLoginSuccess(String username, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('username', username);

    setState(() {
      _isLoggedIn = true;
      _username = username;
      _currentIndex = 0;
    });
    
    // Screenshot will start when user clicks "Clock In" button
    print('✅ Login successful');
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Clear all saved user data
    await prefs.clear();
    
    print('🚪 User logged out - all data cleared');

    setState(() {
      _isLoggedIn = false;
      _username = '';
      _currentIndex = 0;
    });
    _screenshotService.stopCapture();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ),
      );
    }

    if (!_isLoggedIn) {
      return LoginPage(
        apiService: _apiService,
        onLoginSuccess: _handleLoginSuccess,
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardPage(
            apiService: _apiService,
            username: _username,
            screenshotService: _screenshotService,
          ),
          TasksPage(apiService: _apiService),
          ChatPage(apiService: _apiService),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(int.parse('0xFF0f172a')).withOpacity(0.98),
              Color(int.parse('0xFF0a1223')),
            ],
          ),
          border: Border(
            top: BorderSide(
              color: Colors.white.withOpacity(0.05),
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: 6, top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(0, Icons.work, 'Work', Color(int.parse('0xFF10B981'))),
              _buildNavItem(1, Icons.checklist, 'Tasks', Color(int.parse('0xFFF59E0B'))),
              _buildNavItem(2, Icons.chat, 'Chat', Color(int.parse('0xFF3B82F6'))),
              _buildNavItem(3, Icons.screenshot_monitor, 'Test', Color(int.parse('0xFF8B5CF6'))),
              GestureDetector(
                onTap: _handleLogout,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Tooltip(
                    message: 'Logout',
                    child: Icon(Icons.logout, color: Colors.white54, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, Color color) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: color.withOpacity(0.5), width: 1)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? color : Colors.white54,
              size: 20,
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : Colors.white54,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _screenshotService.stopCapture();
    super.dispose();
  }
}
