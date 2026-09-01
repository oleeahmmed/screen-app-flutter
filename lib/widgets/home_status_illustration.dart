import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';
import 'animated_glow_border.dart';

/// Working / break illustration with work day + shift badges on the left, image on the right.
class HomeStatusIllustration extends StatelessWidget {
  final bool isClockedIn;
  final bool onBreak;
  final String workDayLabel;
  final String shiftInfo;

  const HomeStatusIllustration({
    super.key,
    required this.isClockedIn,
    required this.onBreak,
    required this.workDayLabel,
    required this.shiftInfo,
  });

  @override
  Widget build(BuildContext context) {
    final isBreak = isClockedIn && onBreak;
    final color = !isClockedIn
        ? AppTheme.primaryBright
        : (isBreak ? AppTheme.warning : AppTheme.success);
    final title = !isClockedIn
        ? 'Ready'
        : (isBreak ? 'On Break' : 'Working');
    final subtitle = !isClockedIn
        ? 'Clock in to start your work day'
        : (isBreak
            ? 'Take your time — end break when you are ready'
            : 'You are clocked in and your work timer is running');
    final asset = isBreak
        ? 'assets/status/status_break.png'
        : 'assets/status/status_working.png';

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: AnimatedStatusFrame(
        active: true,
        color: color,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MetaBadge(
                      icon: LucideIcons.calendarDays,
                      label: workDayLabel,
                      accent: AppTheme.primaryBright,
                    ),
                    const SizedBox(height: 8),
                    _MetaBadge(
                      icon: LucideIcons.clock3,
                      label: shiftInfo,
                      accent: AppTheme.accent,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        asset,
                        height: 130,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 130,
                          alignment: Alignment.center,
                          child: Icon(
                            isBreak ? Icons.weekend_rounded : Icons.work_rounded,
                            size: 56,
                            color: color.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.92),
                        fontSize: 10,
                        height: 1.35,
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

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _MetaBadge({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            AppTheme.surface2.withValues(alpha: 0.35),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
