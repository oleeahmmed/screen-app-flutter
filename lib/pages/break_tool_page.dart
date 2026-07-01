import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/app_navigation.dart';
import '../services/screenshot_service.dart';
import '../theme/app_theme.dart';
import '../widgets/break_panel.dart';
import '../widgets/tool_page_scaffold.dart';

class BreakToolPage extends StatefulWidget {
  final ApiService apiService;
  final ScreenshotService? screenshotService;
  final VoidCallback? onLogout;

  const BreakToolPage({
    super.key,
    required this.apiService,
    this.screenshotService,
    this.onLogout,
  });

  @override
  State<BreakToolPage> createState() => _BreakToolPageState();
}

class _BreakToolPageState extends State<BreakToolPage> {
  bool _isClockedIn = false;
  int _refresh = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadClockState();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadClockState(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadClockState({bool silent = false}) async {
    final r = await widget.apiService.getCurrentAttendance();
    if (!mounted) return;
    final att = r['data']?['current_attendance'];
    final open = r['success'] == true && ApiService.attendanceIsOpen(att is Map ? Map<String, dynamic>.from(att) : null);
    setState(() {
      _isClockedIn = open;
      _refresh++;
    });
  }

  void _goClockIn() {
    Navigator.of(context).pop();
    AppNavigation.instance.goHome();
  }

  @override
  Widget build(BuildContext context) {
    return ToolPageScaffold(
      title: 'Take a Break',
      subtitle: 'Let your team know when you\'ll be back',
      onLogout: widget.onLogout,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isClockedIn)
            BreakPanel(
              apiService: widget.apiService,
              screenshotService: widget.screenshotService,
              isClockedIn: true,
              refreshToken: _refresh,
              onBreakChanged: (_) => setState(() => _refresh++),
            )
          else
            _clockInPrompt(),
        ],
      ),
    );
  }

  Widget _clockInPrompt() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassPanel(borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.free_breakfast_outlined, color: AppTheme.warning, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Take a Break', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Clock in first — then choose 5m, 10m, 15m or custom.',
                      style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _goClockIn,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Go to Home & Clock In'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.success.withValues(alpha: 0.18),
              foregroundColor: AppTheme.success,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppTheme.success.withValues(alpha: 0.4)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _loadClockState(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh status'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryBright,
              side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
