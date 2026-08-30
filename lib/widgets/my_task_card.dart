import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../pages/task_detail_page.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/platform_capabilities.dart';
import '../utils/responsive.dart';
import '../utils/task_helpers.dart';
import 'premium_task_pickers.dart';
import 'task_action_buttons.dart';
import 'task_assignee_button.dart';
import 'task_stage_dropdown.dart' hide taskStageIdFrom;
import 'task_status_dropdown.dart';

/// My Task card — premium mobile row matching Submit Report language.
class MyTaskCard extends StatefulWidget {
  final Map<String, dynamic> task;
  final ApiService apiService;
  final VoidCallback onToggleComplete;
  final VoidCallback onUpdated;
  final bool compactGrid;
  final List<dynamic> stages;
  final List<dynamic> employees;

  const MyTaskCard({
    super.key,
    required this.task,
    required this.apiService,
    required this.onToggleComplete,
    required this.onUpdated,
    this.compactGrid = false,
    this.stages = const [],
    this.employees = const [],
  });

  @override
  State<MyTaskCard> createState() => _MyTaskCardState();
}

class _MyTaskCardState extends State<MyTaskCard> {
  bool _assignBusy = false;
  bool _stageBusy = false;
  List<dynamic> _employees = [];

  @override
  void initState() {
    super.initState();
    _employees = List<dynamic>.from(widget.employees);
  }

  @override
  void didUpdateWidget(covariant MyTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.employees != oldWidget.employees) {
      _employees = List<dynamic>.from(widget.employees);
    }
  }

  Map<String, dynamic> get task => widget.task;

  void _openDetail(BuildContext context) {
    final id = taskIdFrom(task);
    if (id == null) return;
    openTaskDetailPage(
      context,
      apiService: widget.apiService,
      taskId: id,
      projectId: taskProjectIdFrom(task) ?? 0,
      projectName: task['project_name']?.toString() ?? '',
      initialTask: Map<String, dynamic>.from(task),
      onClosed: widget.onUpdated,
    );
  }

  String _formatDueDate(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return '';
    try {
      final parsed = DateTime.parse(s.split('T').first);
      return DateFormat('dd MMM').format(parsed);
    } catch (_) {
      return s.length > 10 ? s.substring(0, 10) : s;
    }
  }

  Future<List<dynamic>> _ensureEmployees() async {
    if (_employees.isNotEmpty) return _employees;
    final pid = taskProjectIdFrom(task);
    if (pid == null || pid <= 0) return _employees;
    final r = await widget.apiService.getProjectAssignableEmployees(pid);
    if (r['success'] == true) {
      final list = normalizeProjectEmployeesList(r['data'] as List? ?? []);
      if (list.isNotEmpty && mounted) {
        setState(() => _employees = list);
      }
      return list;
    }
    return _employees;
  }

  Future<void> _openAssignee() async {
    if (_assignBusy) return;
    final employees = await _ensureEmployees();
    if (!mounted) return;
    if (employees.isEmpty) {
      AppToast.warning(context, 'No assignable people on this project');
      return;
    }
    final ids = await showPremiumAssigneeSheet(
      context: context,
      employees: employees,
      selectedIds: taskAssigneeIdsFrom(task),
      title: 'Assign task',
    );
    if (ids == null || !mounted) return;

    setState(() => _assignBusy = true);
    final taskId = taskIdFrom(task);
    if (taskId == null) {
      setState(() => _assignBusy = false);
      return;
    }
    final r = await widget.apiService.updateTaskAssignees(
      taskId,
      ids,
      projectId: taskProjectIdFrom(task) ?? 0,
      task: task,
    );
    if (!mounted) return;
    setState(() => _assignBusy = false);
    if (r['success'] == true) {
      AppToast.success(
        context,
        ids.isEmpty
            ? 'Assignees cleared'
            : (ids.length == 1 ? 'Assignee updated' : '${ids.length} people assigned'),
      );
      widget.onUpdated();
    } else {
      AppToast.updateFailed(context, r['error']?.toString());
    }
  }

  Future<void> _openStage() async {
    if (_stageBusy || widget.stages.isEmpty) return;
    final currentId = taskStageIdFrom(task);
    final picked = await showPremiumStageSheet(
      context: context,
      stages: widget.stages,
      selectedStageId: currentId,
      currentName: task['stage_name']?.toString(),
    );
    if (picked == null || !mounted) return;
    if (picked == currentId) return;

    setState(() => _stageBusy = true);
    final taskId = taskIdFrom(task);
    if (taskId == null) {
      setState(() => _stageBusy = false);
      return;
    }
    final r = await widget.apiService.updateTask(
      taskId,
      {'stage_id': picked},
      projectId: taskProjectIdFrom(task) ?? 0,
      task: Map<String, dynamic>.from(task),
    );
    if (!mounted) return;
    setState(() => _stageBusy = false);
    if (r['success'] == true) {
      widget.onUpdated();
    } else {
      AppToast.updateFailed(context, r['error']?.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final simple = PlatformCapabilities.immersiveChatChrome || Responsive.isMobile(context);
    if (simple) return _buildPremiumMobile(context);
    return _buildDesktop(context);
  }

  Widget _buildPremiumMobile(BuildContext context) {
    final isCompleted = taskIsCompleted(task);
    final title = taskDisplayTitle(task);
    final projectName = taskProjectNameFrom(task);
    final dueLabel = _formatDueDate(task['due_date']);
    final stageName = (task['stage_name']?.toString() ?? '').trim();
    final people = taskAssigneeListFrom(task);
    final hasStages = widget.stages.isNotEmpty;
    final firstName = people.isNotEmpty ? (people.first['name']?.toString() ?? '') : '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: AppTheme.taskCardDecoration(borderRadius: 16).copyWith(
            border: Border.all(
              color: isCompleted
                  ? AppTheme.success.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CompleteCheck(
                    completed: isCompleted,
                    onTap: widget.onToggleComplete,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            letterSpacing: -0.15,
                            color: isCompleted ? AppTheme.textMuted : AppTheme.textPrimary,
                            decoration: isCompleted ? TextDecoration.lineThrough : null,
                            decorationColor: AppTheme.textMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (projectName.isNotEmpty || dueLabel.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            [
                              if (projectName.isNotEmpty) projectName,
                              if (dueLabel.isNotEmpty) dueLabel,
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: dueLabel.isNotEmpty
                                  ? AppTheme.accent.withValues(alpha: 0.9)
                                  : AppTheme.textMuted.withValues(alpha: 0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ActionChip(
                    onTap: _assignBusy ? null : _openAssignee,
                    busy: _assignBusy,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (people.isEmpty)
                          Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 16,
                            color: AppTheme.primaryBright.withValues(alpha: 0.95),
                          )
                        else
                          CircleAvatar(
                            radius: 9,
                            backgroundColor: avatarColorForName(firstName),
                            child: Text(
                              firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 88),
                          child: Text(
                            people.isEmpty
                                ? 'Assign'
                                : (people.length == 1
                                    ? (firstName.isNotEmpty ? firstName.split(' ').first : 'Assigned')
                                    : '${people.length} people'),
                            style: TextStyle(
                              color: AppTheme.textPrimary.withValues(alpha: 0.95),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasStages) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: _ActionChip(
                        onTap: _stageBusy ? null : _openStage,
                        busy: _stageBusy,
                        accent: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.layers_rounded,
                              size: 15,
                              color: AppTheme.accent.withValues(alpha: 0.95),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                stageName.isNotEmpty ? stageName : 'Stage',
                                style: TextStyle(
                                  color: AppTheme.textPrimary.withValues(alpha: 0.95),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: AppTheme.textMuted.withValues(alpha: 0.8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppTheme.textMuted.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final isCompleted = taskIsCompleted(task);
    final title = taskDisplayTitle(task);
    final taskId = taskIdFrom(task);
    final projectId = taskProjectIdFrom(task) ?? 0;
    final projectName = taskProjectNameFrom(task);
    final dueLabel = _formatDueDate(task['due_date']);
    final hasStages = widget.stages.isNotEmpty;
    final pad = widget.compactGrid ? 8.0 : 14.0;

    return Container(
      decoration: AppTheme.loginInsetDecoration(borderRadius: widget.compactGrid ? 12 : 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openDetail(context),
              borderRadius: BorderRadius.vertical(top: Radius.circular(widget.compactGrid ? 11 : 13)),
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, widget.compactGrid ? 4 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: widget.compactGrid ? 12.5 : 15,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: isCompleted ? AppTheme.textMuted : AppTheme.textPrimary,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                        decorationColor: AppTheme.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (projectName.isNotEmpty || dueLabel.isNotEmpty) ...[
                      SizedBox(height: widget.compactGrid ? 6 : 8),
                      Wrap(
                        spacing: widget.compactGrid ? 8 : 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (projectName.isNotEmpty)
                            _MetaLine(icon: Icons.folder_open_rounded, label: projectName),
                          if (dueLabel.isNotEmpty)
                            _MetaLine(icon: Icons.event_rounded, label: dueLabel, accent: true),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.compactGrid ? 6 : 12,
              0,
              widget.compactGrid ? 6 : 12,
              widget.compactGrid ? 6 : 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (taskId != null)
                  Row(
                    children: [
                      Expanded(
                        child: TaskStatusDropdown(
                          key: ValueKey<String>('ts_${task['id']}_${task['status']}_${task['completed']}'),
                          taskId: taskId,
                          task: task,
                          projectId: projectId,
                          apiService: widget.apiService,
                          onUpdated: widget.onUpdated,
                          compact: true,
                        ),
                      ),
                      if (hasStages) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: TaskStageDropdown(
                            key: ValueKey<String>('stg_${task['id']}_${task['stage_id']}'),
                            taskId: taskId,
                            task: task,
                            stages: widget.stages,
                            projectId: projectId,
                            apiService: widget.apiService,
                            onUpdated: widget.onUpdated,
                            compact: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TaskAssigneeButton(
                        task: task,
                        employees: widget.employees,
                        apiService: widget.apiService,
                        onUpdated: widget.onUpdated,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 118,
                      child: TaskCompleteButton(
                        isCompleted: isCompleted,
                        onPressed: widget.onToggleComplete,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteCheck extends StatelessWidget {
  final bool completed;
  final VoidCallback onTap;

  const _CompleteCheck({required this.completed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: completed
                ? const LinearGradient(colors: [Color(0xFF34D399), Color(0xFF059669)])
                : null,
            color: completed ? null : Colors.transparent,
            border: Border.all(
              color: completed
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.55),
              width: 2,
            ),
            boxShadow: completed
                ? [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: completed
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool busy;
  final bool accent;

  const _ActionChip({
    required this.child,
    this.onTap,
    this.busy = false,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: (accent ? AppTheme.accent : AppTheme.primary).withValues(alpha: 0.12),
              border: Border.all(
                color: (accent ? AppTheme.accent : AppTheme.primaryBright).withValues(alpha: 0.28),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;

  const _MetaLine({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? AppTheme.accent.withValues(alpha: 0.9)
        : AppTheme.textMuted.withValues(alpha: 0.88);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
