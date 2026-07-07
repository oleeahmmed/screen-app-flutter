// tasks_page.dart — My Task: project tabs + assigned tasks with update/complete

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

class _TasksPageState extends State<TasksPage> {
  List<Map<String, dynamic>> _projects = [];
  List<dynamic> _tasks = [];
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

  @override
  Widget build(BuildContext context) {
    final pad = Responsive.pagePadding(context);
    final displayTasks = _filteredTasks;
    final showProjectOnCard = _selectedProjectId == null && _projects.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Task',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tasks assigned to you, grouped by project',
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                color: AppTheme.textMuted,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        if (_projects.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _buildProjectTabs(pad),
          ),
        if (_tasks.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
            child: _buildSummaryCard(),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Row(
            children: [
              _filterTab('To do', 'pending', '$_pendingCount'),
              const SizedBox(width: 8),
              _filterTab('Done', 'completed', '$_completedCount'),
              const SizedBox(width: 8),
              _filterTab('All', 'all', '${_scopedTasks.length}'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryBright),
                )
              : displayTasks.isEmpty
                  ? _buildEmptyState()
                  : _buildTaskList(
                      context,
                      displayTasks,
                      pad,
                      showProjectOnCard,
                    ),
        ),
      ],
    );
  }

  Widget _buildTaskList(
    BuildContext context,
    List<dynamic> displayTasks,
    double pad,
    bool showProjectOnCard,
  ) {
    if (Responsive.useTaskGrid(context)) {
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 88),
        gridDelegate: Responsive.taskGridDelegate(context),
        itemCount: displayTasks.length,
        itemBuilder: (ctx, i) => _taskCardAt(
          displayTasks[i],
          showProjectOnCard: showProjectOnCard,
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 88),
      itemCount: displayTasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => _taskCardAt(
        displayTasks[i],
        showProjectOnCard: showProjectOnCard,
      ),
    );
  }

  Widget _taskCardAt(
    dynamic task, {
    required bool showProjectOnCard,
  }) {
    final map = task is Map ? Map<String, dynamic>.from(task) : <String, dynamic>{};
    final dense = Responsive.useTaskGrid(context);
    return MyTaskCard(
      task: map,
      apiService: widget.apiService,
      showProjectName: showProjectOnCard,
      dense: dense,
      onToggleComplete: () => _toggleTask(task),
      onUpdated: () => _load(silent: true),
    );
  }

  Widget _buildProjectTabs(double pad) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad),
        children: [
          _projectChip(
            label: 'All projects',
            count: _countInProject(null),
            selected: _selectedProjectId == null,
            onTap: () => setState(() => _selectedProjectId = null),
          ),
          for (final p in _projects) ...[
            const SizedBox(width: 8),
            _projectChip(
              label: p['name']?.toString() ?? 'Project',
              count: _countInProject(_projectId(p)),
              selected: _selectedProjectId == _projectId(p),
              onTap: () => setState(() => _selectedProjectId = _projectId(p)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _projectChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: AppTheme.taskFilterChip(active: selected),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 16,
                color: selected ? AppTheme.featureVault : AppTheme.textMuted,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: selected ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? AppTheme.featureVault : AppTheme.textMuted,
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

  Widget _buildSummaryCard() {
    final total = _scopedTasks.length;
    final pct = total == 0 ? 0 : ((_completedCount / total) * 100).round();
    final projectLabel = _selectedProjectId == null
        ? 'All projects'
        : _projects
                .firstWhere(
                  (p) => _projectId(p) == _selectedProjectId,
                  orElse: () => {'name': 'Project'},
                )['name']
                ?.toString() ??
            'Project';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.taskCardDecoration(borderRadius: 16),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: total == 0 ? 0 : _completedCount / total,
                  strokeWidth: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(AppTheme.featureVault),
                ),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  projectLabel,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$_pendingCount open · $_completedCount done',
                  style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _summaryPill('Open', '$_pendingCount', AppTheme.warning),
          const SizedBox(width: 8),
          _summaryPill('Done', '$_completedCount', AppTheme.success),
        ],
      ),
    );
  }

  Widget _summaryPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: AppTheme.taskFieldDecoration(borderRadius: 10),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _filterTab(String label, String value, String count) {
    final isActive = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: AppTheme.taskFilterChip(active: isActive),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppTheme.featureVault : AppTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: isActive ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count,
                style: TextStyle(
                  color: isActive ? AppTheme.featureVault : AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final projectName = _selectedProjectId == null
        ? null
        : _projects
            .firstWhere(
              (p) => _projectId(p) == _selectedProjectId,
              orElse: () => {'name': 'this project'},
            )['name']
            ?.toString();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.featureVault.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.featureVault.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.assignment_outlined, color: AppTheme.featureVault, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              _filter == 'pending' ? 'No open tasks' : 'No tasks here',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _filter == 'pending'
                  ? (projectName != null
                      ? 'You have no open tasks in $projectName.'
                      : 'Tasks assigned to you will appear here by project.')
                  : (projectName != null
                      ? 'No tasks in $projectName for this filter.'
                      : 'Try another filter to see your tasks.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
