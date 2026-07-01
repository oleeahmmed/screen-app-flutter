import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_session.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_primary_button.dart';
import '../widgets/app_shell.dart';
import '../widgets/glass_card.dart';
import 'data_privacy_notice_page.dart';

class ProfilePage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onOpenP2P;
  final VoidCallback? onLogout;

  const ProfilePage({
    super.key,
    required this.apiService,
    this.onOpenP2P,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r['error']?.toString() ?? 'Could not load profile')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Save failed')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo updated')),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(up['error']?.toString() ?? 'Upload failed')),
      );
    }
  }

  Future<void> _toggleSound(bool v) async {
    setState(() => _sound = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_sound_enabled', v);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AppShell(
        wide: true,
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryBright),
        ),
      );
    }

    return AppShell(
      scrollable: true,
      wide: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Profile & settings', style: AppTheme.pageTitle),
          const SizedBox(height: 4),
          Text(
            'Account, photo, screenshot consent, and alerts',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DataPrivacyNoticePage(),
                ),
              );
            },
            child: Row(
              children: [
                Icon(Icons.description_outlined, color: AppTheme.primaryBright.withValues(alpha: 0.9)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Data & privacy', style: AppTheme.sectionTitle),
                      const SizedBox(height: 2),
                      Text('Screenshots & activity data notice', style: AppTheme.caption),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppTheme.textMuted.withValues(alpha: 0.7)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: AppTheme.surface2,
                        backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                            ? NetworkImage(_resolvePhotoUrl(_photoUrl!))
                            : null,
                        child: (_photoUrl == null || _photoUrl!.isEmpty)
                            ? Icon(Icons.person, size: 48, color: AppTheme.textMuted)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: AppTheme.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: _pickPhoto,
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.camera_alt, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(onPressed: _pickPhoto, child: const Text('Change photo')),
                ),
                const SizedBox(height: 8),
                Text('Username', style: AppTheme.caption),
                const SizedBox(height: 4),
                Text(
                  _username.isEmpty ? '—' : _username,
                  style: AppTheme.sectionTitle.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _firstCtrl,
                        decoration: const InputDecoration(labelText: 'First name'),
                        style: const TextStyle(color: AppTheme.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lastCtrl,
                        decoration: const InputDecoration(labelText: 'Last name'),
                        style: const TextStyle(color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _desigCtrl,
                  decoration: const InputDecoration(labelText: 'Designation'),
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deptCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    hintText: 'e.g. Engineering, Sales',
                  ),
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Screenshot monitoring', style: AppTheme.sectionTitle),
                  subtitle: Text(
                    'Allow screen captures while clocked in. Server will reject uploads if disabled.',
                    style: AppTheme.caption,
                  ),
                  value: _consent,
                  activeThumbColor: AppTheme.primaryBright,
                  onChanged: (v) => setState(() {
                    _consent = v;
                    AppSession.setConsent(v);
                  }),
                ),
                Divider(color: AppTheme.border, height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Notification sound', style: AppTheme.sectionTitle),
                  subtitle: Text(
                    'Play a short sound when new alerts arrive',
                    style: AppTheme.caption,
                  ),
                  value: _sound,
                  activeThumbColor: AppTheme.primaryBright,
                  onChanged: _toggleSound,
                ),
                const SizedBox(height: 4),
                Text(
                  'Capture interval: ${AppConfig.screenshotInterval}s (build flag SCREENSHOT_INTERVAL_SEC)',
                  style: AppTheme.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          if (widget.onOpenP2P != null) ...[
            const SizedBox(height: 14),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              onTap: widget.onOpenP2P,
              child: Row(
                children: [
                  Icon(Icons.swap_horiz, color: AppTheme.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Peer-to-peer transfer', style: AppTheme.sectionTitle),
                        const SizedBox(height: 2),
                        Text('Send files over local network', style: AppTheme.caption),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppTheme.textMuted.withValues(alpha: 0.7)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          AppPrimaryButton(
            label: _saving ? 'Saving…' : 'Save changes',
            icon: _saving ? null : Icons.save,
            loading: _saving,
            expanded: true,
            onPressed: _saving ? null : _saveProfile,
          ),
          if (widget.onLogout != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout, color: AppTheme.danger),
                label: const Text('Log out'),
                style: AppTheme.secondaryButton().copyWith(
                  foregroundColor: WidgetStateProperty.all(AppTheme.danger),
                  side: WidgetStateProperty.all(const BorderSide(color: AppTheme.danger)),
                ),
              ),
            ),
          ],
        ],
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
