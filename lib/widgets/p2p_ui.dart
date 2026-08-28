import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Home-dashboard-style shell for P2P screens.
class P2pHubCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const P2pHubCard({
    super.key,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.loginShell().copyWith(
        borderRadius: BorderRadius.circular(18),
      ),
      padding: padding ?? const EdgeInsets.all(18),
      child: child,
    );
  }
}

class P2pPageFrame extends StatelessWidget {
  final Widget child;
  final bool scroll;
  final bool center;

  const P2pPageFrame({
    super.key,
    required this.child,
    this.scroll = true,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    final pad = Responsive.pagePadding(context);
    final card = Align(
      alignment: center ? Alignment.center : Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: child,
      ),
    );

    if (!scroll) {
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
        child: center
            ? Center(child: card)
            : card,
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
      child: card,
    );
  }
}

/// Compact left-aligned header — matches Home hub card tone (no duplicate page title).
class P2pCardHeader extends StatelessWidget {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const P2pCardHeader({
    super.key,
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: iconGradient,
            ),
            boxShadow: [
              BoxShadow(
                color: iconGradient.first.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppTheme.textMuted.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class P2pFeatureStrip extends StatelessWidget {
  const P2pFeatureStrip({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (LucideIcons.zap, 'Direct'),
      (LucideIcons.shieldCheck, 'Secure'),
      (LucideIcons.cloudOff, 'No upload'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: AppTheme.loginInsetDecoration(borderRadius: 12),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: Colors.white.withValues(alpha: 0.08),
              ),
            Expanded(
              child: Column(
                children: [
                  Icon(items[i].$1, size: 16, color: AppTheme.primaryBright),
                  const SizedBox(height: 4),
                  Text(
                    items[i].$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dashboard-style action row — balanced send / receive tiles.
class P2pActionTile extends StatelessWidget {
  final IconData icon;
  final List<Color> gradient;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const P2pActionTile({
    super.key,
    required this.icon,
    required this.gradient,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: AppTheme.loginInsetDecoration(borderRadius: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                        color: AppTheme.textMuted.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppTheme.textMuted.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class P2pSectionLabel extends StatelessWidget {
  final String text;

  const P2pSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppTheme.textMuted.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class P2pStatusSteps extends StatelessWidget {
  final List<({String label, bool done, bool active})> steps;
  final String statusText;
  final String? iceState;

  const P2pStatusSteps({
    super.key,
    required this.steps,
    required this.statusText,
    this.iceState,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.loginInsetDecoration(borderRadius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const P2pSectionLabel('Connection status'),
          ...steps.map((s) {
            final color = s.done
                ? AppTheme.success
                : (s.active ? AppTheme.accent : AppTheme.textMuted.withValues(alpha: 0.7));
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    s.done
                        ? Icons.check_circle_rounded
                        : (s.active ? Icons.radio_button_checked : Icons.radio_button_off),
                    size: 17,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: s.active || s.done ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                  if (s.label == 'WebRTC' && iceState != null && iceState!.isNotEmpty)
                    Text(
                      iceState!,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted.withValues(alpha: 0.85),
                      ),
                    ),
                ],
              ),
            );
          }),
          if (statusText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted.withValues(alpha: 0.92),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class P2pFilePreview extends StatelessWidget {
  final String fileName;
  final String fileSize;
  final IconData icon;
  final List<Color> gradient;

  const P2pFilePreview({
    super.key,
    required this.fileName,
    required this.fileSize,
    this.icon = LucideIcons.file,
    this.gradient = const [Color(0xFF3B82F6), Color(0xFF60A5FA)],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.loginInsetDecoration(borderRadius: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: gradient),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  fileSize,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class P2pSessionCodeBadge extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;

  const P2pSessionCodeBadge({
    super.key,
    required this.code,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: AppTheme.loginInsetDecoration(borderRadius: 12, emphasized: true),
          child: Row(
            children: [
              const Icon(LucideIcons.hash, size: 15, color: AppTheme.primaryBright),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  code,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.primary.withValues(alpha: 0.16),
                  border: Border.all(color: AppTheme.primaryBright.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.copy, size: 12, color: AppTheme.primaryBright),
                    SizedBox(width: 4),
                    Text(
                      'Copy',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryBright,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class P2pPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final List<Color> gradient;
  final bool loading;

  const P2pPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.gradient = const [Color(0xFF059669), Color(0xFF047857)],
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            border: Border.all(color: gradient.first.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class P2pGhostButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const P2pGhostButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = AppTheme.danger,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class P2pProgressPanel extends StatelessWidget {
  final double progress;
  final String fileName;
  final String statusText;
  final String? bytesLabel;
  final String? peerName;

  const P2pProgressPanel({
    super.key,
    required this.progress,
    required this.fileName,
    required this.statusText,
    this.bytesLabel,
    this.peerName,
  });

  @override
  Widget build(BuildContext context) {
    return P2pHubCard(
      child: Column(
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      progress < 1 ? 'Transferring' : 'Done',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          P2pFilePreview(
            fileName: fileName,
            fileSize: bytesLabel ?? statusText,
            icon: LucideIcons.fileUp,
          ),
          if (peerName != null) ...[
            const SizedBox(height: 8),
            Text(
              'with $peerName',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class P2pJoinField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;

  const P2pJoinField({
    super.key,
    required this.controller,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.loginInsetDecoration(borderRadius: 12, emphasized: true),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 17,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: 'Paste transfer code',
          hintStyle: TextStyle(
            color: AppTheme.textMuted.withValues(alpha: 0.55),
            letterSpacing: 0.5,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}
