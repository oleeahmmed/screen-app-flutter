import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/responsive.dart';
import 'app_bottom_sheet.dart';
import 'empty_state.dart';
import 'glass_card.dart';

/// Daily closing report â€” `/api/closing-reports/`.
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

/// Compact closing-report sheet â€” slides up like Quick menu.
/// Returns `true` when submitted successfully.
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
      setState(() => _error = 'Fill in today and tomorrow fields.');
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
        message: 'Daily closing report saved',
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
    final isUpdate = widget.existingReport != null;
    final maxH = media.size.height * 0.58;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: DecoratedBox(
              decoration: AppTheme.taskCardDecoration(borderRadius: 20).copyWith(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isUpdate ? 'Update report' : 'Submit report',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('EEE, d MMM').format(DateTime.now()),
                                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (!widget.required)
                            IconButton(
                              onPressed: _close,
                              icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 22),
                            ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _whatIDid,
                              maxLines: 2,
                              enabled: !_submitting,
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              decoration: AppTheme.taskLabeledInput('What I did today'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _whatIWillDo,
                              maxLines: 2,
                              enabled: !_submitting,
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              decoration: AppTheme.taskLabeledInput('What I will do next'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _blockers,
                              maxLines: 1,
                              enabled: !_submitting,
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              decoration: AppTheme.taskLabeledInput('Blockers', hint: 'Optional'),
                            ),
                            const SizedBox(height: 10),
                            Text('Dependencies', style: AppTheme.caption),
                            const SizedBox(height: 6),
                            if (_loadingEmployees)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBright),
                                  ),
                                ),
                              )
                            else if (_employees.isEmpty)
                              Text('None', style: AppTheme.caption)
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _employees.take(12).map((e) {
                                  final id = _employeeId(e);
                                  if (id == null) return const SizedBox.shrink();
                                  final selected = _dependencyIds.contains(id);
                                  return FilterChip(
                                    label: Text(_employeeLabel(e), style: const TextStyle(fontSize: 11)),
                                    selected: selected,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onSelected: _submitting
                                        ? null
                                        : (v) => setState(() {
                                              if (v) {
                                                _dependencyIds.add(id);
                                              } else {
                                                _dependencyIds.remove(id);
                                              }
                                            }),
                                    selectedColor: AppTheme.primary.withValues(alpha: 0.35),
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                      color: selected ? Colors.white : AppTheme.textMuted,
                                      fontSize: 11,
                                    ),
                                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                                    side: BorderSide(
                                      color: selected
                                          ? AppTheme.primaryBright.withValues(alpha: 0.4)
                                          : Colors.white.withValues(alpha: 0.1),
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  );
                                }).toList(),
                              ),
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                            ],
                          ],
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
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        children: [
                          if (!widget.required) ...[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _submitting ? null : _close,
                                style: AppTheme.secondaryButton(radius: 12).copyWith(
                                  foregroundColor: WidgetStateProperty.all(AppTheme.textMuted),
                                  padding: WidgetStateProperty.all(
                                    const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                                child: const Text('Later'),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _submitting ? null : _submit,
                              style: AppTheme.primaryButton(radius: 12).copyWith(
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(isUpdate ? 'Update' : 'Submit'),
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
      ),
    );
  }
}
