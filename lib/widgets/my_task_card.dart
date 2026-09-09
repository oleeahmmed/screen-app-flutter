import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../pages/task_detail_page.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/task_helpers.dart';
import 'premium_task_pickers.dart';

/// My Task card — list (phone) or grid (tablet+) layouts.
class MyTaskCard extends StatefulWidget {
  final Map<String, dynamic> task;
  final ApiService apiService;
  final VoidCallback onToggleComplete;
  final VoidCallback onUpdated;
  final List<dynamic> stages;
  final List<dynamic> employees;
  /// `list` = full-width timeline row; `grid` = compact multi-column card.
  final MyTaskCardLayout layout;

  const MyTaskCard({
    super.key,
    required this.task,
    required this.apiService,
    required this.onToggleComplete,
    required this.onUpdated,
    this.stages = const [],
    this.employees = const [],
    this.layout = MyTaskCardLayout.list,
  });

  @override
  State<MyTaskCard> createState() => _MyTaskCardState();
}

enum MyTaskCardLayout { list, grid }

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
    return widget.layout == MyTaskCardLayout.grid
        ? _buildGrid(context)
        : _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    final isCompleted = taskIsCompleted(task);
    final title = taskDisplayTitle(task);
    final projectName = taskProjectNameFrom(task);
    final dueLabel = _formatDueDate(task['due_date']);
    final stageName = (task['stage_name']?.toString() ?? '').trim();
    final priority = (task['priority'] ?? 'medium').toString();
    final priorityColor = AppTheme.taskPriorityColor(priority);
    final people = taskAssigneeListFrom(task);
    final accent = isCompleted ? AppTheme.success : priorityColor;

    final metaParts = <String>[
      if (projectName.isNotEmpty) projectName,
      if (stageName.isNotEmpty) stageName,
      if (dueLabel.isNotEmpty) dueLabel,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openDetail(context),
          onLongPress: () => _showQuickActions(context),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withValues(alpha: 0.045),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3.5, color: accent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 11, 8, 11),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CompleteCheck(
                              completed: isCompleted,
                              onTap: widget.onToggleComplete,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      height: 1.28,
                                      letterSpacing: -0.2,
                                      color: isCompleted
                                          ? AppTheme.textMuted
                                          : AppTheme.textPrimary,
                                      decoration: isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor: AppTheme.textMuted,
                                    ),
                                  ),
                                  if (metaParts.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      metaParts.join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: dueLabel.isNotEmpty && !isCompleted
                                            ? AppTheme.accent.withValues(alpha: 0.95)
                                            : AppTheme.textMuted.withValues(alpha: 0.9),
                                      ),
                                    ),
                                  ],
                                  if (people.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _AssigneeAvatars(people: people),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!isCompleted)
                                  _PriorityDot(priority: priority),
                                PopupMenuButton<String>(
                                  tooltip: 'Actions',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    size: 18,
                                    color: AppTheme.textMuted.withValues(alpha: 0.75),
                                  ),
                                  color: const Color(0xFF152238),
                                  onSelected: (v) {
                                    if (v == 'assign') unawaited(_openAssignee());
                                    if (v == 'stage') unawaited(_openStage());
                                    if (v == 'detail') _openDetail(context);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'detail', child: Text('Open')),
                                    const PopupMenuItem(value: 'assign', child: Text('Assign')),
                                    if (widget.stages.isNotEmpty)
                                      const PopupMenuItem(
                                        value: 'stage',
                                        child: Text('Change stage'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
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

  Widget _buildGrid(BuildContext context) {
    final isCompleted = taskIsCompleted(task);
    final title = taskDisplayTitle(task);
    final projectName = taskProjectNameFrom(task);
    final dueLabel = _formatDueDate(task['due_date']);
    final stageName = (task['stage_name']?.toString() ?? '').trim();
    final priority = (task['priority'] ?? 'medium').toString();
    final priorityColor = AppTheme.taskPriorityColor(priority);
    final people = taskAssigneeListFrom(task);
    final accent = isCompleted ? AppTheme.success : priorityColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(context),
        onLongPress: () => _showQuickActions(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: accent.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  color: accent,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CompleteCheck(
                          completed: isCompleted,
                          onTap: widget.onToggleComplete,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: isCompleted
                                  ? AppTheme.textMuted
                                  : AppTheme.textPrimary,
                              decoration: isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: AppTheme.textMuted,
                            ),
                          ),
                        ),
                        if (!isCompleted) ...[
                          const SizedBox(width: 4),
                          _PriorityDot(priority: priority),
                        ],
                      ],
                    ),
                    if (projectName.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMuted.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (dueLabel.isNotEmpty)
                          _MetaBadge(
                            icon: Icons.event_rounded,
                            label: dueLabel,
                            color: AppTheme.accent,
                          ),
                        if (stageName.isNotEmpty) ...[
                          if (dueLabel.isNotEmpty) const SizedBox(width: 6),
                          Flexible(
                            child: _MetaBadge(
                              icon: Icons.layers_rounded,
                              label: stageName,
                              color: AppTheme.primaryBright,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (people.isNotEmpty) _AssigneeAvatars(people: people, max: 3),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _MiniAction(
                          icon: Icons.person_add_alt_1_rounded,
                          label: people.isEmpty ? 'Assign' : '${people.length}',
                          busy: _assignBusy,
                          onTap: _assignBusy ? null : _openAssignee,
                        ),
                        if (widget.stages.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _MiniAction(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Stage',
                            busy: _stageBusy,
                            onTap: _stageBusy ? null : _openStage,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF152238),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded, color: AppTheme.primaryBright),
                title: const Text('Open task', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openDetail(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded, color: AppTheme.primaryBright),
                title: const Text('Assign', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_openAssignee());
                },
              ),
              if (widget.stages.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.layers_rounded, color: AppTheme.accent),
                  title: const Text('Change stage', style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_openStage());
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _PriorityDot extends StatelessWidget {
  final String priority;

  const _PriorityDot({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.taskPriorityColor(priority);
    final label = priority.isEmpty ? 'M' : priority[0].toUpperCase();
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CompleteCheck extends StatelessWidget {
  final bool completed;
  final VoidCallback onTap;
  final double size;

  const _CompleteCheck({
    required this.completed,
    required this.onTap,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed ? AppTheme.success : Colors.transparent,
            border: Border.all(
              color: completed
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.45),
              width: 1.8,
            ),
          ),
          child: completed
              ? Icon(Icons.check_rounded, size: size * 0.62, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _AssigneeAvatars extends StatelessWidget {
  final List<Map<String, dynamic>> people;
  final int max;

  const _AssigneeAvatars({required this.people, this.max = 4});

  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    final extra = people.length - shown.length;
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < shown.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 0, right: i < shown.length - 1 ? 0 : 0),
              child: Transform.translate(
                offset: Offset(i * -5.0, 0),
                child: _avatar(shown[i]['name']?.toString() ?? ''),
              ),
            ),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                '+$extra',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted.withValues(alpha: 0.9),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatar(String name) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColorForName(name),
        border: Border.all(color: const Color(0xFF0B141A), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  const _MiniAction({
    required this.icon,
    required this.label,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primaryBright),
                  )
                else
                  Icon(icon, size: 13, color: AppTheme.primaryBright),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
