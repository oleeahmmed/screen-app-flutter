import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import '../utils/platform_capabilities.dart';
import 'app_quick_menu.dart';

/// Persistent top bar: branding, section tabs (wide screens), quick menu.
class AppTopBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int unreadNotifs;
  final VoidCallback? onLogout;

  const AppTopBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.unreadNotifs = 0,
    this.onLogout,
  });

  static const _tabs = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.assignment_outlined, Icons.assignment_rounded, 'My Task'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_rounded, 'Chat'),
    (Icons.notifications_outlined, Icons.notifications_rounded, 'Alerts'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.72),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 8),
          child: Row(
            children: [
              _brandMark(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _tabs[selectedIndex.clamp(0, _tabs.length - 1)].$3,
                  style: AppTheme.pageTitle.copyWith(fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selectedIndex == AppNavigation.tabAlerts &&
                  PlatformCapabilities.peerToPeerFileTransfer)
                IconButton(
                  onPressed: () => AppNavigation.instance.openP2P(),
                  tooltip: 'Peer-to-peer file transfer',
                  icon: const Icon(Icons.swap_horiz_rounded, color: AppTheme.accent, size: 24),
                ),
              AppQuickMenuButton(onLogout: onLogout),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandMark() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withValues(alpha: 0.95),
                AppTheme.accent.withValues(alpha: 0.75),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: const Text(
            'A',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ShaderMask(
          shaderCallback: (b) => AppTheme.titleGradient().createShader(b),
          child: const Text(
            'AIMS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }
}
