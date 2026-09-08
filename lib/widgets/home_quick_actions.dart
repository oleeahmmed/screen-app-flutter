import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/app_navigation.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../utils/platform_capabilities.dart';

/// Vault · Monitor · P2P · Submit Report shortcuts on the home dashboard.
class HomeQuickActions extends StatefulWidget {
  const HomeQuickActions({super.key});

  @override
  State<HomeQuickActions> createState() => _HomeQuickActionsState();
}

class _HomeQuickActionsState extends State<HomeQuickActions> {
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final admin = await UserDataService.isCompanyAdmin();
    if (mounted) setState(() => _isAdmin = admin);
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _QuickActionTile(
        icon: LucideIcons.shield,
        label: 'Vault',
        gradient: const [Color(0xFFA78BFA), Color(0xFF7C3AED)],
        glow: AppTheme.featureVault,
        onTap: () => AppNavigation.instance.openVault(),
      ),
      if (_isAdmin && PlatformCapabilities.screenshotMonitoring)
        _QuickActionTile(
          icon: LucideIcons.monitor,
          label: 'Monitor',
          gradient: const [Color(0xFF34D399), Color(0xFF059669)],
          glow: AppTheme.success,
          onTap: () => AppNavigation.instance.openLiveMonitor(),
        ),
      if (PlatformCapabilities.peerToPeerFileTransfer)
        _QuickActionTile(
          icon: LucideIcons.arrowLeftRight,
          label: 'P2P',
          gradient: const [Color(0xFF38BDF8), Color(0xFF0284C7)],
          glow: AppTheme.accent,
          onTap: () => AppNavigation.instance.openP2P(),
        ),
      _QuickActionTile(
        icon: LucideIcons.clipboardCheck,
        label: 'Report',
        gradient: const [Color(0xFF60A5FA), Color(0xFF2563EB)],
        glow: AppTheme.primaryBright,
        onTap: () => AppNavigation.instance.openSubmitReport(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'QUICK ACTIONS',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppTheme.textMuted.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final Color glow;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.glow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: AppTheme.loginInsetDecoration(borderRadius: 11).copyWith(
            border: Border.all(color: glow.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: glow.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, size: 15, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
