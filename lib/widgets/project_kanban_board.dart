import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/platform_capabilities.dart';
import '../utils/responsive.dart';
import '../utils/task_helpers.dart';

/// Drag-and-drop payload for moving tasks between stages.
class TaskDragPayload {
  final int taskId;
  final int? sourceStageId;

  const TaskDragPayload({required this.taskId, this.sourceStageId});
}

typedef KanbanMoveHandler = Future<void> Function(TaskDragPayload data, int targetStageId);

/// Android-first Kanban board — swipe stages on mobile, drag-drop + quick-move chips.
class ProjectKanbanBoard extends StatefulWidget {
  final List<Map<String, dynamic>> stages;
  final List<Map<String, dynamic>> unassignedTasks;
  final KanbanMoveHandler onMoveTask;
  final void Function(Map<String, dynamic> task) onTaskTap;
  final void Function(int stageId) onCreateTask;
  final VoidCallback onAddStage;
  final void Function(int stageId, String name) onDeleteStage;
  final void Function(Map<String, dynamic> task) onAssigneeTap;
  final void Function(Map<String, dynamic> task) onTaskMenu;

  const ProjectKanbanBoard({
    super.key,
    required this.stages,
    required this.unassignedTasks,
    required this.onMoveTask,
    required this.onTaskTap,
    required this.onCreateTask,
    required this.onAddStage,
    required this.onDeleteStage,
    required this.onAssigneeTap,
    required this.onTaskMenu,
  });

  @override
  State<ProjectKanbanBoard> createState() => _ProjectKanbanBoardState();
}

class _ProjectKanbanBoardState extends State<ProjectKanbanBoard> {
  final _boardHScroll = ScrollController();
  final _pageCtrl = PageController();
  int _activeStage = 0;
  int? _movingTaskId;

  bool get _mobileMode => Responsive.widthOf(context) < 720;

  List<Map<String, dynamic>> get _allColumns {
    final cols = <Map<String, dynamic>>[];
    for (final s in widget.stages) {
      cols.add({
        'id': s['id'],
        'name': s['name'] ?? 'Stage',
        'color': s['color'] ?? '#3B82F6',
        'tasks': (s['tasks'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[],
        'isUnassigned': false,
      });
    }
    if (widget.unassignedTasks.isNotEmpty) {
      cols.add({
        'id': -1,
        'name': 'No Stage',
        'color': '#64748B',
        'tasks': widget.unassignedTasks,
        'isUnassigned': true,
      });
    }
    return cols;
  }

  Color _hex(String h) {
    try {
      return Color(int.parse(h.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppTheme.primary;
    }
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'high':
      case 'critical':
        return AppTheme.danger;
      case 'medium':
        return AppTheme.warning;
      default:
        return AppTheme.success;
    }
  }

  @override
  void dispose() {
    _boardHScroll.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _move(TaskDragPayload data, int targetStageId) async {
    if (data.sourceStageId != null && data.sourceStageId == targetStageId) return;
    setState(() => _movingTaskId = data.taskId);
    await widget.onMoveTask(data, targetStageId);
    if (mounted) setState(() => _movingTaskId = null);
  }

  void _showMoveSheet(Map<String, dynamic> task, int? sourceStageId) {
    final others = widget.stages.where((s) => s['id'] != sourceStageId).toList();
    if (others.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: AppTheme.loginShell().copyWith(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Move to stage',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              task['name']?.toString() ?? 'Task',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            ...others.map((s) {
              final color = _hex(s['color']?.toString() ?? '#3B82F6');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _move(
                        TaskDragPayload(taskId: task['id'] as int, sourceStageId: sourceStageId),
                        s['id'] as int,
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s['name']?.toString() ?? 'Stage',
                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          Icon(Icons.arrow_forward_rounded, size: 16, color: color),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cols = _allColumns;
    if (cols.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_kanban_outlined, size: 56, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            const Text('No stages yet', style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: widget.onAddStage,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Stage'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.featureVault,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _mobileMode
                    ? 'Swipe between stages or long-press a task to drag.'
                    : 'Long-press a task and drag it to another column.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_mobileMode) _stageTabStrip(cols),
        Expanded(
          child: _mobileMode ? _mobilePageView(cols) : _desktopBoard(cols),
        ),
      ],
    );
  }

  Widget _stageTabStrip(List<Map<String, dynamic>> cols) {
    return Container(
      height: 48,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: cols.length,
        itemBuilder: (_, i) {
          final col = cols[i];
          final color = _hex(col['color']?.toString() ?? '#3B82F6');
          final active = i == _activeStage;
          final count = (col['tasks'] as List).length;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                onTap: () {
                  setState(() => _activeStage = i);
                  _pageCtrl.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
                },
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: active ? color : color.withValues(alpha: 0.7), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        col['name']?.toString() ?? 'Stage',
                        style: TextStyle(
                          color: active ? AppTheme.bgDeep : AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: active ? AppTheme.bgDeep.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: active ? AppTheme.bgDeep : AppTheme.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _mobilePageView(List<Map<String, dynamic>> cols) {
    return PageView.builder(
      controller: _pageCtrl,
      itemCount: cols.length,
      onPageChanged: (i) => setState(() => _activeStage = i),
      physics: const BouncingScrollPhysics(),
      itemBuilder: (_, i) {
        final col = cols[i];
        final stageId = col['isUnassigned'] == true ? null : col['id'] as int?;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: _stageColumn(col, stageId, fullWidth: true),
        );
      },
    );
  }

  Widget _desktopBoard(List<Map<String, dynamic>> cols) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight.isFinite && constraints.maxHeight > 140 ? constraints.maxHeight : 400.0;
        final colW = Responsive.kanbanColumnWidth(context);
        return Scrollbar(
          controller: _boardHScroll,
          thumbVisibility: true,
          thickness: 6,
          radius: const Radius.circular(6),
          child: ListView(
            controller: _boardHScroll,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
            children: [
              for (final col in cols)
                SizedBox(
                  width: colW,
                  height: h,
                  child: _stageColumn(
                    col,
                    col['isUnassigned'] == true ? null : col['id'] as int?,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _stageColumn(Map<String, dynamic> col, int? stageId, {bool fullWidth = false}) {
    final color = _hex(col['color']?.toString() ?? '#3B82F6');
    final tasks = col['tasks'] as List<Map<String, dynamic>>;
    final isUnassigned = col['isUnassigned'] == true;

    Widget buildColumn({bool highlighted = false}) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: fullWidth ? EdgeInsets.zero : const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: highlighted ? 0.07 : 0.035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted ? color.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.07),
            width: highlighted ? 2 : 1,
          ),
          boxShadow: highlighted
              ? [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 4))]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stageHeader(col, color, stageId, tasks.length, isUnassigned),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 32, color: Colors.white.withValues(alpha: 0.12)),
                          const SizedBox(height: 8),
                          Text(
                            highlighted ? 'Release here' : 'No tasks',
                            style: TextStyle(
                              color: highlighted ? color : Colors.white.withValues(alpha: 0.22),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                      physics: const BouncingScrollPhysics(),
                      itemCount: tasks.length,
                      itemBuilder: (_, i) => _taskWrap(tasks[i], color, stageId),
                    ),
            ),
            if (!isUnassigned && stageId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: TextButton.icon(
                  onPressed: () => widget.onCreateTask(stageId),
                  icon: Icon(Icons.add_rounded, size: 18, color: color),
                  label: Text('Add task', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                  style: TextButton.styleFrom(
                    backgroundColor: color.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (!PlatformCapabilities.kanbanTaskDragDrop || stageId == null && isUnassigned) {
      return buildColumn();
    }

    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (d) {
        final target = stageId ?? -1;
        return d.data.sourceStageId != target;
      },
      onAcceptWithDetails: (d) {
        if (stageId != null) {
          _move(d.data, stageId);
        }
      },
      builder: (_, candidate, __) => buildColumn(highlighted: candidate.isNotEmpty),
    );
  }

  Widget _stageHeader(
    Map<String, dynamic> col,
    Color color,
    int? stageId,
    int count,
    bool isUnassigned,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              col['name']?.toString() ?? 'Stage',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          if (!isUnassigned && stageId != null) ...[
            IconButton(
              onPressed: () => widget.onCreateTask(stageId),
              icon: Icon(Icons.add_circle_outline, color: color, size: 20),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: AppTheme.textMuted, size: 18),
              color: AppTheme.surface2,
              onSelected: (v) {
                if (v == 'add') widget.onCreateTask(stageId);
                if (v == 'delete') widget.onDeleteStage(stageId, col['name']?.toString() ?? '');
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'add', child: Text('Add task')),
                const PopupMenuItem(value: 'delete', child: Text('Delete stage', style: TextStyle(color: Colors.redAccent))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _taskWrap(Map<String, dynamic> task, Color stageColor, int? sourceStageId) {
    final payload = TaskDragPayload(taskId: task['id'] as int, sourceStageId: sourceStageId);
    final card = _kanbanTaskCard(task, stageColor, sourceStageId);
    final isMoving = _movingTaskId == task['id'];
    final colW = Responsive.kanbanColumnWidth(context) - 24;

    Widget child = card;
    if (PlatformCapabilities.kanbanTaskDragDrop) {
      final feedback = Transform.scale(
        scale: 1.03,
        child: Material(
          elevation: 16,
          shadowColor: stageColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          color: Colors.transparent,
          child: SizedBox(width: _mobileMode ? MediaQuery.sizeOf(context).width - 40 : colW, child: card),
        ),
      );
      child = PlatformCapabilities.kanbanLongPressDrag
          ? LongPressDraggable<TaskDragPayload>(
              data: payload,
              feedback: feedback,
              childWhenDragging: Opacity(opacity: 0.25, child: card),
              hapticFeedbackOnStart: true,
              onDragStarted: () => HapticFeedback.mediumImpact(),
              child: card,
            )
          : Draggable<TaskDragPayload>(
              data: payload,
              feedback: feedback,
              childWhenDragging: Opacity(opacity: 0.25, child: card),
              onDragStarted: () => HapticFeedback.selectionClick(),
              child: card,
            );
    }

    return AnimatedScale(
      scale: isMoving ? 0.96 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: isMoving ? 0.5 : 1,
        duration: const Duration(milliseconds: 180),
        child: Padding(
          key: ValueKey('kanban_${task['id']}_$sourceStageId'),
          padding: const EdgeInsets.only(bottom: 8),
          child: child,
        ),
      ),
    );
  }

  Widget _kanbanTaskCard(Map<String, dynamic> t, Color stageColor, int? sourceStageId) {
    final pri = (t['priority'] ?? 'medium').toString();
    final done = taskIsCompleted(t);
    final taskId = t['id'];
    final due = _shortDate(t['due_date']?.toString());
    final otherStages = widget.stages.where((s) => s['id'] != sourceStageId).take(3).toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onTaskTap(t),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface2.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (PlatformCapabilities.kanbanLongPressDrag)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.drag_indicator_rounded, size: 16, color: Colors.white.withValues(alpha: 0.2)),
                    ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: _priorityColor(pri), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('T-$taskId', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (otherStages.isNotEmpty)
                    Material(
                      color: stageColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => _showMoveSheet(t, sourceStageId),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_forward_rounded, size: 12, color: stageColor),
                              const SizedBox(width: 2),
                              Text('Move', style: TextStyle(color: stageColor, fontSize: 9, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => widget.onTaskMenu(t),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.more_horiz, size: 16, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _title(t),
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: AppTheme.textMuted,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (otherStages.isNotEmpty) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (final s in otherStages)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(
                              s['name']?.toString() ?? 'Stage',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                            avatar: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _hex(s['color']?.toString() ?? '#3B82F6'),
                                shape: BoxShape.circle,
                              ),
                            ),
                            backgroundColor: _hex(s['color']?.toString() ?? '#3B82F6').withValues(alpha: 0.12),
                            side: BorderSide(color: _hex(s['color']?.toString() ?? '#3B82F6').withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _move(
                              TaskDragPayload(taskId: t['id'] as int, sourceStageId: sourceStageId),
                              s['id'] as int,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => widget.onAssigneeTap(t),
                    child: _assigneeRow(t),
                  ),
                  const Spacer(),
                  if (due.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule_rounded, size: 11, color: AppTheme.textMuted.withValues(alpha: 0.7)),
                        const SizedBox(width: 3),
                        Text(due, style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assigneeRow(Map<String, dynamic> task) {
    final people = _assignees(task);
    if (people.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            child: const Icon(Icons.person_add_alt_1, size: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(width: 4),
          Text('Assign', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ],
      );
    }
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < people.length && i < 3; i++)
            Transform.translate(
              offset: Offset(i * 14.0, 0),
              child: CircleAvatar(
                radius: 10,
                backgroundColor: _avatarColor(people[i]),
                child: Text(
                  people[i].substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (people.length > 3)
            Padding(
              padding: EdgeInsets.only(left: people.length.clamp(1, 3) * 14.0 + 4),
              child: Text('+${people.length - 3}', style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
            ),
        ],
      ),
    );
  }

  List<String> _assignees(Map<String, dynamic> task) {
    final raw = task['assignees'];
    if (raw is List) {
      return raw.map((a) {
        if (a is Map) return a['name']?.toString() ?? a['full_name']?.toString() ?? '?';
        return a.toString();
      }).where((s) => s.isNotEmpty).toList();
    }
    final name = task['assignee_name'] ?? task['user_name'];
    if (name != null && name.toString().isNotEmpty) return [name.toString()];
    return [];
  }

  Color _avatarColor(String name) {
    const colors = [Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFF8B5CF6), Color(0xFFEC4899)];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _title(Map<String, dynamic> t) => (t['name'] ?? t['title'] ?? '').toString();

  String _shortDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final d = DateTime.parse(raw);
      return '${d.day}/${d.month}';
    } catch (_) {
      return raw.length > 8 ? raw.substring(0, 8) : raw;
    }
  }
}
