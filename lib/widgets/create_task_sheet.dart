import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

/// Compact Add Task sheet — same language as Submit Report.
Future<bool?> showCreateTaskSheet({
  required BuildContext context,
  required ApiService apiService,
  required List<Map<String, dynamic>> projects,
  int? initialProjectId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppTheme.modalBarrierColor,
    builder: (ctx) => _CreateTaskSheet(
      apiService: apiService,
      projects: projects,
      initialProjectId: initialProjectId,
    ),
  );
}

class _CreateTaskSheet extends StatefulWidget {
  final ApiService apiService;
  final List<Map<String, dynamic>> projects;
  final int? initialProjectId;

  const _CreateTaskSheet({
    required this.apiService,
    required this.projects,
    this.initialProjectId,
  });

  @override
  State<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends State<_CreateTaskSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int? _projectId;
  String? _dueDate;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _projectId = widget.initialProjectId;
    if (_projectId == null && widget.projects.length == 1) {
      final id = widget.projects.first['id'];
      _projectId = id is int ? id : int.tryParse('$id');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  int? _pid(Map<String, dynamic> p) {
    final id = p['id'];
    if (id is int) return id;
    return int.tryParse('$id');
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      builder: (c, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primaryBright,
            surface: AppTheme.surface2,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dueDate =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Add a task title');
      return;
    }
    if (_projectId == null) {
      setState(() => _error = 'Pick a project');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final r = await widget.apiService.createTask(
      name: title,
      description: _descCtrl.text.trim(),
      projectId: _projectId,
      dueDate: _dueDate,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (r['success'] == true) {
      Navigator.of(context).pop(true);
      AppToast.show(
        context,
        title: 'Task created',
        message: 'Added to your list',
        type: AppToastType.success,
        icon: Icons.task_alt_rounded,
        placement: AppToastPlacement.top,
      );
    } else {
      setState(() => _error = r['error']?.toString() ?? 'Could not create task');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.58;
    final dueLabel = _dueDate == null
        ? 'Due date (optional)'
        : DateFormat('dd MMM yyyy').format(DateTime.parse(_dueDate!));

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
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add task',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Keep it simple — title + project',
                                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _submitting ? null : () => Navigator.pop(context, false),
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
                              controller: _titleCtrl,
                              maxLines: 2,
                              minLines: 1,
                              enabled: !_submitting,
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              decoration: AppTheme.taskLabeledInput('Task title'),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _descCtrl,
                              maxLines: 2,
                              enabled: !_submitting,
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              decoration: AppTheme.taskLabeledInput('Notes', hint: 'Optional'),
                            ),
                            const SizedBox(height: 10),
                            Text('Project', style: AppTheme.caption),
                            const SizedBox(height: 6),
                            if (widget.projects.isEmpty)
                              Text(
                                'No projects available',
                                style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 12),
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final p in widget.projects)
                                    () {
                                      final id = _pid(p);
                                      final name = p['name']?.toString() ?? 'Project';
                                      final selected = id != null && id == _projectId;
                                      return FilterChip(
                                        label: Text(name, style: const TextStyle(fontSize: 11)),
                                        selected: selected,
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        onSelected: _submitting
                                            ? null
                                            : (_) => setState(() => _projectId = id),
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
                                    }(),
                                ],
                              ),
                            const SizedBox(height: 10),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _submitting ? null : _pickDue,
                                borderRadius: BorderRadius.circular(12),
                                child: Ink(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: AppTheme.loginInsetDecoration(borderRadius: 12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.event_rounded,
                                        size: 18,
                                        color: _dueDate != null
                                            ? AppTheme.accent
                                            : AppTheme.textMuted,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          dueLabel,
                                          style: TextStyle(
                                            color: _dueDate != null
                                                ? AppTheme.textPrimary
                                                : AppTheme.textMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (_dueDate != null)
                                        GestureDetector(
                                          onTap: () => setState(() => _dueDate = null),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 16,
                                            color: AppTheme.textMuted.withValues(alpha: 0.8),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _submitting ? null : () => Navigator.pop(context, false),
                              style: AppTheme.secondaryButton(radius: 12).copyWith(
                                foregroundColor: WidgetStateProperty.all(AppTheme.textMuted),
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
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
                                  : const Text('Create task', style: TextStyle(fontWeight: FontWeight.w700)),
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
