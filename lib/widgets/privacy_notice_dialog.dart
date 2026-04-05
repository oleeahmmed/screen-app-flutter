import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_session.dart';
import '../config.dart';
import '../pages/data_privacy_notice_page.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Shows a blocking dialog until the user agrees or taps Later (shown again next launch if still required).
Future<void> showPrivacyNoticeDialog({
  required BuildContext context,
  required ApiService apiService,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PrivacyNoticeDialogContent(apiService: apiService),
  );
}

class _PrivacyNoticeDialogContent extends StatefulWidget {
  final ApiService apiService;

  const _PrivacyNoticeDialogContent({required this.apiService});

  @override
  State<_PrivacyNoticeDialogContent> createState() => _PrivacyNoticeDialogContentState();
}

class _PrivacyNoticeDialogContentState extends State<_PrivacyNoticeDialogContent> {
  bool _consentScreenshots = true;
  bool _submitting = false;

  Future<void> _accept() async {
    setState(() => _submitting = true);
    final r = await widget.apiService.acceptPrivacyNotice(
      screenshotMonitoringConsent: _consentScreenshots,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (r['success'] == true) {
      final d = r['data'] as Map<String, dynamic>?;
      final av = d?['data_privacy_notice_accepted_version'];
      final sv = d?['data_privacy_notice_version'];
      final consent = d?['screenshot_monitoring_consent'] == true;
      final prefs = await SharedPreferences.getInstance();
      final ai = av is int ? av : int.tryParse('$av') ?? AppConfig.dataPrivacyNoticeVersion;
      final si = sv is int ? sv : int.tryParse('$sv') ?? AppConfig.dataPrivacyNoticeVersion;
      await prefs.setInt('data_privacy_notice_accepted_version', ai);
      await prefs.setInt('data_privacy_notice_server_version', si);
      await prefs.setBool('screenshot_monitoring_consent', consent);
      AppSession.setConsent(consent);
      if (mounted) Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not save')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1e293b),
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Data & monitoring notice',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This app may collect screenshots and related activity data (window titles, idle state, timestamps) '
              'for workplace monitoring as configured by your organization.',
              style: TextStyle(color: Colors.white.withOpacity(0.75), height: 1.45, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DataPrivacyNoticePage(),
                    ),
                  );
                },
                icon: const Icon(Icons.article_outlined, size: 18, color: AppTheme.primaryBright),
                label: const Text('Read full notice'),
              ),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _consentScreenshots,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _consentScreenshots = v ?? true),
              title: Text(
                'I agree to screenshot / monitoring capture as allowed by my organization (change anytime in profile).',
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _accept,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('I understand & agree'),
        ),
      ],
    );
  }
}
