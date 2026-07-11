// tasks_page.dart — My Task (dashboard glass theme, simple list)

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/responsive.dart';
import '../utils/task_helpers.dart';
import '../widgets/my_task_card.dart';

class TasksPage extends StatefulWidget {
  final ApiService apiService;
  final bool embeddedInParent;

  const TasksPage({
    super.key,
    required this.apiService,
    this.embeddedInParent = false,
  });

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _ProjectMeta {
  final List<dynamic> stages;
  final List<dynamic> employees;

  const _ProjectMeta({
    required this.stages,
    required this.employees,
  });
}

class _TasksPageState extends State<TasksPage> {
  List<Map<String, dynamic>> _projects = [];
  List<dynamic> _tasks = [];
  final Map<int, _ProjectMeta> _projectMeta = {};
  bool _loading = true;
  String _filter = 'pending';
  int? _selectedProjectId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final result = await widget.apiService.getMyTasks();
    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>? ?? {};
      final projects = (data['projects'] as List? ?? [])
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
      final tasks = data['tasks'] as List? ?? [];

      setState(() {
        _projects = projects;
        _tasks = tasks;
        _loading = false;
        if (_selectedProjectId != null &&
            !projects.any((p) => _projectId(p) == _selectedProjectId)) {
          _selectedProjectId = null;
        }
      });
      await _loadProjectMetaForTasks(tasks);
    } else {
      setState(() => _loading = false);
      if (!silent) {
        AppToast.error(context, result['error']?.toString() ?? 'Could not load tasks');
      }
    }
  }

  int? _projectId(Map<String, dynamic> p) {
    final raw = p['id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  Future<void> _loadProjectMetaForTasks(List<dynamic> tasks) async {
    final ids = tasks.map(taskProjectIdFrom).whereType<int>().where((id) => id > 0).toSet();
    final missing = ids.where((id) => !_projectMeta.containsKey(id)).toList();
    if (missing.isEmpty) return;

    final results = await Future.wait(
      missing.map((pid) => widget.apiService.getProjectDetail(pid)),
    );

    if (!mounted) return;
    var changed = false;
    for (var i = 0; i < missing.length; i++) {
      final pid = missing[i];
      final r = results[i];
      if (r['success'] == true) {
        final data = r['data'] as Map<String, dynamic>? ?? {};
        _projectMeta[pid] = _ProjectMeta(
          stages: data['stages'] as List? ?? [],
          employees: data['employees'] as List? ?? [],
        );
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  _ProjectMeta _metaForTask(dynamic task) {
    final pid = taskProjectIdFrom(task);
    if (pid == null) return const _ProjectMeta(stages: [], employees: []);
    return _projectMeta[pid] ?? const _ProjectMeta(stages: [], employees: []);
  }

  List<dynamic> get _scopedTasks {
    if (_selectedProjectId == null) return _tasks;
    return _tasks.where((t) => taskProjectIdFrom(t) == _selectedProjectId).toList();
  }

  List<dynamic> get _filteredTasks {
    final base = _scopedTasks;
    if (_filter == 'pending') {
      return base.where((t) => !taskIsCompleted(t)).toList();
    }
    if (_filter == 'completed') {
      return base.where((t) => taskIsCompleted(t)).toList();
    }
    return base;
  }

  int get _pendingCount => _scopedTasks.where((t) => !taskIsCompleted(t)).length;
  int get _completedCount => _scopedTasks.where((t) => taskIsCompleted(t)).length;

  int _countInProject(int? projectId) {
    Iterable<dynamic> list = _tasks;
    if (projectId != null) {
      list = list.where((t) => taskProjectIdFrom(t) == projectId);
    }
    if (_filter == 'pending') {
      return list.where((t) => !taskIsCompleted(t)).length;
    }
    if (_filter == 'completed') {
      return list.where((t) => taskIsCompleted(t)).length;
    }
    return list.length;
  }

  int _projectPct(Map<String, dynamic> p) {
    final total = (p['task_count'] as num?)?.toInt() ?? 0;
    final done = (p['completed_count'] as num?)?.toInt() ?? 0;
    if (total == 0) return 0;
    return ((done / total) * 100).round();
  }

  int get _overallPct {
    if (_tasks.isEmpty) return 0;
    final done = _tasks.where((t) => taskIsCompleted(t)).length;
    return ((done / _tasks.length) * 100).round();
  }

  String get _selectedProjectLabel {
    if (_selectedProjectId == null) return 'All Projects';
    for (final p in _projects) {
      if (_projectId(p) == _selectedProjectId) {
        return p['name']?.toString() ?? 'Project';
      }
    }
    return 'Project';
  }

  Future<void> _toggleTask(dynamic task) async {
    final id = taskIdFrom(task);
    if (id == null) return;
    final done = taskIsCompleted(task);
    final taskMap = task is Map ? Map<String, dynamic>.from(task) : null;
    final result = await widget.apiService.setTaskCompleted(
      id,
      completed: !done,
      task: taskMap,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      AppToast.success(context, done ? 'Task reopened' : 'Task completed');
      await _load(silent: true);
    } else {
      AppToast.updateFailed(context, result['error']?.toString());
    }
  }

  Future<void> _openProjectFilter() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppTheme.modalBarrierColor,
      builder: (ctx) {
        return AppTheme.glassBlur(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  const SizedBox(height: 14),
                  const Text(
                    'Filter by project',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _projectFilterTile(
                    ctx,
                    label: 'All Projects',
                    count: _countInProject(null),
                    pct: _overallPct,
                    selected: _selectedProjectId == null,
                    onTap: () {
                      setState(() => _selectedProjectId = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 6),
                  ..._projects.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _projectFilterTile(
                        ctx,
                        label: p['name']?.toString() ?? 'Project',
                        count: _countInProject(_projectId(p)),
                        pct: _projectPct(p),
                        selected: _selectedProjectId == _projectId(p),
                        onTap: () {
                          setState(() => _selectedProjectId = _projectId(p));
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _projectFilterTile(
    BuildContext ctx, {
    required String label,
    required int count,
    required int pct,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: selected
              ? AppTheme.loginInsetDecoration(borderRadius: 12, emphasized: true)
              : AppTheme.loginInsetDecoration(borderRadius: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  color: selected ? AppTheme.accent : AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: selected ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? AppTheme.accent : AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(dynamic task, {required double width, required bool compact}) {
    final meta = _metaForTask(task);
    return SizedBox(
      width: width,
      child: MyTaskCard(
        task: task is Map ? Map<String, dynamic>.from(task) : <String, dynamic>{},
        apiService: widget.apiService,
        onToggleComplete: () => _toggleTask(task),
        onUpdated: () => _load(silent: true),
        compactGrid: compact,
        stages: meta.stages,
        employees: meta.employees,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = Responsive.pagePadding(context);
    final displayTasks = _filteredTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 10, pad, 8),
          child: Container(
            decoration: AppTheme.loginShell().copyWith(borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SizedBox(width: 148, child: _buildProjectFilterButton()),
                      const SizedBox(width: 8),
                      _filterChip('To do', 'pending', '$_pendingCount'),
                      const SizedBox(width: 6),
                      _filterChip('Done', 'completed', '$_completedCount'),
                      const SizedBox(width: 6),
                      _filterChip('All', 'all', '${_scopedTasks.length}'),
                      const SizedBox(width: 6),
                      _reloadButton(),
                    ],
                  ),
                ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryBright),
                )
              : displayTasks.isEmpty
                  ? _buildEmptyState()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = Responsive.taskGridColumns(context);
                        const gap = 10.0;
                        final itemWidth = cols == 1
                            ? constraints.maxWidth
                            : (constraints.maxWidth - gap * (cols - 1)) / cols;
                        final compact = Responsive.useTaskGrid(context);

                        return SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(pad, 0, pad, 88),
                          child: Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final task in displayTasks)
                                _buildTaskCard(task, width: itemWidth, compact: compact),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildProjectFilterButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openProjectFilter,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: AppTheme.loginInsetDecoration(borderRadius: 10),
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded, size: 16, color: AppTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _selectedProjectLabel,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: AppTheme.textMuted.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value, String count) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: AppTheme.loginInsetDecoration(
          borderRadius: 10,
          emphasized: active,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? AppTheme.textPrimary : AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              count,
              style: TextStyle(
                color: active ? AppTheme.accent : AppTheme.textMuted.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reloadButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _loading ? null : () => _load(),
        customBorder: const CircleBorder(),
        child: Ink(
          width: 34,
          height: 34,
          decoration: AppTheme.loginInsetDecoration(borderRadius: 17),
          child: Icon(
            Icons.refresh_rounded,
            size: 18,
            color: _loading
                ? AppTheme.textMuted.withValues(alpha: 0.4)
                : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.12),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.assignment_outlined, color: AppTheme.accent, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              _filter == 'pending' ? 'No tasks to do' : 'No tasks here',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _filter == 'pending'
                  ? 'Assigned tasks will show up here.'
                  : 'Try another filter or project.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
