import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_session.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/platform_capabilities.dart';
import '../utils/responsive.dart';
import '../widgets/app_tab_shell.dart';
import 'data_privacy_notice_page.dart';

class ProfilePage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;

  const ProfilePage({
    super.key,
    required this.apiService,
    this.onLogout,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = true;
  String _username = '';
  final _emailCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _desigCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _photoUrl;
  bool _consent = false;
  bool _sound = true;
  bool _saving = false;

  String get _displayName {
    final n = '${_firstCtrl.text} ${_lastCtrl.text}'.trim();
    if (n.isNotEmpty) return n;
    if (_username.isNotEmpty) return _username;
    return 'Your profile';
  }

  String get _initials {
    final f = _firstCtrl.text.trim();
    final l = _lastCtrl.text.trim();
    if (f.isNotEmpty || l.isNotEmpty) {
      return '${f.isNotEmpty ? f[0] : ''}${l.isNotEmpty ? l[0] : ''}'.toUpperCase();
    }
    if (_username.isNotEmpty) return _username[0].toUpperCase();
    return '?';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _desigCtrl.dispose();
    _deptCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _applyProfileFromMap(Map<String, dynamic> d) {
    _username = d['username']?.toString() ?? '';
    _emailCtrl.text = d['email']?.toString() ?? '';
    _firstCtrl.text = d['first_name']?.toString() ?? '';
    _lastCtrl.text = d['last_name']?.toString() ?? '';
    final emp = d['employee'];
    if (emp is Map) {
      final em = Map<String, dynamic>.from(emp);
      _desigCtrl.text = em['designation']?.toString() ?? '';
      _deptCtrl.text = em['department']?.toString() ?? '';
      _phoneCtrl.text = em['phone']?.toString() ?? '';
    } else {
      _desigCtrl.clear();
      _deptCtrl.clear();
      _phoneCtrl.clear();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _sound = prefs.getBool('notification_sound_enabled') ?? true;

    final r = await widget.apiService.getUserProfile();
    if (!mounted) return;
    if (r['success'] == true) {
      final d = Map<String, dynamic>.from(r['data'] as Map);
      _applyProfileFromMap(d);
      final emp = d['employee'];
      final c = emp is Map && emp['screenshot_monitoring_consent'] == true;
      final pu = d['profile_photo']?.toString();
      final empPhoto = emp is Map ? emp['profile_photo_url']?.toString() : null;
      final resolvedPhoto = (pu != null && pu.isNotEmpty)
          ? pu
          : ((empPhoto != null && empPhoto.isNotEmpty) ? empPhoto : prefs.getString('profile_photo_url'));

      setState(() {
        _consent = c;
        if (resolvedPhoto != null && resolvedPhoto.isNotEmpty) {
          _photoUrl = resolvedPhoto;
        }
        _loading = false;
      });
      AppSession.setConsent(_consent);
      await prefs.setBool('screenshot_monitoring_consent', _consent);
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
        await prefs.setString('profile_photo_url', _photoUrl!);
      }
    } else {
      setState(() => _loading = false);
      if (mounted) {
        AppToast.error(context, r['error']?.toString() ?? 'Could not load profile');
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    final r = await widget.apiService.patchUserProfile({
      'email': _emailCtrl.text.trim(),
      'first_name': _firstCtrl.text.trim(),
      'last_name': _lastCtrl.text.trim(),
      'designation': _desigCtrl.text.trim(),
      'department': _deptCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'screenshot_monitoring_consent': _consent,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      final raw = r['data'];
      if (raw is Map) {
        _applyProfileFromMap(Map<String, dynamic>.from(raw));
      }
      AppSession.setConsent(_consent);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('screenshot_monitoring_consent', _consent);
      await prefs.setString(
        'full_name',
        '${_firstCtrl.text} ${_lastCtrl.text}'.trim(),
      );
      await prefs.setString('designation', _desigCtrl.text.trim());
      if (!mounted) return;
      setState(() {});
      AppToast.saved(context, message: 'Profile saved');
    } else {
      AppToast.saveFailed(context, r['error']?.toString());
    }
  }

  Future<void> _pickPhoto() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    List<int> bytes;
    if (f.bytes != null) {
      bytes = f.bytes!.toList();
    } else if (f.path != null) {
      bytes = await File(f.path!).readAsBytes();
    } else {
      return;
    }
    final up = await widget.apiService.uploadProfilePhoto(bytes);
    if (!mounted) return;
    if (up['success'] == true) {
      final url = up['data']?['profile_photo']?.toString();
      if (url != null) {
        setState(() => _photoUrl = url);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_photo_url', url);
      }
      if (!mounted) return;
      AppToast.updated(context, message: 'Photo updated');
    } else {
      if (!mounted) return;
      AppToast.error(context, up['error']?.toString() ?? 'Upload failed');
    }
  }

  Future<void> _toggleSound(bool v) async {
    setState(() => _sound = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_sound_enabled', v);
  }

  void _openPrivacy() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex.clamp(0, AppNavigation.tabCount - 1),
          unreadNotifs: AppNavigation.instance.unreadNotifs,
          onLogout: widget.onLogout,
          child: const DataPrivacyNoticePage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = Responsive.bottomNavInset(context) + 20;

    if (_loading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryBright),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHero()),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                Responsive.pagePadding(context),
                8,
                Responsive.pagePadding(context),
                bottomPad,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _sectionLabel('Account'),
                  const SizedBox(height: 10),
                  _buildAccountCard(),
                  const SizedBox(height: 22),
                  _sectionLabel('Preferences'),
                  const SizedBox(height: 10),
                  _buildPreferencesCard(),
                  const SizedBox(height: 22),
                  _sectionLabel('Privacy'),
                  const SizedBox(height: 10),
                  _buildPrivacyTile(),
                  const SizedBox(height: 28),
                  _buildSaveButton(),
                  if (widget.onLogout != null) ...[
                    const SizedBox(height: 12),
                    _buildLogoutButton(),
                  ],
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'AIMS',
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.55),
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppTheme.textMuted.withValues(alpha: 0.85),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildHero() {
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;
    final subtitle = [
      if (_desigCtrl.text.trim().isNotEmpty) _desigCtrl.text.trim(),
      if (_deptCtrl.text.trim().isNotEmpty) _deptCtrl.text.trim(),
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Responsive.pagePadding(context),
        8,
        Responsive.pagePadding(context),
        20,
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.9),
                      AppTheme.accent.withValues(alpha: 0.7),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(3),
                child: CircleAvatar(
                  backgroundColor: AppTheme.bgDeep,
                  backgroundImage: hasPhoto ? NetworkImage(_resolvePhotoUrl(_photoUrl!)) : null,
                  child: hasPhoto
                      ? null
                      : Text(
                          _initials,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: 2,
                child: Material(
                  color: AppTheme.primaryBright,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: InkWell(
                    onTap: _pickPhoto,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted.withValues(alpha: 0.95),
                fontSize: 14,
              ),
            ),
          ],
          if (_username.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Text(
                '@$_username',
                style: TextStyle(
                  color: AppTheme.primaryBright.withValues(alpha: 0.95),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('Update photo'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryBright,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    return _SurfaceCard(
      child: Column(
        children: [
          _field(_emailCtrl, 'Email', Icons.mail_outline_rounded, TextInputType.emailAddress),
          _divider(),
          Row(
            children: [
              Expanded(child: _field(_firstCtrl, 'First name', Icons.badge_outlined)),
              const SizedBox(width: 12),
              Expanded(child: _field(_lastCtrl, 'Last name', Icons.badge_outlined)),
            ],
          ),
          _divider(),
          _field(_phoneCtrl, 'Phone', Icons.phone_outlined, TextInputType.phone),
          _divider(),
          _field(_desigCtrl, 'Designation', Icons.work_outline_rounded),
          _divider(),
          _field(_deptCtrl, 'Department', Icons.apartment_rounded, null, 'e.g. Engineering'),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, [
    TextInputType? keyboard,
    String? hint,
  ]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
          hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5)),
          prefixIcon: Icon(icon, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.85)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
      );

  Widget _buildPreferencesCard() {
    return _SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          if (PlatformCapabilities.screenshotMonitoring) ...[
            _prefTile(
              icon: Icons.screenshot_monitor_rounded,
              iconColor: AppTheme.accent,
              title: 'Screenshot monitoring',
              subtitle: 'Allow captures while clocked in',
              value: _consent,
              onChanged: (v) => setState(() {
                _consent = v;
                AppSession.setConsent(v);
              }),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            ),
          ],
          _prefTile(
            icon: Icons.volume_up_rounded,
            iconColor: AppTheme.primaryBright,
            title: 'Notification sound',
            subtitle: 'Play sound for new alerts',
            value: _sound,
            onChanged: _toggleSound,
          ),
          if (!PlatformCapabilities.screenshotMonitoring)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Screenshot monitoring is available on desktop apps only.',
                style: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Capture interval: ${AppConfig.screenshotInterval}s',
                style: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.65),
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _prefTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      secondary: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
      ),
      value: value,
      activeThumbColor: AppTheme.primaryBright,
      onChanged: onChanged,
    );
  }

  Widget _buildPrivacyTile() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openPrivacy,
        borderRadius: BorderRadius.circular(18),
        child: _SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFA78BFA).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.shield_outlined, color: Color(0xFFA78BFA), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Data & privacy',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Screenshots & activity notice',
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: _saving ? null : _saveProfile,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Save changes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: () => AppNavigation.instance.logout(),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.danger,
          side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 20),
            SizedBox(width: 10),
            Text(
              'Log out',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  String _resolvePhotoUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    final origin = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/api/?$'), '');
    if (pathOrUrl.startsWith('/')) return '$origin$pathOrUrl';
    return '$origin/$pathOrUrl';
  }
}

class _SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
