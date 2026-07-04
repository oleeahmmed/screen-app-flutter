import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bottom tab bar — Home / Work / Chat / Alerts / Me (aims-webapps mobile nav).
class AppBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int unreadNotifs;

  const AppBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.unreadNotifs = 0,
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
    final compact = w < 360;

    return AppTheme.glassBlur(
      topRadius: 16,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, 4, 6, compact ? 4 : 6),
          child: NavigationBar(
            selectedIndex: selectedIndex.clamp(0, _tabs.length - 1),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            height: compact ? 58 : 64,
            labelBehavior: compact
                ? NavigationDestinationLabelBehavior.alwaysHide
                : NavigationDestinationLabelBehavior.alwaysShow,
            indicatorColor: AppTheme.primary.withValues(alpha: 0.22),
            onDestinationSelected: onSelected,
            destinations: List.generate(_tabs.length, (i) {
              final (icon, iconSel, label) = _tabs[i];
              Widget iconWidget = Icon(selectedIndex == i ? iconSel : icon, size: compact ? 22 : 24);
              if (i == 3 && unreadNotifs > 0) {
                iconWidget = Badge(
                  isLabelVisible: true,
                  label: Text(unreadNotifs > 9 ? '9+' : '$unreadNotifs'),
                  child: iconWidget,
                );
              }
              return NavigationDestination(icon: iconWidget, label: label);
            }),
          ),
        ),
      ),
    );
  }
}
