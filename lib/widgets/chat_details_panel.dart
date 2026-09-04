import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/platform_capabilities.dart';

/// WhatsApp-style contact / group details (right pane or bottom sheet).
class ChatDetailsPanel extends StatelessWidget {
  final bool isGroup;
  final String name;
  final String subtitle;
  final Color avatarColor;
  final String initials;
  final bool isOnline;
  final List<Map<String, dynamic>> mediaItems;
  final List<Map<String, dynamic>> fileItems;
  final List<Map<String, dynamic>> voiceItems;
  final VoidCallback onClose;
  final VoidCallback? onVideoCall;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onOpenGroupSettings;
  final VoidCallback? onSearchInChat;
  final ValueChanged<String>? onOpenMediaUrl;
  final String? username;
  final String? email;
  final String? description;
  final int memberCount;
  final ScrollController? scrollController;

  const ChatDetailsPanel({
    super.key,
    required this.isGroup,
    required this.name,
    required this.subtitle,
    required this.avatarColor,
    required this.initials,
    required this.isOnline,
    required this.mediaItems,
    required this.fileItems,
    required this.voiceItems,
    required this.onClose,
    this.onVideoCall,
    this.onVoiceCall,
    this.onOpenGroupSettings,
    this.onSearchInChat,
    this.onOpenMediaUrl,
    this.username,
    this.email,
    this.description,
    this.memberCount = 0,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0B141A),
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xF20B1220),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textPrimary),
                ),
                const Expanded(
                  child: Text(
                    'Contact info',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: [
                const SizedBox(height: 28),
                Center(
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: isGroup ? AppTheme.primary : avatarColor,
                    child: isGroup
                        ? const Icon(Icons.group_rounded, color: Colors.white, size: 48)
                        : Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 36,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isGroup ? '$memberCount members' : subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isOnline ? const Color(0xFF34D399) : AppTheme.textMuted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 22),
                if (!isGroup && PlatformCapabilities.voiceVideoCall)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ActionChip(
                          icon: Icons.videocam_rounded,
                          label: 'Video',
                          onTap: onVideoCall,
                        ),
                        const SizedBox(width: 12),
                        _ActionChip(
                          icon: Icons.call_rounded,
                          label: 'Audio',
                          onTap: onVoiceCall,
                        ),
                        const SizedBox(width: 12),
                        _ActionChip(
                          icon: Icons.search_rounded,
                          label: 'Search',
                          onTap: onSearchInChat,
                        ),
                      ],
                    ),
                  ),
                if (isGroup)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ActionChip(
                          icon: Icons.groups_rounded,
                          label: 'Members',
                          onTap: onOpenGroupSettings,
                        ),
                        const SizedBox(width: 12),
                        _ActionChip(
                          icon: Icons.search_rounded,
                          label: 'Search',
                          onTap: onSearchInChat,
                        ),
                        const SizedBox(width: 12),
                        _ActionChip(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          onTap: onOpenGroupSettings,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                _sectionCard([
                  if (!isGroup && (username ?? '').isNotEmpty)
                    _infoTile(Icons.alternate_email_rounded, 'Username', '@$username'),
                  if (!isGroup && (email ?? '').isNotEmpty)
                    _infoTile(Icons.email_outlined, 'Email', email!),
                  if (isGroup && (description ?? '').trim().isNotEmpty)
                    _infoTile(Icons.info_outline_rounded, 'Description', description!),
                  if (!isGroup)
                    _infoTile(
                      Icons.schedule_rounded,
                      'Status',
                      isOnline ? 'Online' : subtitle,
                    ),
                ]),
                _mediaSection(
                  title: 'Media',
                  count: mediaItems.length,
                  empty: 'No photos yet',
                  child: mediaItems.isEmpty
                      ? null
                      : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: mediaItems.length.clamp(0, 12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemBuilder: (_, i) {
                            final url = (mediaItems[i]['image_url'] ?? '').toString();
                            return InkWell(
                              onTap: () => onOpenMediaUrl?.call(url),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, error, stack) => ColoredBox(
                                  color: AppTheme.surface2,
                                  child: Icon(Icons.broken_image_outlined,
                                      color: AppTheme.textMuted.withValues(alpha: 0.6)),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                _mediaSection(
                  title: 'Documents',
                  count: fileItems.length,
                  empty: 'No documents yet',
                  child: fileItems.isEmpty
                      ? null
                      : Column(
                          children: fileItems.take(8).map((f) {
                            final url = (f['file_url'] ?? '').toString();
                            final label = (f['message'] ?? f['file_name'] ?? 'Document').toString();
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.insert_drive_file_rounded, color: AppTheme.primaryBright),
                              title: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              ),
                              onTap: () => onOpenMediaUrl?.call(url),
                            );
                          }).toList(),
                        ),
                ),
                _mediaSection(
                  title: 'Voice messages',
                  count: voiceItems.length,
                  empty: 'No voice messages yet',
                  child: voiceItems.isEmpty
                      ? null
                      : Column(
                          children: voiceItems.take(6).map((v) {
                            final url = (v['voice_url'] ?? '').toString();
                            final when = (v['created_at'] ?? v['timestamp'] ?? '').toString();
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.mic_rounded, color: AppTheme.accent),
                              title: const Text('Voice message', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                              subtitle: Text(when, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                              onTap: () => onOpenMediaUrl?.call(url),
                            );
                          }).toList(),
                        ),
                ),
                if (isGroup && onOpenGroupSettings != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      tileColor: AppTheme.surface2.withValues(alpha: 0.55),
                      leading: const Icon(Icons.manage_accounts_rounded, color: AppTheme.primaryBright),
                      title: const Text('Group settings', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: const Text('Members, roles, edit group', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                      onTap: onOpenGroupSettings,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface2.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: AppTheme.textMuted, size: 22),
      title: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      subtitle: Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
    );
  }

  Widget _mediaSection({
    required String title,
    required int count,
    required String empty,
    Widget? child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        decoration: BoxDecoration(
          color: AppTheme.surface2.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                const Spacer(),
                Text('$count', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
            if (child == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(empty, style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 13)),
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface2.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 76,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppTheme.primaryBright, size: 22),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openChatMediaUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
