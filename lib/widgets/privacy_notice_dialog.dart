import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_session.dart';
import '../config.dart';
import '../pages/data_privacy_notice_page.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Blocking dialog until the user agrees or taps Later.
Future<void> showPrivacyNoticeDialog({
  required BuildContext context,
  required ApiService apiService,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppTheme.modalBarrierColor,
    useRootNavigator: true,
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
      final d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : <String, dynamic>{};
      final av = d['data_privacy_notice_accepted_version'];
      final sv = d['data_privacy_notice_version'];
      final consent = d['screenshot_monitoring_consent'] == true;
      final prefs = await SharedPreferences.getInstance();
      final ai = av is int ? av : int.tryParse('$av') ?? AppConfig.dataPrivacyNoticeVersion;
      final si = sv is int ? sv : int.tryParse('$sv') ?? AppConfig.dataPrivacyNoticeVersion;
      await prefs.setInt('data_privacy_notice_accepted_version', ai);
      await prefs.setInt('data_privacy_notice_server_version', si);
      await prefs.setBool('screenshot_monitoring_consent', consent);
      AppSession.setConsent(consent);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notice accepted')),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r['error']?.toString() ?? 'Could not save — try again'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return Dialog(
      insetPadding: AppTheme.dialogInsets(context),
      backgroundColor: AppTheme.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppTheme.dialogMaxWidth(context, max: 520),
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(mobile ? 16 : 24, 20, mobile ? 16 : 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Data & monitoring notice',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: mobile ? 17 : 20,
                    ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'This app may collect screenshots and related activity data (window titles, idle state, timestamps) '
                        'for workplace monitoring as configured by your organization.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          height: 1.45,
                          fontSize: mobile ? 13 : 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () {
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
                      CheckboxListTile(
                        value: _consentScreenshots,
                        onChanged: _submitting ? null : (v) => setState(() => _consentScreenshots = v ?? true),
                        title: Text(
                          'I agree to screenshot / monitoring capture as allowed by my organization.',
                          style: TextStyle(
                            fontSize: narrow ? 11 : 12,
                            color: AppTheme.textPrimary.withValues(alpha: 0.85),
                          ),
                        ),
                        subtitle: Text(
                          'Change anytime in Profile.',
                          style: TextStyle(fontSize: 10, color: AppTheme.textMuted.withValues(alpha: 0.8)),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: mobile,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (mobile || narrow)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: _submitting ? null : _accept,
                      style: AppTheme.primaryButton(),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('I understand & agree'),
                    ),
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.of(context, rootNavigator: true).pop(),
                      child: const Text('Later'),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.of(context, rootNavigator: true).pop(),
                      child: const Text('Later'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitting ? null : _accept,
                      style: AppTheme.primaryButton(radius: 12),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('I understand & agree'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
