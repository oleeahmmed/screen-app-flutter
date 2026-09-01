import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';
import 'app_quick_menu.dart';

/// Persistent top bar: logo → home, report / P2P / alerts / profile / logout.
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

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selectedIndex == AppNavigation.tabHome
            ? AppTheme.surface2.withValues(alpha: 0.35)
            : AppTheme.surface.withValues(alpha: 0.72),
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
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 8),
          child: Row(
            children: [
              if (ModalRoute.of(context)?.canPop ?? false) ...[
                const AppBackButton(color: AppTheme.textMuted),
                const SizedBox(width: 2),
              ],
              _logoHomeButton(),
              const Spacer(),
              AppHeaderMenuActions(
                onLogout: onLogout,
                unreadNotifs: unreadNotifs,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoHomeButton() {
    return Tooltip(
      message: 'Home',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => AppNavigation.instance.goHome(),
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.all(2),
            child: AppLogo(size: 32, showBorder: false),
          ),
        ),
      ),
    );
  }
}
