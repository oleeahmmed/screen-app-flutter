import 'package:flutter/material.dart';

import '../app_session.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';
import 'app_quick_menu.dart';

/// Persistent top bar: logo → home, optional Select Apps, report / P2P / alerts / profile / logout.
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
              const SizedBox(width: 8),
              ValueListenableBuilder<int>(
                valueListenable: AppSession.captureUiRevision,
                builder: (context, rev, child) {
                  if (!AppSession.showSelectAppsInTopBar) {
                    return const SizedBox.shrink();
                  }
                  final n = AppSession.selectedAppsCount;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton.icon(
                      onPressed: AppSession.openSelectApps,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.apps_rounded, size: 18),
                      label: Text(
                        n > 0 ? 'Apps ($n)' : 'Select Apps',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                    ),
                  );
                },
              ),
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
