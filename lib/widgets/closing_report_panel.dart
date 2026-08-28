import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/responsive.dart';
import 'app_bottom_sheet.dart';
import 'empty_state.dart';
import 'glass_card.dart';

/// Daily closing report — `/api/closing-reports/`.
class ClosingReportPanel extends StatefulWidget {
  final ApiService apiService;
  final int refreshToken;
  final VoidCallback? onSubmitted;

  const ClosingReportPanel({
    super.key,
    required this.apiService,
    this.refreshToken = 0,
    this.onSubmitted,
  });

  @override
  State<ClosingReportPanel> createState() => _ClosingReportPanelState();
}

class _ClosingReportPanelState extends State<ClosingReportPanel> {
  bool _loading = true;
  bool _pending = false;
  bool _submittedToday = false;
  Map<String, dynamic>? _todayReport;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant ClosingReportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final pendingR = await widget.apiService.getClosingReportPending();
    final reportsR = await widget.apiService.getClosingReports();
    if (!mounted) return;

    var pending = false;
    if (pendingR['success'] == true) {
      pending = pendingR['data']?['pending'] == true;
    }

    Map<String, dynamic>? today;
    var submitted = false;
    if (reportsR['success'] == true) {
      final list = reportsR['data'] as List? ?? [];
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final d = m['report_date']?.toString();
        if (d == null) continue;
        if (d.startsWith(todayStr)) {
          today = m;
          submitted = true;
          break;
        }
      }
    }

    setState(() {
      _pending = pending;
      _submittedToday = submitted;
      _todayReport = today;
      _loading = false;
    });
  }

  Future<void> _openSubmitDialog() async {
    final ok = await showClosingReportDialog(
      context: context,
      apiService: widget.apiService,
      required: _pending && !_submittedToday,
      existingReport: _todayReport,
    );
    if (ok == true) {
      widget.onSubmitted?.call();
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(accent: Colors.white54),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
        ),
      );
    }

    if (_submittedToday && _todayReport != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(accent: AppTheme.success),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Daily report submitted',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _showHistory,
                  child: const Text('History', style: TextStyle(fontSize: 11, color: AppTheme.primaryBright)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _todayReport!['what_i_did']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 11),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openSubmitDialog,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Update report'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openSubmitDialog,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: AppTheme.taskCardDecoration(borderRadius: 16).copyWith(
            border: Border.all(
              color: (_pending ? AppTheme.warning : AppTheme.primaryBright).withValues(alpha: _pending ? 0.35 : 0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (_pending ? AppTheme.warning : AppTheme.primary).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _pending ? Icons.notification_important_outlined : Icons.assignment_outlined,
                  color: _pending ? AppTheme.warning : AppTheme.primaryBright,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pending ? 'Daily report due' : 'Daily closing report',
                      style: TextStyle(
                        color: _pending ? AppTheme.warning : AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _pending
                          ? 'Submit before you leave today.'
                          : 'Share what you accomplished and plan for tomorrow.',
                      style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 11),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _openSubmitDialog,
                style: FilledButton.styleFrom(
                  backgroundColor: _pending ? AppTheme.warning : AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text('Submit', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              ),
              IconButton(
                tooltip: 'Report history',
                onPressed: _showHistory,
                icon: Icon(Icons.history_rounded, color: AppTheme.textMuted.withValues(alpha: 0.85), size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHistory() async {
    final r = await widget.apiService.getClosingReports();
    if (!mounted) return;
    final list = r['success'] == true ? (r['data'] as List? ?? []) : <dynamic>[];
    await AppBottomSheet.show<void>(
      context: context,
      title: 'Daily report history',
      child: list.isEmpty
          ? const EmptyState(
              icon: Icons.assignment_outlined,
              title: 'No reports yet',
              subtitle: 'Submitted daily reports will appear here.',
              iconColor: AppTheme.featureReport,
            )
          : Column(
              children: [
                for (final item in list) ...[
                  Builder(
                    builder: (_) {
                      final m = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
                      final date = m['report_date']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          padding: const EdgeInsets.all(12),
                          borderRadius: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(date, style: const TextStyle(color: AppTheme.primaryBright, fontWeight: FontWeight.w600, fontSize: 12)),
                              const SizedBox(height: 6),
                              Text('Done: ${m['what_i_did'] ?? ''}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text('Next: ${m['what_i_will_do'] ?? ''}', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                              if ((m['blockers']?.toString() ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('Blockers: ${m['blockers']}', style: const TextStyle(color: AppTheme.warning, fontSize: 11)),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
    );
  }

  BoxDecoration _cardDecoration({required Color accent, bool highlight = false}) {
    return AppTheme.taskCardDecoration(borderRadius: 16).copyWith(
      border: Border.all(color: accent.withValues(alpha: highlight ? 0.45 : 0.15)),
    );
  }
}

/// Closing report sheet — slides up from the bottom like Take Break.
/// Returns `true` when the report was submitted successfully.
Future<bool?> showClosingReportDialog({
  required BuildContext context,
  required ApiService apiService,
  bool required = false,
  Map<String, dynamic>? existingReport,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: !required,
    enableDrag: !required,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppTheme.modalBarrierColor,
    builder: (ctx) => _ClosingReportSheet(
      apiService: apiService,
      required: required,
      existingReport: existingReport,
    ),
  );
}

class _ClosingReportSheet extends StatefulWidget {
  final ApiService apiService;
  final bool required;
  final Map<String, dynamic>? existingReport;

  const _ClosingReportSheet({
    required this.apiService,
    required this.required,
    this.existingReport,
  });

  @override
  State<_ClosingReportSheet> createState() => _ClosingReportSheetState();
}

class _ClosingReportSheetState extends State<_ClosingReportSheet> {
  final _whatIDid = TextEditingController();
  final _whatIWillDo = TextEditingController();
  final _blockers = TextEditingController();
  final Set<int> _dependencyIds = {};
  List<Map<String, dynamic>> _employees = [];
  bool _loadingEmployees = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingReport;
    if (existing != null) {
      _whatIDid.text = existing['what_i_did']?.toString() ?? '';
      _whatIWillDo.text = existing['what_i_will_do']?.toString() ?? '';
      _blockers.text = existing['blockers']?.toString() ?? '';
      final deps = existing['dependencies'];
      if (deps is List) {
        for (final d in deps) {
          if (d is! Map) continue;
          final id = d['id'] ?? d['employee_id'];
          if (id is int) {
            _dependencyIds.add(id);
          } else {
            final parsed = int.tryParse('$id');
            if (parsed != null) _dependencyIds.add(parsed);
          }
        }
      }
    }
    _loadEmployees();
  }

  @override
  void dispose() {
    _whatIDid.dispose();
    _whatIWillDo.dispose();
    _blockers.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    List<Map<String, dynamic>> loaded = [];

    final adminR = await widget.apiService.getCompanyEmployees();
    if (adminR['success'] == true) {
      loaded = (adminR['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['id'] != null)
          .toList();
    }

    if (loaded.isEmpty) {
      final chatR = await widget.apiService.getChatUsers();
      if (chatR['success'] == true) {
        for (final raw in chatR['data'] as List? ?? []) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final empId = m['employee_id'];
          if (empId == null) continue;
          m['id'] = empId is int ? empId : int.tryParse('$empId');
          m['name'] = m['full_name'] ?? m['username'];
          loaded.add(m);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _employees = loaded;
      _loadingEmployees = false;
    });
  }

  String _employeeLabel(Map<String, dynamic> e) {
    final name = e['full_name'] ?? e['name'] ?? e['username'] ?? 'Employee';
    final dept = e['department']?.toString();
    if (dept != null && dept.isNotEmpty) return '$name · $dept';
    return name.toString();
  }

  int? _employeeId(Map<String, dynamic> e) {
    final id = e['id'];
    if (id is int) return id;
    return int.tryParse('$id');
  }

  Future<void> _submit() async {
    final did = _whatIDid.text.trim();
    final will = _whatIWillDo.text.trim();
    if (did.isEmpty || will.isEmpty) {
      setState(() => _error = 'Please fill in what you did and what you will do.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final r = await widget.apiService.submitClosingReport(
      whatIDid: did,
      whatIWillDo: will,
      blockers: _blockers.text.trim(),
      dependencyEmployeeIds: _dependencyIds.toList(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (r['success'] == true) {
      Navigator.of(context).pop(true);
      AppToast.show(
        context,
        title: 'Report Submitted',
        message: 'Daily closing report saved successfully',
        type: AppToastType.success,
        icon: Icons.assignment_turned_in_rounded,
        placement: AppToastPlacement.top,
      );
    } else {
      setState(() => _error = r['error']?.toString() ?? 'Submit failed');
    }
  }

  void _close() {
    if (_submitting) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final desktop = Responsive.isDesktop(context);
    final tablet = Responsive.isTablet(context);
    final sheetH = media.size.height * (desktop ? 0.86 : (tablet ? 0.9 : 0.92));
    final maxW = desktop ? 680.0 : (tablet ? 560.0 : media.size.width);
    final todayLabel = DateFormat('EEE, d MMM yyyy').format(DateTime.now());
    final isUpdate = widget.existingReport != null;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: sheetH),
          child: AppTheme.glassBlur(
            topRadius: 28,
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(desktop ? 28 : 20, 16, desktop ? 16 : 12, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.accent.withValues(alpha: 0.35),
                                AppTheme.primary.withValues(alpha: 0.2),
                              ],
                            ),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accent.withValues(alpha: 0.22),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.assignment_turned_in_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isUpdate ? 'Update Report' : 'Submit Report',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: desktop ? 22 : 18,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isUpdate
                                    ? 'Refine today\'s closing summary'
                                    : 'Wrap up today and set tomorrow\'s focus',
                                style: TextStyle(
                                  color: AppTheme.textMuted.withValues(alpha: 0.92),
                                  fontSize: desktop ? 13.5 : 12.5,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppTheme.primaryBright.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.calendar_today_rounded,
                                      size: 12,
                                      color: AppTheme.primaryBright.withValues(alpha: 0.95),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      todayLabel,
                                      style: const TextStyle(
                                        color: AppTheme.primaryBright,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!widget.required)
                          IconButton(
                            onPressed: _close,
                            tooltip: 'Close',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                            ),
                            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: desktop ? 28 : 20),
                    child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        desktop ? 28 : 20,
                        16,
                        desktop ? 28 : 20,
                        12,
                      ),
                      child: desktop
                          ? _desktopFormBody()
                          : _mobileFormBody(),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      desktop ? 28 : 20,
                      12,
                      desktop ? 28 : 20,
                      desktop ? 20 : 14,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.02),
                          Colors.black.withValues(alpha: 0.18),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!widget.required)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _submitting ? null : _close,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.textMuted,
                                side: BorderSide(
                                  color: const Color(0xFF93C5FD).withValues(alpha: 0.22),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Later', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                        if (!widget.required) const SizedBox(width: 12),
                        Expanded(
                          flex: widget.required ? 1 : 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primaryBright,
                                  AppTheme.primary,
                                  AppTheme.primary.withValues(alpha: 0.88),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: FilledButton(
                              onPressed: _submitting ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      isUpdate ? 'Update report' : 'Submit report',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileFormBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionCard(
          icon: Icons.check_circle_outline_rounded,
          title: 'Today',
          subtitle: 'What you accomplished',
          child: _field(
            'What did you do today?',
            _whatIDid,
            maxLines: 4,
            hint: 'Shipped features, fixed bugs, meetings…',
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.flag_outlined,
          title: 'Tomorrow',
          subtitle: 'Next focus',
          child: _field(
            'What will you do next?',
            _whatIWillDo,
            maxLines: 3,
            hint: 'Priorities for the next work day…',
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.warning_amber_rounded,
          title: 'Blockers',
          subtitle: 'Optional',
          child: _field(
            'Anything blocking progress?',
            _blockers,
            maxLines: 2,
            required: false,
            hint: 'Waiting on review, access, decisions…',
          ),
        ),
        const SizedBox(height: 12),
        _dependenciesCard(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorBanner(_error!),
        ],
      ],
    );
  }

  Widget _desktopFormBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _sectionCard(
                icon: Icons.check_circle_outline_rounded,
                title: 'Today',
                subtitle: 'What you accomplished',
                child: _field(
                  'What did you do today?',
                  _whatIDid,
                  maxLines: 5,
                  hint: 'Shipped features, fixed bugs, meetings…',
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _sectionCard(
                icon: Icons.flag_outlined,
                title: 'Tomorrow',
                subtitle: 'Next focus',
                child: _field(
                  'What will you do next?',
                  _whatIWillDo,
                  maxLines: 5,
                  hint: 'Priorities for the next work day…',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _sectionCard(
                icon: Icons.warning_amber_rounded,
                title: 'Blockers',
                subtitle: 'Optional',
                child: _field(
                  'Anything blocking progress?',
                  _blockers,
                  maxLines: 3,
                  required: false,
                  hint: 'Waiting on review, access, decisions…',
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: _dependenciesCard()),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _errorBanner(_error!),
        ],
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: AppTheme.primary.withValues(alpha: 0.16),
                ),
                child: Icon(icon, size: 17, color: AppTheme.primaryBright),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _dependenciesCard() {
    return _sectionCard(
      icon: Icons.groups_2_outlined,
      title: 'Dependencies',
      subtitle: 'Optional teammates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadingEmployees)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_employees.isEmpty)
            Text(
              'No colleagues available for dependencies',
              style: TextStyle(
                color: AppTheme.textMuted.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _employees.map((e) {
                final id = _employeeId(e);
                if (id == null) return const SizedBox.shrink();
                final selected = _dependencyIds.contains(id);
                return FilterChip(
                  label: Text(_employeeLabel(e), style: const TextStyle(fontSize: 11.5)),
                  selected: selected,
                  onSelected: _submitting
                      ? null
                      : (v) => setState(() {
                            if (v) {
                              _dependencyIds.add(id);
                            } else {
                              _dependencyIds.remove(id);
                            }
                          }),
                  selectedColor: AppTheme.primary.withValues(alpha: 0.38),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppTheme.textMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.04),
                  side: BorderSide(
                    color: selected
                        ? AppTheme.primaryBright.withValues(alpha: 0.45)
                        : const Color(0xFF93C5FD).withValues(alpha: 0.18),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.danger, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    int maxLines = 1,
    bool required = true,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textMuted.withValues(alpha: 0.95),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (required) ...[
              const SizedBox(width: 4),
              Text(
                '*',
                style: TextStyle(color: AppTheme.danger.withValues(alpha: 0.85), fontSize: 12),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFF0A1628).withValues(alpha: 0.55),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: TextField(
            controller: c,
            maxLines: maxLines,
            enabled: !_submitting,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, height: 1.4),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: AppTheme.textMuted.withValues(alpha: 0.45),
                fontSize: 13,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
