import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/local_time.dart';
import '../utils/platform_capabilities.dart';
import 'chat_avatar.dart';

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

  static const _accent = Color(0xFF00A884);

  @override
  Widget build(BuildContext context) {
    final desc = (description ?? '').trim();
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;

    return ColoredBox(
      color: Colors.transparent,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: [
                const SizedBox(height: 20),
                Center(child: _avatar(hasPhoto)),
                const SizedBox(height: 16),
                _nameRow(),
                const SizedBox(height: 6),
                _subtitleRow(),
                const SizedBox(height: 20),
                _actionRow(),
                const SizedBox(height: 16),
                if (isGroup) _groupDescriptionRow(desc),
                if (!isGroup) _contactAboutCard(desc),
                const SizedBox(height: 4),
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
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                onTap: () => onOpenMediaUrl?.call(url),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, error, stack) => ColoredBox(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: AppTheme.textMuted.withValues(alpha: 0.6),
                                    ),
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
                            final when = formatChatDetailTime(v['created_at'] ?? v['timestamp']);
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
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onOpenMembers,
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          decoration: AppTheme.loginInsetDecoration(borderRadius: 14),
                          child: ListTile(
                            leading: const Icon(Icons.people_outline_rounded, color: AppTheme.primaryBright),
                            title: const Text('Members', style: TextStyle(color: AppTheme.textPrimary)),
                            subtitle: Text(
                              '$memberCount members',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                          ),
                        ),
                      ),
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
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
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
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
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
        alignment: Alignment.center,
        children: [
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary.withValues(alpha: 0.85),
                  AppTheme.accent.withValues(alpha: 0.75),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(3),
            child: isGroup
                ? CircleAvatar(
                    backgroundColor: avatarColor,
                    backgroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
                    child: hasPhoto
                        ? null
                        : const Icon(Icons.group_rounded, color: Colors.white, size: 48),
                  )
                : ChatAvatar(
                    photoUrl: photoUrl,
                    name: name,
                    initials: initials,
                    backgroundColor: avatarColor,
                    radius: 58,
                    showOnlineIndicator: true,
                    isOnline: isOnline,
                  ),
          ),
          if (canEdit && isGroup)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.bgDeep, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (canEdit && isGroup && onEditName != null) ...[
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onEditName,
              icon: Icon(Icons.edit_outlined, size: 18, color: AppTheme.textMuted.withValues(alpha: 0.9)),
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
          style: TextStyle(fontSize: 14, color: AppTheme.textMuted.withValues(alpha: 0.95)),
          children: [
            const TextSpan(text: 'Group · '),
            TextSpan(
              text: '$memberCount members',
              style: const TextStyle(color: _accent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isOnline)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
          ),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isOnline ? _accent : AppTheme.textMuted.withValues(alpha: 0.95),
            fontSize: 14,
            fontWeight: isOnline ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  List<Widget> _actionButtons() {
    final chips = <Widget>[];

    void add(IconData icon, String label, VoidCallback? onTap) {
      if (onTap == null) return;
      chips.add(_ActionChip(icon: icon, label: label, onTap: onTap));
    }

    if (isGroup) {
      if (PlatformCapabilities.voiceVideoCall) {
        add(Icons.call_rounded, 'Voice', onVoiceCall);
        add(Icons.videocam_rounded, 'Video', onVideoCall);
      }
      add(Icons.person_add_alt_1_rounded, 'Add', onAddMembers);
      add(Icons.search_rounded, 'Search', onSearchInChat);
      add(
        isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
        isPinned ? 'Unpin' : 'Pin',
        onTogglePin,
      );
      add(Icons.wallpaper_rounded, 'Wallpaper', onChangeWallpaper);
    } else {
      if (PlatformCapabilities.voiceVideoCall) {
        add(Icons.videocam_rounded, 'Video', onVideoCall);
        add(Icons.call_rounded, 'Audio', onVoiceCall);
      }
      add(Icons.search_rounded, 'Search', onSearchInChat);
      add(
        isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
        isPinned ? 'Unpin' : 'Pin',
        onTogglePin,
      );
      add(Icons.wallpaper_rounded, 'Wallpaper', onChangeWallpaper);
    }

    return chips;
  }

  Widget _actionRow() {
    final buttons = _actionButtons();
    if (buttons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: buttons[i]),
          ],
        ],
      ),
    );
  }

  Widget _groupDescriptionRow(String desc) {
    final empty = desc.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canEdit ? onEditDescription : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: AppTheme.loginInsetDecoration(borderRadius: 14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      empty ? 'Add group description' : desc,
                      style: TextStyle(
                        color: empty ? _accent : AppTheme.textPrimary,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (canEdit && onEditDescription != null)
                    Icon(Icons.edit_outlined, size: 18, color: AppTheme.textMuted.withValues(alpha: 0.7)),
                ],
              ),
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
      child: AppTheme.glassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: tiles),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return ListTile(
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.primaryBright, size: 20),
      ),
      title: Text(label, style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12)),
      subtitle: Text(
        value,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _mediaSection({
    required String title,
    required int count,
    required String empty,
    Widget? child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AppTheme.glassCard(
        borderRadius: 16,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(color: AppTheme.primaryBright, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (child == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
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

  static const _accent = Color(0xFF00A884);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: AppTheme.loginInsetDecoration(borderRadius: 14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _accent.withValues(alpha: 0.22),
                        AppTheme.primary.withValues(alpha: 0.16),
                      ],
                    ),
                    border: Border.all(color: _accent.withValues(alpha: 0.28)),
                  ),
                  child: Icon(icon, color: _accent, size: 21),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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
