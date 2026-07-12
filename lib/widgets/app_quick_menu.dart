import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Log out with confirmation — shown as an icon beside the quick menu.
class AppLogoutButton extends StatelessWidget {
  final VoidCallback? onLogout;
  final Color? iconColor;
  final double iconSize;

  const AppLogoutButton({
    super.key,
    this.onLogout,
    this.iconColor,
    this.iconSize = 22,
  });

  static Future<void> confirmAndLogout(
    BuildContext context, {
    VoidCallback? onLogout,
  }) async {
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
        onLogout();
      } else {
        await AppNavigation.instance.logout();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Log out',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => confirmAndLogout(context, onLogout: onLogout),
          customBorder: const CircleBorder(),
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEF4444), Color(0xFF991B1B)],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.danger.withValues(alpha: 0.38),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              Icons.power_rounded,
              color: Colors.white,
              size: iconSize * 0.82,
            ),
          ),
        ),
      ),
    );
  }
}

/// Submit daily report — opens closing report modal (dashboard glass style).
class AppSubmitReportButton extends StatelessWidget {
  const AppSubmitReportButton({super.key});

  Future<void> _open() async {
    await AppNavigation.instance.openSubmitReport();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;

    return Tooltip(
      message: 'Submit report',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 6,
            ),
            decoration: AppTheme.loginInsetDecoration(borderRadius: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.assignment_turned_in_rounded,
                  size: 16,
                  color: AppTheme.accent,
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  const Text(
                    'Submit Report',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick menu + logout icon (logout sits on the right).
class AppHeaderMenuActions extends StatelessWidget {
  final VoidCallback? onLogout;
  final Color? iconColor;
  final double iconSize;

  const AppHeaderMenuActions({
    super.key,
    this.onLogout,
    this.iconColor,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSubmitReportButton(),
        const SizedBox(width: 6),
        AppQuickMenuButton(iconColor: iconColor, iconSize: iconSize),
        AppLogoutButton(
          onLogout: onLogout,
          iconColor: iconColor ?? AppTheme.danger,
          iconSize: iconSize,
        ),
      ],
    );
  }
}

/// Jump to app shortcuts (Vault, Project) from any screen.
class AppQuickMenuButton extends StatelessWidget {
  final Color? iconColor;
  final double iconSize;

  const AppQuickMenuButton({
    super.key,
    this.iconColor,
    this.iconSize = 22,
  });

  Future<void> _open(BuildContext context) async {
    if (Responsive.isMobile(context)) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: AppTheme.modalBarrierColor,
        builder: (ctx) {
          final maxH = MediaQuery.sizeOf(ctx).height * 0.5;
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
                          'Shortcuts',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
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
                        ListTile(
                          leading: const Icon(Icons.folder_open_rounded, color: AppTheme.primaryBright),
                          title: const Text('Project', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                          subtitle: Text('Browse & manage projects', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 11)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onTap: () {
                            Navigator.pop(ctx);
                            AppNavigation.instance.openProject();
                          },
                        ),
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
          value: -4,
          onTap: () => AppNavigation.instance.openVault(),
          child: const Row(children: [
            Icon(Icons.lock_outline_rounded, color: Color(0xFFA78BFA), size: 18),
            SizedBox(width: 10),
            Text('Vault', style: TextStyle(color: AppTheme.textPrimary)),
          ]),
        ),
        PopupMenuItem<int>(
          value: -5,
          onTap: () => AppNavigation.instance.openProject(),
          child: const Row(children: [
            Icon(Icons.folder_open_rounded, color: AppTheme.primaryBright, size: 18),
            SizedBox(width: 10),
            Text('Project', style: TextStyle(color: AppTheme.textPrimary)),
          ]),
        ),
      ],
    );
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
