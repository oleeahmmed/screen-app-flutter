import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/screenshot_service.dart';
import '../theme/app_theme.dart';
import '../utils/platform_capabilities.dart';

/// BRB break controls — uses `/api/breaks/` endpoints.
class BreakPanel extends StatefulWidget {
  final ApiService apiService;
  final ScreenshotService? screenshotService;
  final bool isClockedIn;
  final int refreshToken;
  /// When true, shows a hint card even if not clocked in (Home dashboard).
  final bool alwaysVisible;
  /// Home dashboard: one Break button opens duration picker sheet.
  final bool compact;
  final ValueChanged<bool>? onBreakChanged;

  const BreakPanel({
    super.key,
    required this.apiService,
    this.screenshotService,
    required this.isClockedIn,
    this.refreshToken = 0,
    this.alwaysVisible = false,
    this.compact = false,
    this.onBreakChanged,
  });

  @override
  State<BreakPanel> createState() => _BreakPanelState();
}

class _BreakPanelState extends State<BreakPanel> {
  bool _onBreak = false;
  Map<String, dynamic>? _activeBreak;
  bool _loading = true;
  bool _busy = false;
  bool _screenshotsPausedForBreak = false;
  DateTime _now = DateTime.now();
  Map<String, dynamic>? _breakSummary;

  static const _presets = [5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _tickClock();
  }

  @override
  void didUpdateWidget(covariant BreakPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.isClockedIn != widget.isClockedIn) {
      _fetchStatus();
    }
  }

  void _tickClock() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _tickClock();
    });
  }

  Future<void> _fetchStatus() async {
    if (!widget.isClockedIn) {
      final wasOnBreak = _onBreak;
      if (mounted) {
        setState(() {
          _onBreak = false;
          _activeBreak = null;
          _breakSummary = null;
          _loading = false;
        });
      }
      if (wasOnBreak) widget.onBreakChanged?.call(false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final r = await widget.apiService.getBreakStatus();
      final my = await widget.apiService.getMyBreaks();
      if (!mounted) return;
      if (r['success'] == true) {
        final data = r['data'] as Map<String, dynamic>? ?? {};
        final nextOnBreak = data['on_break'] == true;
        final wasOnBreak = _onBreak;
        setState(() {
          _onBreak = nextOnBreak;
          _activeBreak = data['break'] as Map<String, dynamic>?;
        });
        if (nextOnBreak != wasOnBreak) {
          widget.onBreakChanged?.call(nextOnBreak);
        }
        if (_onBreak && widget.screenshotService?.isRunning == true) {
          _screenshotsPausedForBreak = true;
          unawaited(widget.screenshotService?.stopCapture());
        }
      }
      if (my['success'] == true && mounted) {
        setState(() => _breakSummary = my['data'] as Map<String, dynamic>?);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  Future<void> _startBreak(int minutes) async {
    final expectedBack = DateTime.now().add(Duration(minutes: minutes));
    await _startBreakAt(expectedBack);
  }

  Future<void> _startBreakAt(DateTime expectedBack) async {
    if (_busy || !widget.isClockedIn) return;
    if (!expectedBack.isAfter(DateTime.now())) {
      _showSnack('Return time must be in the future', Colors.red);
      return;
    }
    setState(() => _busy = true);
    final r = await widget.apiService.startBreak(expectedBack);
    if (!mounted) return;
    if (r['success'] == true) {
      final data = r['data'] as Map<String, dynamic>? ?? {};
      if (widget.screenshotService?.isRunning == true) {
        _screenshotsPausedForBreak = true;
        await widget.screenshotService?.stopCapture();
      }
      setState(() {
        _onBreak = true;
        _activeBreak = data['break'] as Map<String, dynamic>?;
        _busy = false;
      });
      widget.onBreakChanged?.call(true);
      await _fetchStatus();
      _showSnack('Break started — back by ${DateFormat('HH:mm').format(expectedBack)}', Colors.amber.shade700);
    } else {
      setState(() => _busy = false);
      _showSnack(r['error']?.toString() ?? 'Could not start break', Colors.red);
    }
  }

  Future<void> _showCustomBreakDialog() async {
    final minutesCtrl = TextEditingController(text: '15');
    final picked = await showDialog<DateTime?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text('Custom break', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minutesCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Minutes from now',
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final now = TimeOfDay.now();
                final time = await showTimePicker(
                  context: ctx,
                  initialTime: TimeOfDay(hour: now.hour, minute: (now.minute + 15) % 60),
                );
                if (time == null) return;
                final dt = DateTime.now();
                var back = DateTime(dt.year, dt.month, dt.day, time.hour, time.minute);
                if (!back.isAfter(DateTime.now())) back = back.add(const Duration(days: 1));
                if (ctx.mounted) Navigator.pop(ctx, back);
              },
              icon: const Icon(Icons.schedule, color: Colors.white70),
              label: const Text('Pick return time', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final m = int.tryParse(minutesCtrl.text.trim());
              if (m == null || m < 1) return;
              Navigator.pop(ctx, DateTime.now().add(Duration(minutes: m)));
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
    minutesCtrl.dispose();
    if (picked != null) await _startBreakAt(picked);
  }

  Future<void> _endBreak() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await widget.apiService.endBreak();
    if (!mounted) return;
    if (r['success'] == true) {
      if (_screenshotsPausedForBreak && widget.isClockedIn) {
        _screenshotsPausedForBreak = false;
        unawaited(widget.screenshotService?.startCapture());
      }
      setState(() {
        _onBreak = false;
        _activeBreak = null;
        _busy = false;
      });
      widget.onBreakChanged?.call(false);
      await _fetchStatus();
      _showSnack('Welcome back!', const Color(0xFF22C55E));
    } else {
      setState(() => _busy = false);
      _showSnack(r['error']?.toString() ?? 'Could not end break', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  String _remainingLabel() {
    final back = _parseDt(_activeBreak?['expected_back']);
    if (back == null) return '';
    final diff = back.difference(_now);
    if (diff.isNegative) {
      final over = diff.abs();
      return 'Over by ${over.inMinutes}m ${over.inSeconds.remainder(60)}s';
    }
    return 'Back in ${diff.inMinutes}m ${diff.inSeconds.remainder(60)}s';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isClockedIn) {
      if (!widget.alwaysVisible) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(onBreak: false),
        child: Row(
          children: [
            Icon(Icons.free_breakfast_outlined, color: AppTheme.textMuted.withValues(alpha: 0.45), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Take a Break',
                    style: TextStyle(
                      color: AppTheme.textMuted.withValues(alpha: 0.75),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Clock in first — then choose 5m, 10m, 15m or custom.',
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.55), fontSize: 11),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textMuted.withValues(alpha: 0.45),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Break', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(onBreak: false),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
        ),
      );
    }

    if (_onBreak && _activeBreak != null) {
      final started = _parseDt(_activeBreak!['break_start']);
      final expected = _parseDt(_activeBreak!['expected_back']);
      final isOverdue = expected != null && expected.isBefore(_now);

      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(onBreak: true, overdue: isOverdue),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.coffee_rounded, color: isOverdue ? AppTheme.danger : AppTheme.warning, size: 20),
                const SizedBox(width: 8),
                Text(
                  'On Break',
                  style: TextStyle(
                    color: isOverdue ? AppTheme.danger : AppTheme.warning,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isOverdue ? AppTheme.danger : AppTheme.warning).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _remainingLabel(),
                    style: TextStyle(
                      color: isOverdue ? AppTheme.danger : AppTheme.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            if (started != null || expected != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (started != null) 'Started ${DateFormat('HH:mm').format(started)}',
                  if (expected != null) 'Expected ${DateFormat('HH:mm').format(expected)}',
                ].join(' · '),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _endBreak,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.login_rounded, size: 18),
                label: const Text("I'm Back", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(onBreak: false),
      child: widget.compact ? _compactIdleCard() : _inlineIdleCard(),
    );
  }

  Widget _compactIdleCard() {
    return Row(
      children: [
        const Icon(Icons.free_breakfast_outlined, color: AppTheme.primaryBright, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Take a Break',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Let your team know when you\'ll be back.',
                style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 11),
              ),
              if (_breakSummary?['summary'] is Map) ...[
                const SizedBox(height: 4),
                Text(
                  'Today: ${_breakSummary!['summary']['total_breaks'] ?? 0} breaks · '
                  '${_breakSummary!['summary']['total_break_minutes'] ?? 0}m total',
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.65), fontSize: 10),
                ),
              ],
            ],
          ),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () => showBreakStartSheet(
                    context: context,
                    apiService: widget.apiService,
                    screenshotService: widget.screenshotService,
                    onStarted: () {
                      widget.onBreakChanged?.call(true);
                      _fetchStatus();
                    },
                  ),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.warning.withValues(alpha: 0.22),
            foregroundColor: AppTheme.warning,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.45)),
            ),
            elevation: 0,
          ),
          child: const Text('Break', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _inlineIdleCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.free_breakfast_outlined, color: Colors.white70, size: 18),
            SizedBox(width: 8),
            Text('Take a Break', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Let your team know when you\'ll be back.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._presets.map((m) => _presetChip('${m}m', () => _startBreak(m))),
            _presetChip('Custom', _showCustomBreakDialog, icon: Icons.tune_rounded),
          ],
        ),
        if (_breakSummary?['summary'] is Map) ...[
          const SizedBox(height: 10),
          Text(
            'Today: ${_breakSummary!['summary']['total_breaks'] ?? 0} breaks · '
            '${_breakSummary!['summary']['total_break_minutes'] ?? 0}m total',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ],
    );
  }

  BoxDecoration _cardDecoration({required bool onBreak, bool overdue = false}) {
    final accent = onBreak ? (overdue ? AppTheme.danger : AppTheme.warning) : AppTheme.textMuted;
    return AppTheme.glassPanel(borderRadius: 16).copyWith(
      border: Border.all(color: accent.withValues(alpha: onBreak ? 0.4 : 0.1)),
    );
  }

  Widget _presetChip(String label, VoidCallback onTap, {IconData? icon}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withValues(alpha: 0.22),
                AppTheme.primaryBright.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: AppTheme.primaryBright),
                  const SizedBox(width: 4),
                ],
                Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal break picker — same presets as [BreakPanel].
Future<void> showBreakStartSheet({
  required BuildContext context,
  required ApiService apiService,
  ScreenshotService? screenshotService,
  VoidCallback? onStarted,
}) async {
  const presets = [5, 10, 15, 30, 60];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppTheme.modalBarrierColor,
    builder: (ctx) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.surface2.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.free_breakfast_outlined, color: AppTheme.warning, size: 22),
                    SizedBox(width: 10),
                    Text('Take a break', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  PlatformCapabilities.screenshotMonitoring
                      ? 'Choose when you\'ll be back. Screenshots pause while on break.'
                      : 'Choose when you\'ll be back.',
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ...presets.map((m) {
                      return ActionChip(
                        label: Text('${m}m'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final expected = DateTime.now().add(Duration(minutes: m));
                          final r = await apiService.startBreak(expected);
                          if (!context.mounted) return;
                          if (r['success'] == true) {
                            if (screenshotService?.isRunning == true) {
                              await screenshotService?.stopCapture();
                            }
                            onStarted?.call();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Break started — back by ${DateFormat('HH:mm').format(expected)}'),
                                backgroundColor: AppTheme.warning,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(r['error']?.toString() ?? 'Could not start break')),
                            );
                          }
                        },
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                        labelStyle: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                      );
                    }),
                    ActionChip(
                      label: const Text('Custom'),
                      avatar: const Icon(Icons.tune, size: 16, color: AppTheme.primaryBright),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final minutesCtrl = TextEditingController(text: '15');
                        final picked = await showDialog<DateTime?>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            backgroundColor: AppTheme.surface2,
                            title: const Text('Custom break', style: TextStyle(color: AppTheme.textPrimary)),
                            content: TextField(
                              controller: minutesCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: const InputDecoration(labelText: 'Minutes from now'),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                              FilledButton(
                                onPressed: () {
                                  final m = int.tryParse(minutesCtrl.text.trim());
                                  if (m == null || m < 1) return;
                                  Navigator.pop(dctx, DateTime.now().add(Duration(minutes: m)));
                                },
                                child: const Text('Start'),
                              ),
                            ],
                          ),
                        );
                        minutesCtrl.dispose();
                        if (picked == null || !context.mounted) return;
                        final r = await apiService.startBreak(picked);
                        if (!context.mounted) return;
                        if (r['success'] == true) {
                          if (screenshotService?.isRunning == true) {
                            await screenshotService?.stopCapture();
                          }
                          onStarted?.call();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Break started — back by ${DateFormat('HH:mm').format(picked)}')),
                          );
                        }
                      },
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                      labelStyle: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
