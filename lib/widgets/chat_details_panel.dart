import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/platform_capabilities.dart';

/// WhatsApp-style contact / group info (right pane or full-screen sheet).
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
  final VoidCallback? onAddMembers;
  final VoidCallback? onOpenMembers;
  final VoidCallback? onSearchInChat;
  final VoidCallback? onChangeWallpaper;
  final bool isPinned;
  final VoidCallback? onTogglePin;
  final ValueChanged<String>? onOpenMediaUrl;
  final String? username;
  final String? email;
  final String? designation;
  final String? description;
  final String? photoUrl;
  final int memberCount;
  final bool canEdit;
  final VoidCallback? onEditName;
  final VoidCallback? onEditDescription;
  final VoidCallback? onChangePhoto;
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
    this.onAddMembers,
    this.onOpenMembers,
    this.onSearchInChat,
    this.onChangeWallpaper,
    this.isPinned = false,
    this.onTogglePin,
    this.onOpenMediaUrl,
    this.username,
    this.email,
    this.designation,
    this.description,
    this.photoUrl,
    this.memberCount = 0,
    this.canEdit = false,
    this.onEditName,
    this.onEditDescription,
    this.onChangePhoto,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final desc = (description ?? '').trim();
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;

    return ColoredBox(
      color: const Color(0xFF0B141A),
      child: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: [
                const SizedBox(height: 24),
                Center(child: _avatar(hasPhoto)),
                const SizedBox(height: 18),
                _nameRow(),
                const SizedBox(height: 8),
                _subtitleRow(),
                const SizedBox(height: 24),
                _actionRow(),
                const SizedBox(height: 20),
                if (isGroup) _groupDescriptionRow(desc),
                if (!isGroup) _contactAboutCard(desc),
                const SizedBox(height: 8),
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
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: AppTheme.textMuted.withValues(alpha: 0.6),
                                  ),
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
                              title: const Text(
                                'Voice message',
                                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              ),
                              subtitle: Text(
                                when,
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                              ),
                              onTap: () => onOpenMediaUrl?.call(url),
                            );
                          }).toList(),
                        ),
                ),
                if (isGroup && onOpenMembers != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      tileColor: AppTheme.surface2.withValues(alpha: 0.55),
                      leading: const Icon(Icons.people_outline_rounded, color: AppTheme.primaryBright),
                      title: const Text('Members', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: Text(
                        '$memberCount members',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                      onTap: onOpenMembers,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
          Expanded(
            child: Text(
              isGroup ? 'Group info' : 'Contact info',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(bool hasPhoto) {
    return GestureDetector(
      onTap: canEdit && isGroup ? onChangePhoto : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 58,
            backgroundColor: isGroup ? const Color(0xFF3B4A54) : avatarColor,
            backgroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
            child: hasPhoto
                ? null
                : (isGroup
                    ? const Icon(Icons.group_rounded, color: Colors.white70, size: 52)
                    : Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 38,
                        ),
                      )),
          ),
          if (canEdit && isGroup)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF00A884),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0B141A), width: 2),
                ),
                child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nameRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          if (canEdit && isGroup && onEditName != null) ...[
            const SizedBox(width: 6),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onEditName,
              icon: Icon(Icons.edit_outlined, size: 18, color: Colors.white.withValues(alpha: 0.65)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _subtitleRow() {
    if (isGroup) {
      return RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
          children: [
            const TextSpan(text: 'Group · '),
            TextSpan(
              text: '$memberCount members',
              style: const TextStyle(color: Color(0xFF00A884)),
            ),
          ],
        ),
      );
    }
    return Text(
      subtitle,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: isOnline ? const Color(0xFF00A884) : AppTheme.textMuted,
        fontSize: 14,
      ),
    );
  }

  Widget _actionRow() {
    if (isGroup) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (PlatformCapabilities.voiceVideoCall)
              _ActionChip(icon: Icons.call_rounded, label: 'Voice', onTap: onVoiceCall),
            if (PlatformCapabilities.voiceVideoCall)
              _ActionChip(icon: Icons.videocam_rounded, label: 'Video', onTap: onVideoCall),
            _ActionChip(icon: Icons.person_add_alt_1_rounded, label: 'Add', onTap: onAddMembers),
            _ActionChip(icon: Icons.search_rounded, label: 'Search', onTap: onSearchInChat),
            _ActionChip(
              icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              label: isPinned ? 'Unpin' : 'Pin',
              onTap: onTogglePin,
            ),
            _ActionChip(icon: Icons.wallpaper_rounded, label: 'Wallpaper', onTap: onChangeWallpaper),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (PlatformCapabilities.voiceVideoCall)
            _ActionChip(icon: Icons.videocam_rounded, label: 'Video', onTap: onVideoCall),
          if (PlatformCapabilities.voiceVideoCall)
            _ActionChip(icon: Icons.call_rounded, label: 'Audio', onTap: onVoiceCall),
          _ActionChip(icon: Icons.search_rounded, label: 'Search', onTap: onSearchInChat),
          _ActionChip(
            icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            label: isPinned ? 'Unpin' : 'Pin',
            onTap: onTogglePin,
          ),
          _ActionChip(icon: Icons.wallpaper_rounded, label: 'Wallpaper', onTap: onChangeWallpaper),
        ],
      ),
    );
  }

  Widget _groupDescriptionRow(String desc) {
    final empty = desc.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: AppTheme.surface2.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: canEdit ? onEditDescription : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    empty ? 'Add group description' : desc,
                    style: TextStyle(
                      color: empty ? const Color(0xFF00A884) : AppTheme.textPrimary,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ),
                if (canEdit && onEditDescription != null)
                  Icon(Icons.edit_outlined, size: 18, color: Colors.white.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contactAboutCard(String about) {
    final tiles = <Widget>[];
    if ((designation ?? '').trim().isNotEmpty) {
      tiles.add(_infoTile(Icons.work_outline_rounded, 'Designation', designation!));
    }
    if ((username ?? '').trim().isNotEmpty) {
      tiles.add(_infoTile(Icons.alternate_email_rounded, 'Username', '@$username'));
    }
    if ((email ?? '').trim().isNotEmpty) {
      tiles.add(_infoTile(Icons.email_outlined, 'Email', email!));
    }
    tiles.add(_infoTile(
      Icons.schedule_rounded,
      'Status',
      isOnline ? 'Online' : subtitle,
    ));
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface2.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: tiles),
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
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text('$count', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
            if (child == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  empty,
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 13),
                ),
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
      color: const Color(0xFF1F2C34),
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF00A884), size: 24),
              const SizedBox(height: 6),
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
