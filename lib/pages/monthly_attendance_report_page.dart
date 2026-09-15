import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/attendance_report_export.dart';
import '../widgets/report_ui.dart';
import '../widgets/tool_page_scaffold.dart';
import 'attendance_report_page.dart';

enum _ReportTarget { myself, allStaff, employee }

const _weekdayOptions = <(int, String)>[
  (0, 'Mon'),
  (1, 'Tue'),
  (2, 'Wed'),
  (3, 'Thu'),
  (4, 'Fri'),
  (5, 'Sat'),
  (6, 'Sun'),
];

class MonthlyAttendanceReportPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;

  const MonthlyAttendanceReportPage({
    super.key,
    required this.apiService,
    this.onLogout,
  });

  @override
  State<MonthlyAttendanceReportPage> createState() => _MonthlyAttendanceReportPageState();
}

class _MonthlyAttendanceReportPageState extends State<MonthlyAttendanceReportPage> {
  late DateTime _dateFrom;
  late DateTime _dateTo;
  final Set<int> _weeklyOff = {5};
  bool _loading = false;
  bool _exporting = false;
  bool _generated = false;
  bool _isAdmin = false;
  bool _loadingEmployees = false;
  String? _error;
  Map<String, dynamic>? _report;
  _ReportTarget _target = _ReportTarget.myself;
  int? _selectedUserId;
  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateFrom = DateTime(now.year, now.month, 1);
    _dateTo = DateTime(now.year, now.month + 1, 0);
    _loadAdminContext();
  }

  Future<void> _loadAdminContext() async {
    final admin = await UserDataService.isCompanyAdmin();
    if (!mounted) return;
    setState(() => _isAdmin = admin);
    if (!admin) return;
    setState(() => _loadingEmployees = true);
    final r = await widget.apiService.getCompanyEmployees();
    if (!mounted) return;
    final list = <Map<String, dynamic>>[];
    if (r['success'] == true) {
      for (final item in r['data'] as List? ?? const []) {
        if (item is Map) list.add(Map<String, dynamic>.from(item));
      }
      list.sort((a, b) => (a['full_name'] ?? a['username'] ?? '').toString().compareTo((b['full_name'] ?? b['username'] ?? '').toString()));
    }
    setState(() {
      _employees = list;
      _loadingEmployees = false;
    });
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String _dur(dynamic block) {
    if (block is Map) {
      final f = block['formatted']?.toString();
      if (f != null && f.isNotEmpty) return f;
    }
    return '—';
  }

  String _timeOnly(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
        if (_dateTo.isBefore(_dateFrom)) _dateTo = _dateFrom;
      } else {
        _dateTo = picked;
        if (_dateFrom.isAfter(_dateTo)) _dateFrom = _dateTo;
      }
    });
  }

  void _setMonthPreset(int year, int month) {
    setState(() {
      _dateFrom = DateTime(year, month, 1);
      _dateTo = DateTime(year, month + 1, 0);
    });
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _generated = false;
    });
    final r = await widget.apiService.getMonthlyAttendanceReport(
      dateFrom: _fmtDate(_dateFrom),
      dateTo: _fmtDate(_dateTo),
      weeklyOffDays: _weeklyOff.toList()..sort(),
      companySummary: _isAdmin && _target == _ReportTarget.allStaff,
      userId: _isAdmin && _target == _ReportTarget.employee ? _selectedUserId : null,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _report = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : null;
        _loading = false;
        _generated = true;
      });
    } else {
      setState(() {
        _error = r['error']?.toString() ?? 'Could not generate report';
        _loading = false;
      });
    }
  }

  Future<void> _exportReport() async {
    if (_report == null) return;
    setState(() => _exporting = true);
    try {
      await AttendanceReportExport.exportMonthlyReport(_report!);
      if (mounted) {
        AppToast.show(context, message: 'Report ready — save or share from the menu', type: AppToastType.success);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, message: 'Export failed: $e', type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  bool get _isCompanySummary => _report?['scope']?.toString() == 'company';

  String? get _selectedEmployeeName {
    if (_selectedUserId == null) return null;
    for (final e in _employees) {
      if (e['user_id'] == _selectedUserId) {
        return (e['full_name'] ?? e['username'] ?? 'Employee').toString();
      }
    }
    return null;
  }

  Future<void> _pickEmployee() async {
    if (_employees.isEmpty) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.dialogBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setLocal) {
            final filtered = _employees.where((e) {
              final name = '${e['full_name']} ${e['username']}'.toLowerCase();
              return query.isEmpty || name.contains(query.toLowerCase());
            }).toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Select employee', style: ReportUi.titleStyle),
                    const SizedBox(height: 10),
                    TextField(
                      onChanged: (v) => setLocal(() => query = v),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search by name…',
                        hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7)),
                        prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 18),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final e = filtered[i];
                          final uid = e['user_id'] as int?;
                          final name = (e['full_name'] ?? e['username'] ?? 'Employee').toString();
                          return ListTile(
                            dense: true,
                            title: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                            subtitle: e['designation']?.toString().isNotEmpty == true
                                ? Text(e['designation'].toString(), style: ReportUi.mutedStyle.copyWith(fontSize: 11))
                                : null,
                            onTap: uid == null ? null : () => Navigator.pop(context, uid),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _target = _ReportTarget.employee;
      _selectedUserId = picked;
    });
  }

  void _openDayDetail(String dateStr) {
    if (_isCompanySummary) return;
    if (_isAdmin && _target == _ReportTarget.employee && _selectedUserId != null) return;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AttendanceReportPage(
          apiService: widget.apiService,
          onLogout: widget.onLogout,
          initialDate: parsed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCompany = _isCompanySummary;
    final summary = !isCompany && _report?['summary'] is Map
        ? Map<String, dynamic>.from(_report!['summary'] as Map)
        : null;
    final companyTotals = isCompany && _report?['totals'] is Map
        ? Map<String, dynamic>.from(_report!['totals'] as Map)
        : null;
    final sched = !isCompany && _report?['schedule'] is Map
        ? Map<String, dynamic>.from(_report!['schedule'] as Map)
        : null;
    final days = !isCompany && _report?['days'] is List ? _report!['days'] as List : const [];
    final staffRows = isCompany && _report?['employees'] is List ? _report!['employees'] as List : const [];
    final employeeName = _report?['employee'] is Map
        ? (_report!['employee'] as Map)['full_name']?.toString()
        : _selectedEmployeeName;

    return ToolPageScaffold(
      showHeader: true,
      header: ReportUi.pageHeader(
        icon: LucideIcons.calendarRange,
        title: 'Monthly Attendance',
        subtitle: _isAdmin ? 'Generate staff summary or export CSV' : 'Pick dates, weekly off & generate',
        accent: AppTheme.primaryBright,
      ),
      onLogout: widget.onLogout,
      useBackground: true,
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filtersCard(now),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _errorBox(_error!),
          ],
          if (_generated && _report != null) ...[
            const SizedBox(height: 14),
            if (employeeName != null && employeeName.isNotEmpty)
              _infoChip('Employee: $employeeName'),
            if (isCompany)
              _infoChip('All staff summary · ${companyTotals?['employee_count'] ?? staffRows.length} employees'),
            if (sched != null) ...[
              const SizedBox(height: 8),
              _shiftChip(sched),
            ],
            const SizedBox(height: 10),
            if (isCompany && companyTotals != null)
              _summaryGrid(companyTotals)
            else if (summary != null)
              _summaryGrid(summary),
            const SizedBox(height: 14),
            _sectionHeader(
              title: isCompany ? 'Staff summary' : 'Daily breakdown',
              count: isCompany ? staffRows.length : days.length,
              onExport: _exportReport,
              exporting: _exporting,
            ),
            const SizedBox(height: 8),
            if (isCompany)
              _companySummaryTable(staffRows)
            else
              _daysTable(days),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required int count,
    required VoidCallback onExport,
    required bool exporting,
  }) {
    return Row(
      children: [
        Expanded(child: ReportUi.sectionLabel(title, count: count)),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: exporting ? null : onExport,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryBright.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (exporting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBright),
                    )
                  else
                    const Icon(Icons.ios_share_rounded, size: 14, color: AppTheme.primaryBright),
                  const SizedBox(width: 4),
                  const Text(
                    'Export CSV',
                    style: TextStyle(
                      color: AppTheme.primaryBright,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ReportUi.inset(radius: 10),
      child: Text(text, style: ReportUi.mutedStyle.copyWith(fontSize: 11.5, color: AppTheme.textPrimary)),
    );
  }

  Widget _filtersCard(DateTime now) {
    return ReportUi.glossCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReportUi.iconBox(icon: LucideIcons.slidersHorizontal, color: AppTheme.primaryBright, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Generate report', style: ReportUi.titleStyle),
                    Text(
                      '${DateFormat('d MMM').format(_dateFrom)} – ${DateFormat('d MMM yyyy').format(_dateTo)}',
                      style: ReportUi.mutedStyle.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Date range', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _dateTile('From', _dateFrom, () => _pickDate(isFrom: true))),
              const SizedBox(width: 8),
              Expanded(child: _dateTile('To', _dateTo, () => _pickDate(isFrom: false))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _presetPill('This month', () => _setMonthPreset(now.year, now.month))),
              const SizedBox(width: 8),
              Expanded(
                child: _presetPill(
                  'Last month',
                  () => now.month > 1
                      ? _setMonthPreset(now.year, now.month - 1)
                      : _setMonthPreset(now.year - 1, 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Weekly off', style: ReportUi.titleStyle),
          const SizedBox(height: 4),
          Text('Default Saturday', style: ReportUi.mutedStyle.copyWith(fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in _weekdayOptions)
                _dayPill(
                  w.$2,
                  selected: _weeklyOff.contains(w.$1),
                  onTap: () {
                    setState(() {
                      if (_weeklyOff.contains(w.$1)) {
                        if (_weeklyOff.length > 1) _weeklyOff.remove(w.$1);
                      } else {
                        _weeklyOff.add(w.$1);
                      }
                    });
                  },
                ),
              _dayPill('Sat+Sun', selected: _weeklyOff.containsAll({5, 6}), onTap: () => setState(() => _weeklyOff.addAll({5, 6}))),
            ],
          ),
          if (_isAdmin) ...[
            const SizedBox(height: 14),
            const Text('Report for', style: ReportUi.titleStyle),
            const SizedBox(height: 8),
            _adminTargetPicker(),
            if (_target == _ReportTarget.employee) ...[
              const SizedBox(height: 8),
              _employeePickTile(),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_loading || (_target == _ReportTarget.employee && _selectedUserId == null)) ? null : _generate,
            style: ReportUi.primaryButton(),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Generate report',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.none),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _adminTargetPicker() {
    return Row(
      children: [
        Expanded(child: _targetPill('Me', _ReportTarget.myself)),
        const SizedBox(width: 6),
        Expanded(child: _targetPill('All staff', _ReportTarget.allStaff)),
        const SizedBox(width: 6),
        Expanded(child: _targetPill('Employee', _ReportTarget.employee)),
      ],
    );
  }

  Widget _targetPill(String label, _ReportTarget target) {
    final active = _target == target;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          _target = target;
          if (target != _ReportTarget.employee) _selectedUserId = null;
        }),
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? AppTheme.primaryBright.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? AppTheme.textPrimary : AppTheme.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _employeePickTile() {
    final name = _selectedEmployeeName ?? (_loadingEmployees ? 'Loading…' : 'Tap to choose employee');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _loadingEmployees ? null : _pickEmployee,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: ReportUi.inset(radius: 12),
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: AppTheme.primaryBright, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: ReportUi.inset(radius: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ReportUi.mutedStyle.copyWith(fontSize: 10.5)),
              const SizedBox(height: 2),
              Text(
                DateFormat('d MMM yyyy').format(date),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetPill(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: ReportUi.inset(radius: 10),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayPill(String label, {required bool selected, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.primaryBright.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.textPrimary : AppTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ReportUi.card(radius: 12).copyWith(
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.35)),
      ),
      child: Text(message, style: const TextStyle(color: AppTheme.danger, decoration: TextDecoration.none)),
    );
  }

  Widget _shiftChip(Map<String, dynamic> sched) {
    final text = 'Shift ${sched['expected_check_in']} → ${sched['expected_check_out']}'
        '${sched['is_overnight'] == true ? ' (next day)' : ''} · ${sched['timezone'] ?? 'UTC'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ReportUi.inset(radius: 10),
      child: Text(text, style: ReportUi.mutedStyle.copyWith(fontSize: 11)),
    );
  }

  Widget _summaryGrid(Map<String, dynamic> summary) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _statTile('Present', '${summary['present_days'] ?? 0}', AppTheme.success)),
            const SizedBox(width: 8),
            Expanded(child: _statTile('Absent', '${summary['absent_days'] ?? 0}', AppTheme.danger)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _statTile('Leave', '${summary['leave_days'] ?? 0}', AppTheme.warning)),
            const SizedBox(width: 8),
            Expanded(child: _statTile('Late', '${summary['late_days'] ?? 0}', const Color(0xFFF59E0B))),
          ],
        ),
        const SizedBox(height: 8),
        _statTile('Total net work', _dur(summary['total_net_duration']), AppTheme.primaryBright, wide: true),
      ],
    );
  }

  Widget _statTile(String label, String value, Color color, {bool wide = false}) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: ReportUi.card(radius: 14),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 26,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ReportUi.mutedStyle.copyWith(fontSize: 11)),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _companySummaryTable(List<dynamic> staffRows) {
    const columns = [
      ReportTableColumn(label: 'EMPLOYEE', width: 110, flex: 4),
      ReportTableColumn(label: 'PRS', width: 36, flex: 1, align: TextAlign.center),
      ReportTableColumn(label: 'ABS', width: 36, flex: 1, align: TextAlign.center),
      ReportTableColumn(label: 'LV', width: 32, flex: 1, align: TextAlign.center),
      ReportTableColumn(label: 'LT', width: 32, flex: 1, align: TextAlign.center),
      ReportTableColumn(label: 'NET', width: 54, flex: 2, align: TextAlign.center),
    ];

    final rows = <ReportTableRow>[];
    for (final raw in staffRows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final emp = row['employee'] is Map ? Map<String, dynamic>.from(row['employee'] as Map) : <String, dynamic>{};
      final summary = row['summary'] is Map ? Map<String, dynamic>.from(row['summary'] as Map) : <String, dynamic>{};
      final uid = emp['user_id'] as int?;
      rows.add(
        ReportTableRow(
          onTap: uid == null
              ? null
              : () {
                  setState(() {
                    _target = _ReportTarget.employee;
                    _selectedUserId = uid;
                  });
                  _generate();
                },
          cells: [
            ReportTableCell(
              child: Text(
                (emp['full_name'] ?? 'Employee').toString(),
                maxLines: 2,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            ReportTableCell(text: '${summary['present_days'] ?? 0}'),
            ReportTableCell(text: '${summary['absent_days'] ?? 0}', color: AppTheme.danger),
            ReportTableCell(text: '${summary['leave_days'] ?? 0}', color: AppTheme.warning),
            ReportTableCell(text: '${summary['late_days'] ?? 0}', color: const Color(0xFFF59E0B)),
            ReportTableCell(text: _dur(summary['total_net_duration']), color: AppTheme.primaryBright),
          ],
        ),
      );
    }

    return ReportUi.dataTable(
      columns: columns,
      rows: rows,
      emptyMessage: 'No employees found',
    );
  }

  Widget _daysTable(List<dynamic> days) {
    const columns = [
      ReportTableColumn(label: 'DATE', width: 68, flex: 3),
      ReportTableColumn(label: 'IN', width: 40, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'OUT', width: 40, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'BRK', width: 46, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'NET', width: 46, flex: 2, align: TextAlign.center),
      ReportTableColumn(label: 'STATUS', width: 58, flex: 2, align: TextAlign.center),
    ];

    final rows = <ReportTableRow>[];
    for (final raw in days) {
      if (raw is! Map) continue;
      final d = Map<String, dynamic>.from(raw);
      final dateStr = d['date']?.toString() ?? '';
      final parsed = DateTime.tryParse(dateStr);
      final status = d['status']?.toString() ?? '';
      final dateLabel = parsed != null ? DateFormat('d MMM').format(parsed) : dateStr;
      final weekday = parsed != null ? DateFormat('EEE').format(parsed) : '';
      final tappable = status == 'present' || status == 'absent';
      final showTimes = status == 'present' || status == 'absent';

      rows.add(
        ReportTableRow(
          onTap: tappable ? () => _openDayDetail(dateStr) : null,
          cells: [
            ReportTableCell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (weekday.isNotEmpty)
                    Text(
                      weekday,
                      style: ReportUi.mutedStyle.copyWith(fontSize: 9.5),
                    ),
                ],
              ),
            ),
            ReportTableCell(
              text: showTimes ? _timeOnly(d['first_check_in']?.toString()) : '—',
              muted: !showTimes,
            ),
            ReportTableCell(
              text: showTimes ? _timeOnly(d['last_check_out']?.toString()) : '—',
              muted: !showTimes,
            ),
            ReportTableCell(
              text: showTimes ? _dur(d['break_duration']) : '—',
              muted: !showTimes,
            ),
            ReportTableCell(
              text: showTimes ? _dur(d['net_duration']) : '—',
              color: showTimes ? AppTheme.primaryBright : null,
              muted: !showTimes,
            ),
            ReportTableCell(child: _statusBadge(status, d['holiday_name']?.toString(), late: d['late'] == true)),
          ],
        ),
      );
    }

    return ReportUi.dataTable(
      columns: columns,
      rows: rows,
      emptyMessage: 'No days in this range',
    );
  }

  Widget _statusBadge(String status, String? holidayName, {bool late = false}) {
    Color color;
    String text;
    switch (status) {
      case 'present':
        color = late ? const Color(0xFFF59E0B) : AppTheme.success;
        text = late ? 'Late' : 'OK';
        break;
      case 'absent':
        color = AppTheme.danger;
        text = 'Absent';
        break;
      case 'weekly_off':
        color = AppTheme.textMuted;
        text = 'Off';
        break;
      case 'holiday':
        color = AppTheme.primaryBright;
        text = _shortHoliday(holidayName);
        break;
      case 'leave':
        color = AppTheme.warning;
        text = 'Leave';
        break;
      case 'future':
        color = AppTheme.textMuted;
        text = '—';
        break;
      default:
        color = AppTheme.textMuted;
        text = status;
    }
    return ReportUi.statusChip(text, color, compact: true);
  }

  String _shortHoliday(String? name) {
    if (name == null || name.isEmpty) return 'Hol';
    if (name.length <= 8) return name;
    return '${name.substring(0, 7)}…';
  }
}
