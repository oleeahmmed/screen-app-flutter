import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/tool_page_scaffold.dart';

class AttendanceReportPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;

  const AttendanceReportPage({
    super.key,
    required this.apiService,
    this.onLogout,
  });

  @override
  State<AttendanceReportPage> createState() => _AttendanceReportPageState();
}

class _AttendanceReportPageState extends State<AttendanceReportPage> {
  bool _loading = true;
  String? _error;
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dateParam => DateFormat('yyyy-MM-dd').format(_selectedDate);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.apiService.getMyAttendanceReport(date: _dateParam);
    if (!mounted) return;
    if (r['success'] == true) {
      final data = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : null;
      final wd = data?['working_date']?.toString();
      if (wd != null && wd.isNotEmpty) {
        final parsed = DateTime.tryParse(wd);
        if (parsed != null) _selectedDate = parsed;
      }
      setState(() {
        _report = data;
        _loading = false;
      });
    } else {
      setState(() {
        _error = r['error']?.toString() ?? 'Could not load report';
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primaryBright,
            surface: AppTheme.surface2,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _load();
  }

  String _dur(dynamic block) {
    if (block is Map) {
      final f = block['formatted']?.toString();
      if (f != null && f.isNotEmpty) return f;
    }
    return '0h 0m';
  }

  String _scheduleLabel(Map<String, dynamic>? sched) {
    if (sched == null) return '';
    final inT = sched['expected_check_in']?.toString() ?? '--:--';
    final outT = sched['expected_check_out']?.toString() ?? '--:--';
    final overnight = sched['is_overnight'] == true;
    return overnight ? '$inT → $outT (next day)' : '$inT – $outT';
  }

  @override
  Widget build(BuildContext context) {
    final summary = _report?['summary'] is Map
        ? Map<String, dynamic>.from(_report!['summary'] as Map)
        : <String, dynamic>{};
    final sched = _report?['effective_schedule'] is Map
        ? Map<String, dynamic>.from(_report!['effective_schedule'] as Map)
        : null;
    final sessions = _report?['sessions'] is List ? _report!['sessions'] as List : [];
    final breaks = _report?['breaks'] is List ? _report!['breaks'] as List : [];

    return ToolPageScaffold(
      title: 'Work Report',
      subtitle: 'Net work and break hours for your work day',
      onLogout: widget.onLogout,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(DateFormat('EEE, d MMM yyyy').format(_selectedDate)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: AppTheme.primaryBright,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
          if (sched != null) ...[
            const SizedBox(height: 10),
            Text(
              'Expected: ${_scheduleLabel(sched)}',
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: AppTheme.primaryBright)),
            )
          else if (_error != null)
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            )
          else ...[
            Row(
              children: [
                Expanded(child: _statCard('Net Work', _dur(summary['net_work_duration']), AppTheme.success)),
                const SizedBox(width: 10),
                Expanded(child: _statCard('Break', _dur(summary['break_duration']), AppTheme.warning)),
              ],
            ),
            const SizedBox(height: 10),
            _statCard('Gross Work', _dur(summary['gross_work_duration']), AppTheme.primaryBright, fullWidth: true),
            const SizedBox(height: 20),
            _sectionTitle('Sessions', sessions.length),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              _emptyNote('No clock-in sessions for this work day.')
            else
              ...sessions.map((s) => _sessionTile(s)),
            const SizedBox(height: 20),
            _sectionTitle('Breaks', breaks.length),
            const SizedBox(height: 8),
            if (breaks.isEmpty)
              _emptyNote('No breaks recorded for this work day.')
            else
              ...breaks.map((b) => _breakTile(b)),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, int count) {
    return Text(
      '$title ($count)',
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _statCard(String label, String value, Color color, {bool fullWidth = false}) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: fullWidth ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted.withValues(alpha: 0.85),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyNote(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.taskFieldDecoration(borderRadius: 10),
      child: Text(text, style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 12)),
    );
  }

  Widget _sessionTile(dynamic raw) {
    if (raw is! Map) return const SizedBox.shrink();
    final s = Map<String, dynamic>.from(raw);
    final inDt = DateTime.tryParse(s['check_in']?.toString() ?? '')?.toLocal();
    final outDt = DateTime.tryParse(s['check_out']?.toString() ?? '')?.toLocal();
    final isOpen = s['is_open'] == true;
    final dur = s['gross_duration'] is Map
        ? Map<String, dynamic>.from(s['gross_duration'] as Map)['formatted']?.toString() ?? ''
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 10,
        child: Row(
          children: [
            Icon(
              isOpen ? Icons.play_circle_outline : Icons.check_circle_outline,
              color: isOpen ? AppTheme.success : AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inDt != null ? DateFormat('HH:mm').format(inDt) : '—',
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    outDt != null
                        ? 'Out ${DateFormat('HH:mm').format(outDt)}'
                        : (isOpen ? 'Still clocked in' : '—'),
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(dur, style: const TextStyle(color: AppTheme.primaryBright, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _breakTile(dynamic raw) {
    if (raw is! Map) return const SizedBox.shrink();
    final b = Map<String, dynamic>.from(raw);
    final start = DateTime.tryParse(b['break_start']?.toString() ?? '')?.toLocal();
    final back = DateTime.tryParse(b['actual_back']?.toString() ?? '')?.toLocal();
    final isActive = b['is_active'] == true;
    final dur = b['duration'] is Map
        ? Map<String, dynamic>.from(b['duration'] as Map)['formatted']?.toString() ?? ''
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 10,
        child: Row(
          children: [
            Icon(Icons.free_breakfast_rounded, color: isActive ? AppTheme.warning : AppTheme.textMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    start != null ? DateFormat('HH:mm').format(start) : '—',
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    back != null
                        ? 'Back ${DateFormat('HH:mm').format(back)}'
                        : (isActive ? 'On break now' : '—'),
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(dur, style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
