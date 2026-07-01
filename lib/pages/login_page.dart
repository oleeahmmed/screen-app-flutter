// login_page.dart — Login (aims-webapps glass style)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_session.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';

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
  bool _isLoading = false;
  bool _showPassword = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
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
      _usernameController.text,
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
      setState(() => _errorMessage = result['error'] ?? 'Login failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxW = Responsive.isMobile(context) ? double.infinity : 420.0;

    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: AppTheme.screenGradient()),
          // Ambient orbs
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.15,
            left: MediaQuery.sizeOf(context).width * 0.1,
            child: _orb(const Color(0xFF6366F1), 220),
          ),
          Positioned(
            bottom: MediaQuery.sizeOf(context).height * 0.15,
            right: MediaQuery.sizeOf(context).width * 0.08,
            child: _orb(const Color(0xFF0EA5E9), 200),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: Container(
                    decoration: AppTheme.loginShell(),
                    padding: EdgeInsets.all(Responsive.isMobile(context) ? 20 : 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              const AppLogo(size: 72),
                              const SizedBox(height: 16),
                              ShaderMask(
                                shaderCallback: (b) => AppTheme.titleGradient().createShader(b),
                                child: const Text(
                                  'AIMS',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Sign in to your workspace',
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: AppTheme.danger.withValues(alpha: 0.9), fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _label('Username'),
                        TextField(
                          controller: _usernameController,
                          enabled: !_isLoading,
                          style: const TextStyle(color: AppTheme.textPrimary),
                          decoration: _inputDeco(hint: 'Username or email'),
                        ),
                        const SizedBox(height: 14),
                        _label('Password'),
                        TextField(
                          controller: _passwordController,
                          enabled: !_isLoading,
                          obscureText: !_showPassword,
                          style: const TextStyle(color: AppTheme.textPrimary),
                          decoration: _inputDeco(hint: 'Password').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: AppTheme.textMuted,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                            ),
                          ),
                          onSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _isLoading ? null : _login,
                          style: AppTheme.primaryButton(),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '© AIMS Monitor Pro',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF52525B), fontSize: 11),
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

  Widget _orb(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  InputDecoration _inputDeco({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7)),
      filled: true,
      fillColor: AppTheme.surface2.withValues(alpha: 0.65),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: const Color(0xFF93C5FD).withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
    );
  }
}
