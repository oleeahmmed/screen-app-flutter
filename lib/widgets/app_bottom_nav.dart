import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../theme/app_theme.dart';

/// Bottom tab bar — Home / My Task / Chat / Alerts / Me.
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
    (Icons.assignment_outlined, Icons.assignment_rounded, 'My Task'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_rounded, 'Chat'),
    (Icons.notifications_outlined, Icons.notifications_rounded, 'Alerts'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 420;

    return AppTheme.footerBlueGlass(
      topRadius: 16,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, compact ? 4 : 6),
          child: NavigationBar(
            selectedIndex: selectedIndex.clamp(0, _tabs.length - 1),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            height: compact ? 56 : 62,
            labelBehavior: compact
                ? NavigationDestinationLabelBehavior.alwaysHide
                : NavigationDestinationLabelBehavior.alwaysShow,
            indicatorColor: AppTheme.primary.withValues(alpha: 0.28),
            onDestinationSelected: onSelected,
            destinations: List.generate(_tabs.length, (i) {
              final (icon, iconSel, label) = _tabs[i];
              Widget iconWidget = Icon(selectedIndex == i ? iconSel : icon, size: compact ? 21 : 23);
              if (i == AppNavigation.tabAlerts && unreadNotifs > 0) {
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
