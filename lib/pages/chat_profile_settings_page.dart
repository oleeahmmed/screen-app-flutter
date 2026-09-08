import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../generated/app_version.dart';
import '../services/api_service.dart';
import '../services/chat_wallpaper_prefs.dart';
import '../utils/app_toast.dart';
import '../widgets/chat_avatar.dart';
import 'data_privacy_notice_page.dart';
import 'profile_page.dart';

/// WhatsApp-style profile / settings hub opened from chat list menu.
class ChatProfileSettingsPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;

  const ChatProfileSettingsPage({
    super.key,
    required this.apiService,
    this.onLogout,
  });

  @override
  State<ChatProfileSettingsPage> createState() => _ChatProfileSettingsPageState();
}

class _ChatProfileSettingsPageState extends State<ChatProfileSettingsPage> {
  static const _waGreen = Color(0xFF00A884);
  static const _titleColor = Color(0xFF111B21);
  static const _subtitleColor = Color(0xFF667781);
  static const _iconColor = Color(0xFF54656F);
  static const _pageBg = Color(0xFFF0F2F5);
  static const _headerBg = Color(0xFFECE5DD);

  bool _loading = true;
  String _username = '';
  String _displayName = 'Your profile';
  String _designation = '';
  String _department = '';
  String? _photoUrl;
  bool _sound = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _sound = prefs.getBool('notification_sound_enabled') ?? true;

    final r = await widget.apiService.getUserProfile();
    if (!mounted) return;
    if (r['success'] == true) {
      final d = Map<String, dynamic>.from(r['data'] as Map);
      final first = d['first_name']?.toString().trim() ?? '';
      final last = d['last_name']?.toString().trim() ?? '';
      final full = '$first $last'.trim();
      _username = d['username']?.toString() ?? '';
      _displayName = full.isNotEmpty ? full : (_username.isNotEmpty ? _username : 'Your profile');
      final emp = d['employee'];
      if (emp is Map) {
        _designation = emp['designation']?.toString().trim() ?? '';
        _department = emp['department']?.toString().trim() ?? '';
      }
      final pu = d['profile_photo']?.toString();
      final empPhoto = emp is Map ? emp['profile_photo_url']?.toString() : null;
      final resolved = (pu != null && pu.isNotEmpty)
          ? pu
          : ((empPhoto != null && empPhoto.isNotEmpty) ? empPhoto : prefs.getString('profile_photo_url'));
      if (resolved != null && resolved.isNotEmpty) _photoUrl = resolved;
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _initials {
    final parts = _displayName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty) return parts.first[0].toUpperCase();
    return '?';
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(
          apiService: widget.apiService,
          onLogout: widget.onLogout,
          standalone: true,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _toggleSound(bool value) async {
    setState(() => _sound = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_sound_enabled', value);
  }

  Future<void> _resetChatWallpaper() async {
    await ChatWallpaperPrefs.setDoodle();
    if (!mounted) return;
    AppToast.updated(context, message: 'Chat wallpaper reset');
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _pageBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _waGreen))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  elevation: 0,
                  backgroundColor: _headerBg,
                  surfaceTintColor: Colors.transparent,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: _titleColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Edit profile',
                      onPressed: _openAccount,
                      icon: const Icon(Icons.edit_outlined, color: _titleColor, size: 22),
                    ),
                  ],
                  expandedHeight: 220,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      color: _headerBg,
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChatAvatar(
                            photoUrl: _photoUrl,
                            name: _displayName,
                            initials: _initials,
                            backgroundColor: _waGreen,
                            radius: 42,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _displayName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _titleColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (_designation.isNotEmpty || _department.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              [_designation, _department].where((s) => s.isNotEmpty).join(' · '),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: _subtitleColor, fontSize: 14),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -12),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          _settingsTile(
                            icon: Icons.key_rounded,
                            title: 'Account',
                            subtitle: 'Profile, email, security',
                            onTap: _openAccount,
                          ),
                          _divider(),
                          _settingsTile(
                            icon: Icons.lock_outline_rounded,
                            title: 'Privacy',
                            subtitle: 'Data privacy notice',
                            onTap: () {
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => const DataPrivacyNoticePage(),
                                ),
                              );
                            },
                          ),
                          _divider(),
                          _settingsTile(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'Chats',
                            subtitle: 'Wallpaper, appearance',
                            onTap: _resetChatWallpaper,
                          ),
                          _divider(),
                          SwitchListTile(
                            secondary: const Icon(Icons.notifications_none_rounded, color: _iconColor),
                            title: const Text(
                              'Notifications',
                              style: TextStyle(
                                color: _titleColor,
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: const Text(
                              'Message sounds',
                              style: TextStyle(color: _subtitleColor, fontSize: 13),
                            ),
                            value: _sound,
                            activeThumbColor: _waGreen,
                            onChanged: _toggleSound,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.onLogout != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
                          title: const Text(
                            'Log out',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: widget.onLogout,
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 16 + bottomSafe),
                    child: Column(
                      children: [
                        Text(
                          AppVersion.display,
                          style: TextStyle(color: _subtitleColor.withValues(alpha: 0.85), fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'AIMS',
                          style: TextStyle(
                            color: _subtitleColor,
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        indent: 68,
        color: const Color(0xFFE9EDEF),
      );

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: _iconColor, size: 24),
      title: Text(
        title,
        style: const TextStyle(
          color: _titleColor,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: _subtitleColor, fontSize: 13),
      ),
      onTap: onTap,
    );
  }
}
