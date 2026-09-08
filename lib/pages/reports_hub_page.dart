import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/closing_report_panel.dart';
import '../widgets/report_ui.dart';
import '../widgets/tool_page_scaffold.dart';
import 'attendance_report_page.dart';
import 'monthly_attendance_report_page.dart';

class ReportsHubPage extends StatelessWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;

  const ReportsHubPage({
    super.key,
    required this.apiService,
    this.onLogout,
  });

  Future<void> _openClosingReport(BuildContext context) async {
    final reportsR = await apiService.getClosingReports();
    Map<String, dynamic>? todayReport;
    if (reportsR['success'] == true) {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      for (final item in reportsR['data'] as List? ?? []) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final d = m['report_date']?.toString();
        if (d != null && d.startsWith(todayStr)) {
          todayReport = m;
          break;
        }
      }
    }
    if (!context.mounted) return;
    await showClosingReportDialog(
      context: context,
      apiService: apiService,
      existingReport: todayReport,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ToolPageScaffold(
      title: 'Reports',
      subtitle: 'Attendance & daily updates',
      onLogout: onLogout,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReportTile(
            icon: LucideIcons.calendarRange,
            title: 'Monthly Attendance',
            subtitle: 'Full month or custom date range',
            accent: AppTheme.primaryBright,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MonthlyAttendanceReportPage(
                    apiService: apiService,
                    onLogout: onLogout,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _ReportTile(
            icon: LucideIcons.clock,
            title: 'Daily Work Report',
            subtitle: 'Clock in, breaks & net hours',
            accent: AppTheme.success,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AttendanceReportPage(
                    apiService: apiService,
                    onLogout: onLogout,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _ReportTile(
            icon: LucideIcons.clipboardCheck,
            title: 'Daily Closing Report',
            subtitle: 'What you did today — same as dashboard',
            accent: AppTheme.featureReport,
            onTap: () => _openClosingReport(context),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: ReportUi.card(radius: 16).copyWith(
            border: Border.all(color: accent.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              ReportUi.iconBox(icon: icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: ReportUi.mutedStyle.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted.withValues(alpha: 0.7), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
