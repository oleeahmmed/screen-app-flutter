import 'package:aims_style_notify/aims_style_notify.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';

import 'app_session.dart';
import 'config.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/user_data_service.dart';
import 'services/screenshot_service.dart';
import 'services/notification_service.dart';
import 'services/call_service.dart';
import 'services/call_navigation.dart';
import 'services/call_notification.dart';
import 'services/chat_notification.dart';
import 'services/call_tokens.dart';
import 'services/push_service.dart';
import 'services/local_notification_service.dart';
import 'services/push_keepalive_service.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/tasks_page.dart';
import 'pages/work_hub_page.dart';
import 'pages/chat_page.dart';
import 'pages/call_page.dart';
import 'pages/notifications_page.dart';
import 'pages/profile_page.dart';
import 'pages/peer2peer_page.dart';
import 'pages/daily_report_tool_page.dart';
import 'pages/activity_tool_page.dart';
import 'pages/attendance_report_page.dart';
import 'pages/vault_hub_page.dart';
import 'widgets/privacy_notice_dialog.dart';
import 'widgets/closing_report_panel.dart';
import 'widgets/tool_page_scaffold.dart';
import 'widgets/notification_banner.dart';
import 'widgets/app_tab_shell.dart';
import 'services/app_navigation.dart';
import 'utils/platform_capabilities.dart';

/// Root navigator — used to close pushed routes on logout.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

int _intFromDynamic(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('AIMS API: ${AppConfig.apiBaseUrl}');
  if (!kIsWeb) {
    // Fail slow/broken routes faster (common on Android IPv6) so login can retry.
    HttpOverrides.global = _AimsHttpOverrides();
  }
  AppSession.screenshotIntervalSeconds = AppConfig.screenshotInterval;
  await LocalNotificationService.initialize();
  await PushService.instance.initialize();
  await PushKeepAlive.configure();
  runApp(const MyApp());
}

/// Shared HTTP tuning for mobile / desktop (not web).
class _AimsHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 20);
    client.idleTimeout = const Duration(seconds: 45);
    return client;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aims',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.dark(),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late final ApiService _apiService = ApiService();
  late final ScreenshotService _screenshotService = ScreenshotService(_apiService);
  late final NotificationService _notificationService = NotificationService(_apiService);
  bool _isLoggedIn = false;
  String _username = '';
  int _currentIndex = 0;
  bool _isLoading = true;
  int _unreadNotifs = 0;
  int _notifListRefreshToken = 0;
  int _homeRefreshToken = 0;
  StreamSubscription<Map<String, dynamic>>? _notifPushSub;
  StreamSubscription<Map<String, dynamic>>? _nativeCallSub;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  Widget? _dashboardPage;
  Widget? _tasksPage;
  Widget? _chatPage;
  Widget? _vaultPage;
  Widget? _projectPage;

  void _clearPageCache() {
    _dashboardPage = null;
    _tasksPage = null;
    _chatPage = null;
    _vaultPage = null;
    _projectPage = null;
  }

  void _ensurePageBuilt(int index) {
    switch (index) {
      case 0:
        _dashboardPage ??= DashboardPage(
          apiService: _apiService,
          username: _username,
          screenshotService: _screenshotService,
          refreshToken: _homeRefreshToken,
          onLogout: _handleLogout,
        );
      case 1:
        _tasksPage ??= SafeArea(
          top: false,
          bottom: false,
          child: TasksPage(apiService: _apiService),
        );
      case 2:
        _chatPage ??= ChatPage(
          apiService: _apiService,
          notificationService: _notificationService,
        );
      case 3:
        _vaultPage ??= SafeArea(
          top: false,
          bottom: false,
          child: VaultHubPage(
            apiService: _apiService,
            onLogout: _handleLogout,
            embeddedInTabs: true,
          ),
        );
      case 4:
        _projectPage ??= WorkHubPage(
          apiService: _apiService,
          screenshotService: _screenshotService,
          onLogout: _handleLogout,
        );
    }
  }

  List<Widget> _mainStackChildren() {
    _ensurePageBuilt(_currentIndex);
    return [
      _dashboardPage ?? const SizedBox.shrink(),
      _tasksPage ?? const SizedBox.shrink(),
      _chatPage ?? const SizedBox.shrink(),
      _vaultPage ?? const SizedBox.shrink(),
      _projectPage ?? const SizedBox.shrink(),
    ];
  }

  @override
  void initState() {
    super.initState();
    CallNavigation.navigatorKey = appNavigatorKey;
    WidgetsBinding.instance.addObserver(this);
    LocalNotificationService.onAction = (actionId, payload, input) {
      unawaited(_onNotificationAction(actionId, payload, input: input));
    };
    LocalNotificationService.onTap = (payload) {
      if (CallNotification.isCallPayload(payload)) return;
      if (!_isLoggedIn || !mounted) return;
      if (ChatNotification.isChatPayload(payload) || payload == 'chat') {
        _openChatFromPayload(payload);
        return;
      }
      unawaited(_openNotifications());
    };
    AppNavigation.instance.onSelectTab = _onNavSelected;
    AppNavigation.instance.onNavigateToTab = _navigateToTab;
    AppNavigation.instance.onLogout = _handleLogout;
    AppNavigation.instance.onOpenDailyReport = _openDailyReportTool;
    AppNavigation.instance.onOpenActivity = _openActivityTool;
    AppNavigation.instance.onOpenAttendanceReport = _openAttendanceReportTool;
    AppNavigation.instance.onOpenVault = _openVaultTool;
    AppNavigation.instance.onOpenProject = _openProjectTool;
    AppNavigation.instance.onOpenP2P = _openP2P;
    AppNavigation.instance.onOpenSubmitReport = _openSubmitReport;
    AppNavigation.instance.onOpenNotifications = _openNotifications;
    AppNavigation.instance.onOpenProfile = _openProfile;
    AppNavigationBridge.openChatTab = () => _navigateToTab(2);
    AppNavigationBridge.openChatPeer = (userId, groupId) {
      AppNavigation.instance.goChatWithPeer(userId: userId, groupId: groupId);
    };
    AppNavigationBridge.openNotifications = _openNotifications;
    AppNavigationBridge.openIncomingCall = (data) {
      unawaited(CallService.instance.handleRemoteSignal(data));
      _openCallPage();
    };
    _notificationService.onUnreadCountChanged = _onUnreadCountChanged;
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
    final refresh = prefs.getString('refresh_token');
    final username = prefs.getString('username');
    final accessGranted = prefs.getBool('access_granted') ?? false;

    final hasSession = (token != null && token.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty);

    if (!hasSession || username == null || username.isEmpty) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    if (token != null && token.isNotEmpty) {
      _apiService.setToken(token);
    }

    // WhatsApp-style: refresh token proactively so session stays alive for months.
    if (refresh != null && refresh.isNotEmpty) {
      await _apiService.refreshAccessToken();
    }

    try {
      final result = await _apiService.accessCheck();
      if (result['success'] == true) {
        final data = result['data'];
        if (data['access_granted'] == true) {
          await _applyAccessCheckPayload(data, prefs, username);
          if (!mounted) return;
          setState(() {
            _isLoggedIn = true;
            _username = username;
            _isLoading = false;
          });
          _ensurePageBuilt(0);
          _startNotifications();
          if (data['employee'] != null) {
            _schedulePrivacyNoticeDialog();
            _scheduleClosingReportDialog();
          }
          return;
        }
        // Server explicitly denied access — clear auth only.
        await UserDataService.clearAuthSession();
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }
    } catch (_) {
      // Network/server unreachable — stay logged in if we had a valid session.
    }

    if (accessGranted) {
      AppSession.setConsent(prefs.getBool('screenshot_monitoring_consent') ?? false);
      if (!mounted) return;
      setState(() {
        _isLoggedIn = true;
        _username = username;
        _isLoading = false;
      });
      _ensurePageBuilt(0);
      _startNotifications();
      return;
    }

    await UserDataService.clearAuthSession();
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _applyAccessCheckPayload(
    Map<String, dynamic> data,
    SharedPreferences prefs,
    String username,
  ) async {
    if (data['user'] != null) {
      await prefs.setString('user_id', data['user']['id']?.toString() ?? '');
      await prefs.setString('email', data['user']['email'] ?? '');
      await prefs.setString('full_name', data['user']['full_name'] ?? username);
    }
    if (data['employee'] != null) {
      final emp = data['employee'];
      await UserDataService.saveEmployeeId(emp);
      await prefs.setString('designation', emp['designation'] ?? '');
      await UserDataService.saveEmployeeRoleFlags(
        emp is Map ? Map<String, dynamic>.from(emp) : null,
      );
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
    if (data['employee'] == null) {
      final sv = _intFromDynamic(
        data['data_privacy_notice_version'],
        AppConfig.dataPrivacyNoticeVersion,
      );
      await prefs.setInt('data_privacy_notice_server_version', sv);
      await prefs.setInt('data_privacy_notice_accepted_version', sv);
    }
  }

  Future<void> _handleLoginSuccess(String username, String token) async {
    _apiService.setToken(token);
    await SharedPreferences.getInstance().then((p) async {
      await p.setString('auth_token', token);
      await p.setString('username', username);
    });
    final access = await _apiService.accessCheck();
    if (access['success'] == true && access['data'] is Map) {
      final prefs = await SharedPreferences.getInstance();
      await _applyAccessCheckPayload(
        Map<String, dynamic>.from(access['data'] as Map),
        prefs,
        username,
      );
    }
    if (!mounted) return;
    setState(() {
      _isLoggedIn = true;
      _username = username;
      _currentIndex = 0;
    });
    _clearPageCache();
    _ensurePageBuilt(0);
    _startNotifications();
    _schedulePrivacyNoticeDialog();
    _scheduleClosingReportDialog();
  }

  /// Prompt for daily closing report when admin schedule time has passed.
  void _scheduleClosingReportDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_isLoggedIn) return;
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || !_isLoggedIn) return;
      final r = await _apiService.getClosingReportPending();
      if (!mounted) return;
      if (r['success'] == true && r['data']?['pending'] == true) {
        await showClosingReportDialog(
          context: context,
          apiService: _apiService,
          required: true,
        );
      }
    });
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

  void _onUnreadCountChanged(int count) {
    if (!mounted) return;
    setState(() => _unreadNotifs = count);
    AppNavigation.instance.unreadNotifs = count;
  }

  void _syncNavState() {
    AppNavigation.instance.selectedTabIndex = _currentIndex;
    AppNavigation.instance.unreadNotifs = _unreadNotifs;
  }

  void _navigateToTab(int i) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _onNavSelected(i);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    final foreground = state == AppLifecycleState.resumed;
    PushKeepAlive.setUiForeground(foreground);
    if (!_isLoggedIn) return;
    if (foreground) {
      _notificationService.setAppInBackground(false);
      unawaited(_notificationService.reconnect());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _notificationService.setAppInBackground(true);
    }
  }

  Future<void> _ensureMobileNotificationPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await LocalNotificationService.requestPermissions();
  }

  void _startNotifications() {
    unawaited(_startNotificationsAsync());
  }

  Future<void> _startNotificationsAsync() async {
    _notifPushSub?.cancel();
    await _bindCallService();
    await _notificationService.start();
    _notifPushSub = _notificationService.pushStream.listen(_onPushNotification);
    _nativeCallSub?.cancel();
    if (!kIsWeb && Platform.isAndroid) {
      _nativeCallSub = AimsStyleNotify.events().listen((event) {
        unawaited(_onNotificationAction(
          event['actionId']?.toString(),
          event['payload']?.toString(),
        ));
      });
    }
    unawaited(_ensureMobileNotificationPermission());
    unawaited(PushKeepAlive.start());
    unawaited(PushService.instance.bindApi(_apiService));
  }

  Future<void> _bindCallService() async {
    var uid = int.tryParse(await UserDataService.getUserId());
    if (uid == null) {
      final r = await _apiService.accessCheck();
      if (r['success'] == true) {
        final user = r['data']?['user'];
        if (user is Map) {
          uid = int.tryParse('${user['id'] ?? ''}');
          if (uid != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_id', uid.toString());
          }
        }
      }
    }
    if (uid == null) return;
    await CallNotification.flushPendingDecline();
    CallService.instance.bind(
      notificationService: _notificationService,
      apiService: _apiService,
      myUserId: uid,
    );
    CallService.instance.onIncomingCall = (_) {
      if (!mounted) return;
      _openCallPage();
    };
    final pending = LocalNotificationService.takePending();
    if (pending != null) {
      unawaited(_onNotificationAction(pending.actionId, pending.payload, input: pending.input));
    }
  }

  Future<void> _onNotificationAction(String? actionId, String? payload, {String? input}) async {
    final invite = CallNotification.parse(payload);
    if (invite != null) {
      if (!_isLoggedIn) {
        LocalNotificationService.pendingActionId = actionId;
        LocalNotificationService.pendingPayload = payload;
        LocalNotificationService.pendingInput = input;
        return;
      }
      await CallService.instance.applyNotificationAction(actionId, invite);
      return;
    }
    if (!_isLoggedIn || !mounted) return;

    if (actionId == ChatNotification.replyAction) {
      await ChatNotification.replyViaHttp(payload, input);
      return;
    }
    if (actionId == ChatNotification.markReadAction) {
      await ChatNotification.markReadViaHttp(payload);
      final chat = ChatNotification.parse(payload);
      final peerId = int.tryParse('${chat?['peer_id'] ?? ''}');
      if (peerId != null) {
        LocalNotificationService.clearChatThread('u:$peerId');
      }
      return;
    }

    if (ChatNotification.isChatPayload(payload) || payload == 'chat') {
      _openChatFromPayload(payload);
      return;
    }
    unawaited(_openNotifications());
  }

  void _openChatFromPayload(String? payload) {
    final chat = ChatNotification.parse(payload);
    final peerId = int.tryParse('${chat?['peer_id'] ?? ''}');
    final groupId = int.tryParse('${chat?['group_id'] ?? ''}');
    AppNavigation.instance.goChatWithPeer(userId: peerId, groupId: groupId);
  }

  void _openCallPage() {
    if (!mounted || !_isLoggedIn) return;
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final top = ModalRoute.of(nav.context)?.settings.name;
    if (top == '/call') return;
    nav.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/call'),
        builder: (_) => const CallPage(),
        fullscreenDialog: true,
      ),
    );
  }

  void _stopNotifications() {
    unawaited(PushKeepAlive.stop());
    _notifPushSub?.cancel();
    _notifPushSub = null;
    _nativeCallSub?.cancel();
    _nativeCallSub = null;
    if (CallService.instance.isInCall) CallService.instance.hangUp();
    CallService.instance.unbind();
    unawaited(PushService.instance.unregister());
    _notificationService.stop();
    NotificationBanner.hide();
  }

  Future<void> _onPushNotification(Map<String, dynamic> data) async {
    if (!mounted) return;

    final notifType = data['notification_type']?.toString() ?? '';
    final title = data['title']?.toString() ?? 'Notification';
    final message = data['message']?.toString() ?? '';
    final inForeground = _lifecycle == AppLifecycleState.resumed;
    final rawId = data['id'];
    final notifId = rawId is int ? rawId : int.tryParse('$rawId') ?? title.hashCode;
    final isChat = notifType == 'new_message' || notifType == 'new_group_message';

    if (notifType == 'call_invite') {
      final call = CallTokens.chatMessageToCallSignal({
        'message': message,
        'sender_id': data['sender_id'],
        'sender_name': title.replaceFirst('Incoming call from ', ''),
      });
      if (call != null) {
        unawaited(CallService.instance.handleRemoteSignal(call));
        if (mounted) _openCallPage();
      }
      return;
    }

    if (inForeground) {
      final chatMeta = isChat ? ChatNotification.fromData(data) : null;
      NotificationBanner.show(
        context,
        title: chatMeta?.name ?? title,
        message: chatMeta?.body.isNotEmpty == true ? chatMeta!.body : message,
        notificationType: notifType,
        onTap: () {
          if (isChat) {
            _openChatFromPayload(ChatNotification.encode(
              name: chatMeta?.name ?? title,
              peerId: chatMeta?.peerId,
              groupId: chatMeta?.groupId,
              notificationType: notifType,
            ));
          } else {
            unawaited(_openNotifications());
          }
        },
      );
    }

    // Chat: always show WhatsApp-style system tray heads-up on Android/iOS.
    if (LocalNotificationService.supported && (!inForeground || isChat)) {
      if (isChat) {
        final chat = ChatNotification.fromData(data);
        await LocalNotificationService.showChat(
          conversationKey: chat.isGroup
              ? 'g:${chat.groupId ?? notifId}'
              : 'u:${chat.peerId ?? notifId}',
          personName: chat.name,
          body: chat.body.isNotEmpty ? chat.body : (message.isNotEmpty ? message : 'New message'),
          payload: ChatNotification.encode(
            name: chat.name,
            peerId: chat.peerId,
            groupId: chat.groupId,
            notificationType: notifType,
          ),
          isGroup: chat.isGroup,
          groupTitle: chat.isGroup ? chat.name : null,
          personKey: chat.peerId ?? chat.groupId,
        );
      } else {
        await LocalNotificationService.show(
          id: notifId,
          title: title,
          body: message.isNotEmpty ? message : 'Tap to open AIMS',
          payload: 'alerts',
        );
      }
    }

    setState(() => _notifListRefreshToken++);

    if (notifType == 'closing_report_due') {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await showClosingReportDialog(
        context: context,
        apiService: _apiService,
        required: true,
      );
    } else if (notifType == 'closing_report_dependency') {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: AppTheme.modalBarrierColor,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface2,
          surfaceTintColor: Colors.transparent,
          title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
          content: Text(message, style: const TextStyle(color: AppTheme.textMuted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  /// Legacy alias — keeps badge in sync when opening Alerts tab.
  Future<void> _refreshNotificationBadge() async {
    await _notificationService.refreshUnreadCount();
  }

  Future<void> _handleLogout() async {
    _stopNotifications();
    _screenshotService.stopCapture();

    // Close tool/detail routes and dialogs so LoginPage is visible.
    appNavigatorKey.currentState?.popUntil((route) => route.isFirst);

    _apiService.setToken('');
    AppSession.setConsent(false);
    await UserDataService.clearAllData();
    _clearPageCache();

    AppNavigation.instance.selectedTabIndex = 0;
    AppNavigation.instance.unreadNotifs = 0;

    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _username = '';
      _currentIndex = 0;
      _unreadNotifs = 0;
      _isLoading = false;
    });
  }

  Future<void> _openSubmitReport() async {
    if (!mounted || !_isLoggedIn) return;
    final reportsR = await _apiService.getClosingReports();
    Map<String, dynamic>? todayReport;
    if (reportsR['success'] == true) {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      for (final item in reportsR['data'] as List? ?? []) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final d = m['report_date']?.toString();
        if (d != null && d.startsWith(todayStr)) {
          todayReport = m;
          break;
        }
      }
    }
    if (!mounted) return;
    await showClosingReportDialog(
      context: context,
      apiService: _apiService,
      existingReport: todayReport,
    );
  }

  Future<void> _openP2P() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex,
          unreadNotifs: _unreadNotifs,
          onLogout: _handleLogout,
          homeStyleBackground: true,
          child: ToolPageScaffold(
            scrollable: false,
            useBackground: false,
            showHeader: false,
            onLogout: _handleLogout,
            child: Peer2PeerPage(apiService: _apiService, embedded: true),
          ),
        ),
      ),
    );
  }

  Future<void> _openDailyReportTool() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex,
          unreadNotifs: _unreadNotifs,
          onLogout: _handleLogout,
          child: DailyReportToolPage(
            apiService: _apiService,
            onLogout: _handleLogout,
          ),
        ),
      ),
    );
  }

  Future<void> _openActivityTool() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex,
          unreadNotifs: _unreadNotifs,
          onLogout: _handleLogout,
          child: ActivityToolPage(
            apiService: _apiService,
            onLogout: _handleLogout,
          ),
        ),
      ),
    );
  }

  Future<void> _openAttendanceReportTool() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex,
          unreadNotifs: _unreadNotifs,
          onLogout: _handleLogout,
          child: AttendanceReportPage(
            apiService: _apiService,
            onLogout: _handleLogout,
          ),
        ),
      ),
    );
  }

  Future<void> _openProjectTool() async {
    if (!mounted) return;
    _onNavSelected(AppNavigation.tabProject);
  }

  Future<void> _openVaultTool() async {
    if (!mounted) return;
    _onNavSelected(AppNavigation.tabVault);
  }

  Future<void> _openProfile() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex.clamp(0, AppNavigation.tabCount - 1),
          unreadNotifs: _unreadNotifs,
          onLogout: _handleLogout,
          child: ProfilePage(
            apiService: _apiService,
            onLogout: _handleLogout,
          ),
        ),
      ),
    );
  }

  Future<void> _openNotifications() async {
    if (!mounted) return;
    setState(() => _notifListRefreshToken++);
    await _refreshNotificationBadge();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex,
          unreadNotifs: _unreadNotifs,
          onLogout: _handleLogout,
          child: NotificationsPage(
            apiService: _apiService,
            refreshToken: _notifListRefreshToken,
            onNotificationsChanged: () => _notificationService.syncUnreadCount(),
          ),
        ),
      ),
    );
    if (mounted) await _refreshNotificationBadge();
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

    _syncNavState();

    final immersiveChat = PlatformCapabilities.immersiveChatChrome &&
        _currentIndex == AppNavigation.tabChat;

    return AppTabShell(
      selectedIndex: _currentIndex,
      unreadNotifs: _unreadNotifs,
      onLogout: _handleLogout,
      showTopBar: !immersiveChat,
      showBottomNav: !immersiveChat,
      homeStyleBackground: immersiveChat,
      child: IndexedStack(
        index: _currentIndex,
        children: _mainStackChildren(),
      ),
    );
  }

  void _onNavSelected(int i) {
    final comingHome = i == 0 && _currentIndex != 0;
    setState(() {
      _currentIndex = i;
      if (comingHome) {
        _homeRefreshToken++;
      }
    });
    _syncNavState();
    _ensurePageBuilt(i);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocalNotificationService.onTap = null;
    AppNavigation.instance.onSelectTab = null;
    AppNavigation.instance.onNavigateToTab = null;
    AppNavigation.instance.onOpenDailyReport = null;
    AppNavigation.instance.onOpenActivity = null;
    AppNavigation.instance.onOpenVault = null;
    AppNavigation.instance.onOpenProject = null;
    AppNavigation.instance.onOpenP2P = null;
    AppNavigation.instance.onOpenSubmitReport = null;
    AppNavigation.instance.onOpenNotifications = null;
    AppNavigation.instance.onOpenProfile = null;
    AppNavigation.instance.onLogout = null;
    _stopNotifications();
    _notificationService.dispose();
    _screenshotService.stopCapture();
    super.dispose();
  }
}
