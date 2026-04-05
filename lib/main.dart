import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'app_session.dart';
import 'config.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/screenshot_service.dart';
import 'services/notification_sound.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/work_hub_page.dart';
import 'pages/chat_page.dart';
import 'pages/notifications_page.dart';
import 'pages/profile_page.dart';
import 'pages/peer2peer_page.dart';
import 'widgets/privacy_notice_dialog.dart';

int _intFromDynamic(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppSession.screenshotIntervalSeconds = AppConfig.screenshotInterval;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iGenHR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final ApiService _apiService = ApiService();
  late final ScreenshotService _screenshotService = ScreenshotService(_apiService);
  bool _isLoggedIn = false;
  String _username = '';
  int _currentIndex = 0;
  bool _isLoading = true;
  int _unreadNotifs = 0;
  int? _prevUnreadForSound;
  int _homeRefreshToken = 0;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('Desktop build — API: ${AppConfig.apiBaseUrl}');
      });
    }
  }

  Future<void> _initializeApp() async {
    await _apiService.initToken();
    final prefs = await SharedPreferences.getInstance();
    AppSession.setConsent(prefs.getBool('screenshot_monitoring_consent') ?? false);
    await _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final username = prefs.getString('username');
    final accessGranted = prefs.getBool('access_granted') ?? false;

    if (token != null && username != null && token.isNotEmpty) {
      _apiService.setToken(token);
      try {
        final result = await _apiService.accessCheck();
        if (result['success']) {
          final data = result['data'];
          if (data['access_granted'] == true) {
            if (data['user'] != null) {
              await prefs.setString('user_id', data['user']['id']?.toString() ?? '');
              await prefs.setString('email', data['user']['email'] ?? '');
              await prefs.setString('full_name', data['user']['full_name'] ?? username);
            }
            if (data['employee'] != null) {
              final emp = data['employee'];
              await prefs.setString('designation', emp['designation'] ?? '');
              await prefs.setBool('is_admin', emp['is_admin'] ?? false);
              final c = emp['screenshot_monitoring_consent'] == true;
              await prefs.setBool('screenshot_monitoring_consent', c);
              AppSession.setConsent(c);
              await prefs.setInt(
                'data_privacy_notice_accepted_version',
                _intFromDynamic(emp['data_privacy_notice_accepted_version'], 0),
              );
            }
            await prefs.setInt(
              'data_privacy_notice_server_version',
              _intFromDynamic(data['data_privacy_notice_version'], AppConfig.dataPrivacyNoticeVersion),
            );
            if (data['profile_photo'] != null) {
              await prefs.setString('profile_photo_url', data['profile_photo'].toString());
            }
            if (data['company'] != null) {
              await prefs.setString('company_id', data['company']['id']?.toString() ?? '');
              await prefs.setString('company_name', data['company']['name'] ?? '');
            }
            if (data['subscription'] != null) {
              await prefs.setString('subscription_plan', data['subscription']['plan'] ?? '');
              await prefs.setString('subscription_status', data['subscription']['status'] ?? '');
            }
            await prefs.setBool('access_granted', true);
            if (!mounted) return;
            setState(() {
              _isLoggedIn = true;
              _username = username;
              _isLoading = false;
            });
            _pollNotifCount();
            if (data['employee'] != null) {
              _schedulePrivacyNoticeDialog();
            } else {
              final sv = _intFromDynamic(
                data['data_privacy_notice_version'],
                AppConfig.dataPrivacyNoticeVersion,
              );
              await prefs.setInt('data_privacy_notice_server_version', sv);
              await prefs.setInt('data_privacy_notice_accepted_version', sv);
            }
            return;
          }
          await prefs.clear();
          if (!mounted) return;
          setState(() => _isLoading = false);
          return;
        }
        await prefs.clear();
        if (!mounted) return;
        setState(() => _isLoading = false);
      } catch (e) {
        if (accessGranted) {
          AppSession.setConsent(prefs.getBool('screenshot_monitoring_consent') ?? false);
          if (!mounted) return;
          setState(() {
            _isLoggedIn = true;
            _username = username;
            _isLoading = false;
          });
          _pollNotifCount();
          return;
        }
        await prefs.clear();
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    } else {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLoginSuccess(String username, String token) async {
    await SharedPreferences.getInstance().then((p) async {
      await p.setString('auth_token', token);
      await p.setString('username', username);
    });
    if (!mounted) return;
    setState(() {
      _isLoggedIn = true;
      _username = username;
      _currentIndex = 0;
    });
    _pollNotifCount();
    _schedulePrivacyNoticeDialog();
  }

  /// Show first-run style dialog when server notice version is newer than accepted.
  void _schedulePrivacyNoticeDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_isLoggedIn) return;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final av = prefs.getInt('data_privacy_notice_accepted_version') ?? 0;
      final sv = prefs.getInt('data_privacy_notice_server_version') ?? AppConfig.dataPrivacyNoticeVersion;
      if (av >= sv) return;
      if (!mounted) return;
      await showPrivacyNoticeDialog(context: context, apiService: _apiService);
    });
  }

  Future<void> _pollNotifCount() async {
    if (!_isLoggedIn || !mounted) return;
    final r = await _apiService.getNotificationUnreadCount();
    if (!r['success'] || !mounted) {
      Future.delayed(const Duration(seconds: 30), _pollNotifCount);
      return;
    }
    final n = r['data']?['unread_count'] as int? ?? 0;
    final prefs = await SharedPreferences.getInstance();
    final soundOn = prefs.getBool('notification_sound_enabled') ?? true;
    if (_prevUnreadForSound != null && n > _prevUnreadForSound! && soundOn) {
      NotificationSound.playPing();
    }
    _prevUnreadForSound = n;
    setState(() => _unreadNotifs = n);
    Future.delayed(const Duration(seconds: 30), _pollNotifCount);
  }

  Future<void> _handleLogout() async {
    await SharedPreferences.getInstance().then((p) => p.clear());
    AppSession.setConsent(false);
    _screenshotService.stopCapture();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _username = '';
      _currentIndex = 0;
      _prevUnreadForSound = null;
    });
  }

  void _openP2P() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Peer transfer'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: Peer2PeerPage(apiService: _apiService),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: AppTheme.screenGradient(),
          child: const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryBright),
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
            refreshToken: _homeRefreshToken,
          ),
          WorkHubPage(apiService: _apiService),
          ChatPage(apiService: _apiService),
          NotificationsPage(apiService: _apiService),
          ProfilePage(
            apiService: _apiService,
            onOpenP2P: _openP2P,
            onLogout: _handleLogout,
          ),
        ],
      ),
      bottomNavigationBar: AppTheme.glassBlur(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              indicatorColor: AppTheme.primary.withValues(alpha: 0.22),
              onDestinationSelected: (i) {
                setState(() {
                  _currentIndex = i;
                  if (i == 0) _homeRefreshToken++;
                });
                if (i == 3) _pollNotifCount();
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.work_outline_rounded),
                  selectedIcon: Icon(Icons.work_rounded),
                  label: 'Work',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  selectedIcon: Icon(Icons.chat_rounded),
                  label: 'Chat',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: _unreadNotifs > 0,
                    label: Text(_unreadNotifs > 9 ? '9+' : '$_unreadNotifs'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: _unreadNotifs > 0,
                    label: Text(_unreadNotifs > 9 ? '9+' : '$_unreadNotifs'),
                    child: const Icon(Icons.notifications_rounded),
                  ),
                  label: 'Alerts',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Me',
                ),
              ],
            ),
          ),
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
