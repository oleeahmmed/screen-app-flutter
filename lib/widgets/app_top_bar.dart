import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
    (Icons.work_outline_rounded, Icons.work_rounded, 'Work'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_rounded, 'Chat'),
    (Icons.notifications_outlined, Icons.notifications_rounded, 'Alerts'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final showTopTabs = w >= 768;

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
              if (showTopTabs) ...[
                const SizedBox(width: 20),
                Expanded(child: _topNavPills()),
              ] else ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _tabs[selectedIndex.clamp(0, _tabs.length - 1)].$3,
                    style: AppTheme.pageTitle.copyWith(fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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

  Widget _topNavPills() {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 900;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final selected = i == selectedIndex;
              final (icon, iconSel, label) = _tabs[i];
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Material(
                  color: selected
                      ? AppTheme.primary.withValues(alpha: 0.24)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => onSelected(i),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppTheme.primary.withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _tabIcon(i, selected ? iconSel : icon, selected),
                          if (!compact) ...[
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected ? AppTheme.primaryBright : AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _tabIcon(int index, IconData icon, bool selected) {
    final color = selected ? AppTheme.primaryBright : AppTheme.textMuted;
    if (index == 3 && unreadNotifs > 0) {
      return Badge(
        isLabelVisible: true,
        label: Text(unreadNotifs > 9 ? '9+' : '$unreadNotifs'),
        child: Icon(icon, size: 18, color: color),
      );
    }
    return Icon(icon, size: 18, color: color);
  }
}
