import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/platform_capabilities.dart';
import '../widgets/app_quick_menu.dart';

/// In-app copy of the monitor web “Data & privacy” notice (keep in sync when bumping version).
class DataPrivacyNoticePage extends StatelessWidget {
  const DataPrivacyNoticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final captureScreenshots = PlatformCapabilities.screenshotMonitoring;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data & monitoring notice'),
        actions: const [
          AppHeaderMenuActions(iconColor: Colors.white70),
        ],
      ),
      body: Container(
        decoration: AppTheme.screenGradient(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Notice version 1',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Summary',
              style: TextStyle(
                color: AppTheme.primaryBright,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              captureScreenshots
                  ? 'This workplace productivity application may capture screenshots of your device screen '
                      'and related metadata (for example active window title, browser site hints, idle state, and timestamps) '
                      'while you are using the app as directed by your organization. Data is used for attendance, '
                      'activity insight, and monitoring features your employer has enabled.'
                  : 'This Android build does not capture screenshots. It is used for attendance, tasks, chat, '
                      'and related workplace workflows your organization has enabled. Account and app activity '
                      'data may still be processed as part of those features.',
              style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 20),
            const Text(
              'What may be collected',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (captureScreenshots) ...const [
              _Bullet('Periodic screen captures when capture is enabled and you have agreed.'),
              _Bullet('Technical signals such as last activity time, idle detection, and optional window/browser context.'),
            ] else ...const [
              _Bullet('This app does not request screen-capture / MediaProjection permission.'),
              _Bullet('Attendance, tasks, chat, and related workflow events you use in the app.'),
            ],
            const _Bullet('Account context: your profile, company association, and related app events.'),
            const SizedBox(height: 20),
            const Text(
              'Purpose',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              captureScreenshots
                  ? 'Data is processed to provide the service your organization subscribed to — for example live monitoring, '
                      'reports, attendance, and team workflows.'
                  : 'Data is processed for attendance, tasks, chat, and team workflows — not for screen monitoring on this device.',
              style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your choices',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              captureScreenshots
                  ? 'You can review screenshot monitoring consent in your profile and contact your company administrator '
                      'for questions.'
                  : 'Contact your company administrator for questions about how workplace data is used.',
              style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 24),
            const Text(
              'This notice is informational and does not replace your employment contract or local law.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.white54)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.45, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
