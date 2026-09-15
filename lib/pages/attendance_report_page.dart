import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/report_ui.dart';
import '../widgets/tool_page_scaffold.dart';

class AttendanceReportPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;
  final DateTime? initialDate;

  const AttendanceReportPage({
    super.key,
    required this.apiService,
    this.onLogout,
    this.initialDate,
  });

  @override
  State<AttendanceReportPage> createState() => _AttendanceReportPageState();
}

class _AttendanceReportPageState extends State<AttendanceReportPage> {
  bool _loading = false;
  bool _generated = false;
  String? _error;
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
      _load();
    }
  }

  String get _dateParam => DateFormat('yyyy-MM-dd').format(_selectedDate);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _generated = false;
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
        _generated = true;
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
      showHeader: true,
      header: ReportUi.pageHeader(
        icon: LucideIcons.clock,
        title: 'Work Report',
        subtitle: 'Daily clock in, break & net work',
        accent: AppTheme.success,
      ),
      onLogout: widget.onLogout,
      useBackground: true,
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dateBar(sched),
          if (_error != null) ...[
            const SizedBox(height: 10),
            ReportUi.glossCard(
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger, decoration: TextDecoration.none)),
            ),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: AppTheme.primaryBright)),
            )
          else if (_generated && _report != null) ...[
            const SizedBox(height: 12),
            _heroSummary(summary),
            const SizedBox(height: 14),
            ReportUi.sectionLabel('Sessions', count: sessions.length),
            const SizedBox(height: 8),
            _sessionsTable(sessions),
            const SizedBox(height: 14),
            ReportUi.sectionLabel('Breaks', count: breaks.length),
            const SizedBox(height: 8),
            _breaksTable(breaks),
          ],
        ],
      ),
    );
  }

  Widget _dateBar(Map<String, dynamic>? sched) {
    return ReportUi.glossCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _loading ? null : _pickDate,
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        ReportUi.iconBox(icon: Icons.calendar_today_rounded, color: AppTheme.primaryBright, size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Work day', style: ReportUi.mutedStyle.copyWith(fontSize: 10.5)),
                              Text(
                                DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              if (sched != null && _generated)
                                Text(
                                  'Shift ${_scheduleLabel(sched)}',
                                  style: ReportUi.mutedStyle.copyWith(fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_generated)
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: AppTheme.textMuted,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _loading ? null : _load,
            style: ReportUi.primaryButton(),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'View report',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.none),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _heroSummary(Map<String, dynamic> summary) {
    final net = _dur(summary['net_work_duration']);
    final gross = _dur(summary['gross_work_duration']);
    final breakT = _dur(summary['break_duration']);

    return ReportUi.glossCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Column(
        children: [
          Text(
            net,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1,
              decoration: TextDecoration.none,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text('Net work', style: ReportUi.mutedStyle.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _miniStat('Gross', gross, AppTheme.primaryBright)),
              Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.1)),
              Expanded(child: _miniStat('Break', breakT, AppTheme.warning)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: ReportUi.mutedStyle.copyWith(fontSize: 11)),
      ],
    );
  }

  Widget _sessionsTable(List<dynamic> sessions) {
    const columns = [
      ReportTableColumn(label: '#', width: 24, flex: 1, align: TextAlign.center),
      ReportTableColumn(label: 'IN', width: 48, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'OUT', width: 48, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'TIME', width: 56, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'STAT', width: 52, flex: 2, align: TextAlign.center),
    ];

    final rows = <ReportTableRow>[];
    for (var i = 0; i < sessions.length; i++) {
      final raw = sessions[i];
      if (raw is! Map) continue;
      final s = Map<String, dynamic>.from(raw);
      final inDt = DateTime.tryParse(s['check_in']?.toString() ?? '')?.toLocal();
      final outDt = DateTime.tryParse(s['check_out']?.toString() ?? '')?.toLocal();
      final isOpen = s['is_open'] == true;
      final dur = s['gross_duration'] is Map
          ? Map<String, dynamic>.from(s['gross_duration'] as Map)['formatted']?.toString() ?? '—'
          : '—';

      rows.add(
        ReportTableRow(
          cells: [
            ReportTableCell(text: '${i + 1}', muted: true),
            ReportTableCell(
              text: inDt != null ? DateFormat('HH:mm').format(inDt) : '—',
              color: AppTheme.success,
            ),
            ReportTableCell(
              text: outDt != null
                  ? DateFormat('HH:mm').format(outDt)
                  : (isOpen ? 'Open' : '—'),
              muted: outDt == null && !isOpen,
              color: outDt != null ? AppTheme.primaryBright : (isOpen ? AppTheme.warning : null),
            ),
            ReportTableCell(text: dur, color: AppTheme.primaryBright),
            ReportTableCell(
              child: ReportUi.statusChip(
                isOpen ? 'Active' : 'Done',
                isOpen ? AppTheme.success : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return ReportUi.dataTable(
      columns: columns,
      rows: rows,
      emptyMessage: 'No clock-in sessions for this day',
    );
  }

  Widget _breaksTable(List<dynamic> breaks) {
    const columns = [
      ReportTableColumn(label: '#', width: 24, flex: 1, align: TextAlign.center),
      ReportTableColumn(label: 'START', width: 48, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'BACK', width: 48, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'TIME', width: 56, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'STAT', width: 52, flex: 2, align: TextAlign.center),
    ];

    final rows = <ReportTableRow>[];
    for (var i = 0; i < breaks.length; i++) {
      final raw = breaks[i];
      if (raw is! Map) continue;
      final b = Map<String, dynamic>.from(raw);
      final start = DateTime.tryParse(b['break_start']?.toString() ?? '')?.toLocal();
      final back = DateTime.tryParse(b['actual_back']?.toString() ?? '')?.toLocal();
      final isActive = b['is_active'] == true;
      final dur = b['duration'] is Map
          ? Map<String, dynamic>.from(b['duration'] as Map)['formatted']?.toString() ?? '—'
          : '—';

      rows.add(
        ReportTableRow(
          cells: [
            ReportTableCell(text: '${i + 1}', muted: true),
            ReportTableCell(
              text: start != null ? DateFormat('HH:mm').format(start) : '—',
              color: AppTheme.warning,
            ),
            ReportTableCell(
              text: back != null
                  ? DateFormat('HH:mm').format(back)
                  : (isActive ? 'On break' : '—'),
              muted: back == null && !isActive,
              color: back != null ? AppTheme.primaryBright : (isActive ? AppTheme.warning : null),
            ),
            ReportTableCell(text: dur, color: AppTheme.warning),
            ReportTableCell(
              child: ReportUi.statusChip(
                isActive ? 'Active' : 'Done',
                isActive ? AppTheme.warning : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return ReportUi.dataTable(
      columns: columns,
      rows: rows,
      emptyMessage: 'No breaks recorded',
    );
  }
}
