// login_page.dart — aims-webapps Login.jsx clone

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_session.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';

enum _LoginView { login, forgot }

class LoginPage extends StatefulWidget {
  final ApiService apiService;
  final Function(String, String) onLoginSuccess;

  const LoginPage({
    super.key,
    required this.apiService,
    required this.onLoginSuccess,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _forgotEmailController = TextEditingController();

  _LoginView _view = _LoginView.login;
  bool _isLoading = false;
  bool _showPassword = false;
  bool _rememberMe = false;
  String? _errorMessage;
  bool _forgotSent = false;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('remembered_username');
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() {
        _usernameController.text = saved;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _forgotEmailController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter username and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await widget.apiService.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      final data = result['data'];

      if (data['access_granted'] == false) {
        setState(() => _errorMessage = data['message'] ?? 'Access denied');
        return;
      }

      final username = data['user']?['username'] ?? 'User';
      final token = data['access'] ?? '';

      widget.apiService.setToken(token);

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_username', _usernameController.text.trim());
      } else {
        await prefs.remove('remembered_username');
      }
      await prefs.setString('auth_token', token);
      await prefs.setString('refresh_token', data['refresh'] ?? '');
      await prefs.setString('username', username);
      await prefs.setString('user_id', data['user']?['id']?.toString() ?? '');
      await UserDataService.saveEmployeeId(data['employee']);
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
        await prefs.setInt('data_privacy_notice_accepted_version', 0);
      }

      final p = data['profile_photo']?.toString();
      if (p != null && p.isNotEmpty) {
        await prefs.setString('profile_photo_url', p);
      }

      widget.onLoginSuccess(username, token);
    } else {
      setState(() => _errorMessage = result['error'] ?? 'Invalid username or password, or account is inactive.');
    }
  }

  Future<void> _sendForgotPassword() async {
    final email = _forgotEmailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your email address');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final r = await widget.apiService.forgotPassword(email);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (r['success'] == true) {
        _forgotSent = true;
        _errorMessage = null;
      } else {
        _errorMessage = r['error']?.toString() ?? 'Could not send reset link';
      }
    });
  }

  String get _subtitle {
    switch (_view) {
      case _LoginView.forgot:
        return 'Reset your password';
      case _LoginView.login:
        return 'Sign in to your workspace';
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxW = Responsive.isMobile(context) ? double.infinity : 448.0;
    final pad = Responsive.isMobile(context) ? 20.0 : 32.0;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(decoration: AppTheme.screenGradient()),
          _ambientOrbs(context),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: Container(
                    decoration: AppTheme.loginShell(),
                    padding: EdgeInsets.all(pad),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              const AppLogo(size: 56, showBorder: false),
                              const SizedBox(height: 16),
                              Text(
                                _subtitle,
                                style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (_view == _LoginView.login) _buildLoginForm() else _buildForgotForm(),
                        const SizedBox(height: 24),
                        const Text(
                          '© 2024 AIMS Monitor Pro. All rights reserved.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF52525B), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ambientOrbs(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: size.height * 0.22,
            left: size.width * 0.18,
            child: _blurOrb(const Color(0xFF6366F1), 280),
          ),
          Positioned(
            bottom: size.height * 0.2,
            right: size.width * 0.15,
            child: _blurOrb(const Color(0xFF0EA5E9), 260),
          ),
          Positioned(
            top: size.height * 0.45,
            left: size.width * 0.35,
            child: _blurOrb(const Color(0xFF38BDF8), 320),
          ),
        ],
      ),
    );
  }

  Widget _blurOrb(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.14),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Username'),
        TextField(
          controller: _usernameController,
          enabled: !_isLoading,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: _glassInput(hint: 'Enter your username'),
          onSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 16),
        _label('Password'),
        TextField(
          controller: _passwordController,
          enabled: !_isLoading,
          obscureText: !_showPassword,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: _glassInput(hint: '••••••••').copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: const Color(0xFF64748B),
                size: 18,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          onSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _rememberMe,
                onChanged: _isLoading ? null : (v) => setState(() => _rememberMe = v ?? false),
                activeColor: const Color(0xFF3B82F6),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isLoading ? null : () => setState(() => _rememberMe = !_rememberMe),
              child: const Text('Remember me', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            ),
            const Spacer(),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => setState(() {
                        _view = _LoginView.forgot;
                        _errorMessage = null;
                        _forgotSent = false;
                      }),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF60A5FA),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Forgot password?', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          _errorBox(_errorMessage!),
        ],
        const SizedBox(height: 18),
        _primaryBtn(
          label: _isLoading ? 'Signing in…' : 'Sign In',
          onPressed: _isLoading ? null : _login,
          loading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildForgotForm() {
    if (_forgotSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
            ),
            child: Text(
              'Password reset instructions sent to ${_forgotEmailController.text.trim()}. Check your inbox.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() {
              _view = _LoginView.login;
              _forgotSent = false;
            }),
            child: const Text('← Back to sign in', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12)),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Enter your email and we'll send you a reset link.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        const SizedBox(height: 16),
        _label('Email Address'),
        TextField(
          controller: _forgotEmailController,
          enabled: !_isLoading,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: _glassInput(hint: 'you@example.com'),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          _errorBox(_errorMessage!),
        ],
        const SizedBox(height: 18),
        _primaryBtn(
          label: _isLoading ? 'Sending…' : 'Send Reset Link',
          onPressed: _isLoading ? null : _sendForgotPassword,
          loading: _isLoading,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => setState(() {
                    _view = _LoginView.login;
                    _errorMessage = null;
                  }),
          child: const Text('← Back to sign in', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12)),
        ),
      ],
    );
  }

  Widget _primaryBtn({
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
      ),
      child: Text(msg, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12)),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  InputDecoration _glassInput({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: const Color(0xFFA1A1AA).withValues(alpha: 0.75)),
      filled: true,
      fillColor: const Color(0xFF0F172A).withValues(alpha: 0.65),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: const Color(0xFF93C5FD).withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
    );
  }
}
