import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Jump to any main app section from any screen.
class AppQuickMenuButton extends StatelessWidget {
  final Color? iconColor;
  final double iconSize;
  final VoidCallback? onLogout;

  const AppQuickMenuButton({
    super.key,
    this.iconColor,
    this.iconSize = 22,
    this.onLogout,
  });

  static const _destinations = [
    (0, Icons.home_rounded, 'Home', 'Dashboard & clock'),
    (1, Icons.work_rounded, 'Work', 'Projects & tasks'),
    (2, Icons.chat_bubble_rounded, 'Chat', 'Messages'),
    (3, Icons.notifications_rounded, 'Alerts', 'Notifications'),
    (4, Icons.person_rounded, 'Profile', 'Settings & account'),
  ];

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: const Text('Log out?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'You will stop screenshot capture and return to the login screen.',
          style: TextStyle(color: AppTheme.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (onLogout != null) {
        onLogout!();
      } else {
        await AppNavigation.instance.logout();
      }
    }
  }

  List<Widget> _logoutTiles(BuildContext context, {required VoidCallback closeSheet}) {
    return [
      const Divider(color: Colors.white12, height: 20),
      ListTile(
        leading: const Icon(Icons.logout_rounded, color: AppTheme.danger),
        title: const Text('Log out', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
        subtitle: Text('Quick sign out', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 11)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () {
          closeSheet();
          _confirmLogout(context);
        },
      ),
    ];
  }

  void _go(BuildContext context, int index) {
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    AppNavigation.instance.selectTab(index);
  }

  Future<void> _open(BuildContext context) async {
    if (Responsive.isMobile(context)) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: AppTheme.modalBarrierColor,
        builder: (ctx) {
          final maxH = MediaQuery.sizeOf(ctx).height * 0.65;
          return AppTheme.glassBlur(
            child: SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Quick menu',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Jump to any section',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Shortcuts',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        ListTile(
                          leading: const Icon(Icons.assignment_outlined, color: AppTheme.warning),
                          title: const Text('Daily report', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                          subtitle: Text('Submit closing report', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 11)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onTap: () {
                            Navigator.pop(ctx);
                            AppNavigation.instance.openDailyReport();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.timeline_rounded, color: Color(0xFF38BDF8)),
                          title: const Text('Today\'s activity', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                          subtitle: Text('Clock-in & break log', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 11)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onTap: () {
                            Navigator.pop(ctx);
                            AppNavigation.instance.openActivity();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.lock_outline_rounded, color: Color(0xFFA78BFA)),
                          title: const Text('Vault', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                          subtitle: Text('Project credentials', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 11)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onTap: () {
                            Navigator.pop(ctx);
                            AppNavigation.instance.openVault();
                          },
                        ),
                        const Divider(color: Colors.white12, height: 20),
                        Text(
                          'Navigate',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        ..._destinations.map(
                          (d) => ListTile(
                            leading: Icon(d.$2, color: AppTheme.primaryBright),
                            title: Text(
                              d.$3,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              d.$4,
                              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 11),
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onTap: () {
                              Navigator.pop(ctx);
                              _go(context, d.$1);
                            },
                          ),
                        ),
                        ..._logoutTiles(context, closeSheet: () => Navigator.pop(ctx)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    final offset = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(40, 40);
    final screenW = MediaQuery.sizeOf(context).width;
    final menuW = 200.0;
    final left = (offset.dx + size.width - menuW).clamp(8.0, screenW - menuW - 8);

    await showMenu<int>(
      context: context,
      color: AppTheme.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
        left,
        offset.dy + size.height + 4,
        left + menuW,
        offset.dy,
      ),
      items: [
        PopupMenuItem<int>(
          enabled: false,
          height: 28,
          child: Text('Shortcuts', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        PopupMenuItem<int>(
          value: -1,
          onTap: () => AppNavigation.instance.openDailyReport(),
          child: const Row(children: [
            Icon(Icons.assignment_outlined, color: AppTheme.warning, size: 18),
            SizedBox(width: 10),
            Text('Daily report', style: TextStyle(color: AppTheme.textPrimary)),
          ]),
        ),
        PopupMenuItem<int>(
          value: -3,
          onTap: () => AppNavigation.instance.openActivity(),
          child: const Row(children: [
            Icon(Icons.timeline_rounded, color: Color(0xFF38BDF8), size: 18),
            SizedBox(width: 10),
            Text('Today\'s activity', style: TextStyle(color: AppTheme.textPrimary)),
          ]),
        ),
        PopupMenuItem<int>(
          value: -4,
          onTap: () => AppNavigation.instance.openVault(),
          child: const Row(children: [
            Icon(Icons.lock_outline_rounded, color: Color(0xFFA78BFA), size: 18),
            SizedBox(width: 10),
            Text('Vault', style: TextStyle(color: AppTheme.textPrimary)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          enabled: false,
          height: 28,
          child: Text('Navigate', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        ..._destinations
          .map(
            (d) => PopupMenuItem<int>(
              value: d.$1,
              child: Row(
                children: [
                  Icon(d.$2, color: AppTheme.primaryBright, size: 18),
                  const SizedBox(width: 10),
                  Text(d.$3, style: const TextStyle(color: AppTheme.textPrimary)),
                ],
              ),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          value: -99,
          onTap: () => _confirmLogout(context),
          child: const Row(children: [
            Icon(Icons.logout_rounded, color: AppTheme.danger, size: 18),
            SizedBox(width: 10),
            Text('Log out', style: TextStyle(color: AppTheme.danger)),
          ]),
        ),
      ],
    ).then((index) {
      if (index != null && index >= 0 && context.mounted) _go(context, index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _open(context),
      tooltip: 'Quick menu',
      icon: Icon(Icons.apps_rounded, color: iconColor ?? AppTheme.textMuted, size: iconSize),
    );
  }
}

/// Standard back control for pushed routes.
class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color? color;

  const AppBackButton({super.key, this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      tooltip: 'Back',
      icon: Icon(Icons.arrow_back_rounded, color: color ?? AppTheme.textMuted, size: 22),
      visualDensity: VisualDensity.compact,
    );
  }
}
