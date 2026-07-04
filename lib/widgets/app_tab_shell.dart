import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import 'app_bottom_nav.dart';
import 'app_top_bar.dart';

/// Persistent shell: top bar + page body + bottom nav (all pushed routes).
class AppTabShell extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final int unreadNotifs;
  final VoidCallback? onLogout;
  final bool showTopBar;

  const AppTabShell({
    super.key,
    required this.child,
    required this.selectedIndex,
    this.unreadNotifs = 0,
    this.onLogout,
    this.showTopBar = true,
  });

  void _onTab(int index) {
    AppNavigation.instance.navigateToTab(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTopBar)
            AppTopBar(
              selectedIndex: selectedIndex,
              onSelected: _onTab,
              unreadNotifs: unreadNotifs,
              onLogout: onLogout,
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        selectedIndex: selectedIndex,
        onSelected: _onTab,
        unreadNotifs: unreadNotifs,
      ),
    );
  }
}
