// tasks_page.dart — My Tasks (responsive redesign)

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/platform_capabilities.dart';
import '../utils/responsive.dart';
import '../utils/task_helpers.dart';
import '../widgets/app_logo.dart';
import '../widgets/create_task_sheet.dart';
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
  int? _selectedStageId;
  bool _unstagedSelected = false;
  Timer? _refreshTimer;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearStageFilter() {
    _selectedStageId = null;
    _unstagedSelected = false;
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
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
            _clearStageFilter();
          } else if (_selectedProjectId != null) {
            _pruneStageSelection();
          }
        });
        unawaited(_loadProjectMetaForTasks(tasks));
      } else {
        setState(() => _loading = false);
        if (!silent) {
          AppToast.error(context, result['error']?.toString() ?? 'Could not load tasks');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        AppToast.error(context, 'Could not load tasks');
      }
    }
  }

  void _pruneStageSelection() {
    if (_selectedProjectId == null) {
      _clearStageFilter();
      return;
    }
    if (!_unstagedSelected && _selectedStageId == null) return;
    final stages = _stagesForSelectedProject();
    final stillValid = stages.any((s) {
      final id = s['id'];
      if (_unstagedSelected) return id == null;
      return id is int && id == _selectedStageId;
    });
    if (!stillValid) _clearStageFilter();
  }

  int? _projectId(Map<String, dynamic> p) {
    final raw = p['id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  Future<List<dynamic>> _loadEmployeesForProject(int projectId) async {
    final assignable = await widget.apiService.getProjectAssignableEmployees(projectId);
    if (assignable['success'] == true) {
      final list = assignable['data'] as List? ?? [];
      if (list.isNotEmpty) {
        return normalizeProjectEmployeesList(list);
      }
    }

    final detail = await widget.apiService.getProjectDetail(projectId);
    if (detail['success'] == true) {
      final data = detail['data'] as Map<String, dynamic>? ?? {};
      final employees = data['employees'] as List? ?? [];
      if (employees.isNotEmpty) {
        return normalizeProjectEmployeesList(employees);
      }
      final members = data['project_members'] as List? ?? [];
      if (members.isNotEmpty) {
        return normalizeProjectEmployeesList(
          members
              .map((m) => {
                    'user_id': m['user_id'],
                    'full_name': m['username'],
                    'username': m['username'],
                  })
              .toList(),
        );
      }
    }
    return const [];
  }

  Future<void> _loadProjectMetaForTasks(List<dynamic> tasks) async {
    final ids = tasks.map(taskProjectIdFrom).whereType<int>().where((id) => id > 0).toSet();
    final missing = ids.where((id) {
      final cached = _projectMeta[id];
      return cached == null || cached.employees.isEmpty;
    }).take(4).toList();
    if (missing.isEmpty) return;

    for (final pid in missing) {
      if (!mounted) return;
      final employees = await _loadEmployeesForProject(pid);
      if (!mounted) return;
      final stages = _stagesFromProjectList(pid);
      _projectMeta[pid] = _ProjectMeta(stages: stages, employees: employees);
      if (mounted) setState(() {});
    }
  }

  List<dynamic> _stagesFromProjectList(int projectId) {
    for (final p in _projects) {
      if (_projectId(p) == projectId) {
        return p['stages'] as List? ?? [];
      }
    }
    return const [];
  }

  _ProjectMeta _metaForTask(dynamic task) {
    final pid = taskProjectIdFrom(task);
    if (pid == null) return const _ProjectMeta(stages: [], employees: []);
    final cached = _projectMeta[pid];
    final stages = cached?.stages.isNotEmpty == true
        ? cached!.stages
        : _stagesFromProjectList(pid);
    final employees = cached?.employees ?? const <dynamic>[];
    return _ProjectMeta(stages: stages, employees: employees);
  }

  List<dynamic> get _scopedTasks {
    if (_selectedProjectId == null) return _tasks;
    return _tasks.where((t) => taskProjectIdFrom(t) == _selectedProjectId).toList();
  }

  List<dynamic> get _stageScopedTasks {
    final base = _scopedTasks;
    if (_selectedProjectId == null) return base;
    if (_unstagedSelected) {
      return base.where((t) => taskStageIdFrom(t) == null).toList();
    }
    if (_selectedStageId != null) {
      return base.where((t) => taskStageIdFrom(t) == _selectedStageId).toList();
    }
    return base;
  }

  List<dynamic> get _searchScopedTasks {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _stageScopedTasks;
    return _stageScopedTasks.where((t) {
      final title = taskDisplayTitle(t).toLowerCase();
      final project = taskProjectNameFrom(t).toLowerCase();
      final stage = taskStageNameFrom(t).toLowerCase();
      final assignees = taskAssigneeListFrom(t)
          .map((p) => (p['name']?.toString() ?? '').toLowerCase())
          .join(' ');
      return title.contains(q) ||
          project.contains(q) ||
          stage.contains(q) ||
          assignees.contains(q);
    }).toList();
  }

  List<dynamic> get _filteredTasks {
    final base = _searchScopedTasks;
    if (_filter == 'pending') {
      return base.where((t) => !taskIsCompleted(t)).toList();
    }
    if (_filter == 'completed') {
      return base.where((t) => taskIsCompleted(t)).toList();
    }
    return base;
  }

  int get _pendingCount => _searchScopedTasks.where((t) => !taskIsCompleted(t)).length;
  int get _completedCount => _searchScopedTasks.where((t) => taskIsCompleted(t)).length;

  List<Map<String, dynamic>> _stagesForSelectedProject() {
    if (_selectedProjectId == null) return const [];

    Map<String, dynamic>? project;
    for (final p in _projects) {
      if (_projectId(p) == _selectedProjectId) {
        project = p;
        break;
      }
    }

    final apiStages = project?['stages'];
    if (apiStages is List && apiStages.isNotEmpty) {
      return apiStages
          .whereType<Map>()
          .map((s) => Map<String, dynamic>.from(s))
          .toList();
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final t in _scopedTasks) {
      final sid = taskStageIdFrom(t);
      final key = sid?.toString() ?? 'none';
      if (!byId.containsKey(key)) {
        byId[key] = {
          'id': sid,
          'name': sid == null
              ? 'No stage'
              : (taskStageNameFrom(t).isNotEmpty ? taskStageNameFrom(t) : 'Stage'),
          'task_count': 0,
        };
      }
      byId[key]!['task_count'] = (byId[key]!['task_count'] as int) + 1;
    }
    final list = byId.values.toList();
    list.sort((a, b) {
      final ai = a['id'];
      final bi = b['id'];
      if (ai == null && bi != null) return 1;
      if (ai != null && bi == null) return -1;
      return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
    });
    return list;
  }

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

  int _stageTaskCount(Map<String, dynamic> stage) {
    final id = stage['id'];
    return _scopedTasks.where((t) {
      final sid = taskStageIdFrom(t);
      if (id == null) return sid == null;
      return sid == (id is int ? id : int.tryParse('$id'));
    }).length;
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

  Widget _buildTaskCard(
    dynamic task, {
    required double width,
    required MyTaskCardLayout layout,
  }) {
    final meta = _metaForTask(task);
    return SizedBox(
      width: width,
      child: MyTaskCard(
        task: task is Map ? Map<String, dynamic>.from(task) : <String, dynamic>{},
        apiService: widget.apiService,
        onToggleComplete: () => _toggleTask(task),
        onUpdated: () => _load(silent: true),
        layout: layout,
        stages: meta.stages,
        employees: meta.employees,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final immersive = PlatformCapabilities.immersiveChatChrome;
    final sidePad = Responsive.isMobile(context) ? 14.0 : 18.0;
    final displayTasks = _filteredTasks;
    final selectedProjectName = () {
      if (_selectedProjectId == null) return null;
      for (final p in _projects) {
        if (_projectId(p) == _selectedProjectId) {
          return p['name']?.toString() ?? 'Project';
        }
      }
      return null;
    }();
    final stages = _stagesForSelectedProject();
    final stageFilterActive = _unstagedSelected || _selectedStageId != null;
    // Width-based only — Windows/Linux also set immersiveChatChrome, so do not
    // force list layout on wide resized desktop windows.
    final bottomInset = immersive
        ? MediaQuery.paddingOf(context).bottom
        : Responsive.bottomNavInset(context);
    final fabBottom = bottomInset + 12;
    final showFab = !immersive || Responsive.isDesktop(context);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: immersive,
        bottom: false,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroHeader(immersive, sidePad),
                Padding(
                  padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSearchField(),
                      const SizedBox(height: 10),
                      _buildSegmentedFilter(),
                    ],
                  ),
                ),
                if (selectedProjectName != null) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 8),
                    child: _buildProjectContext(selectedProjectName, stages),
                  ),
                ],
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: AppTheme.primaryBright),
                        )
                      : RefreshIndicator(
                          color: AppTheme.primaryBright,
                          backgroundColor: const Color(0xFF152238),
                          onRefresh: () => _load(),
                          child: displayTasks.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.only(bottom: fabBottom + 56),
                                  children: [
                                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.1),
                                    _buildEmptyState(stageFilterActive: stageFilterActive),
                                  ],
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    const gap = 10.0;
                                    final available =
                                        constraints.maxWidth.clamp(0.0, double.infinity);
                                    final cols = Responsive.taskGridColumnsForWidth(available);
                                    final useList = cols <= 1;

                                    if (useList) {
                                      return ListView.builder(
                                        physics: const AlwaysScrollableScrollPhysics(),
                                        padding: EdgeInsets.fromLTRB(
                                          sidePad,
                                          2,
                                          sidePad,
                                          fabBottom + 56,
                                        ),
                                        itemCount: displayTasks.length,
                                        itemBuilder: (_, i) => _buildTaskCard(
                                          displayTasks[i],
                                          width: available,
                                          layout: MyTaskCardLayout.list,
                                        ),
                                      );
                                    }

                                    final itemWidth =
                                        (((available - gap * (cols - 1)) / cols) - 0.5)
                                            .clamp(120.0, available);

                                    return SingleChildScrollView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsets.fromLTRB(
                                        sidePad,
                                        2,
                                        sidePad,
                                        fabBottom + 56,
                                      ),
                                      child: Wrap(
                                        spacing: gap,
                                        runSpacing: gap,
                                        children: [
                                          for (final task in displayTasks)
                                            _buildTaskCard(
                                              task,
                                              width: itemWidth,
                                              layout: MyTaskCardLayout.grid,
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                ),
              ],
            ),
            if (showFab)
              Positioned(
                right: sidePad,
                bottom: fabBottom,
                child: _fab(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(bool immersive, double sidePad) {
    final projectActive = _selectedProjectId != null;
    final subtitle = _loading
        ? 'Loading…'
        : '$_pendingCount open · $_completedCount done';

    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad, immersive ? 6 : 10, sidePad, 10),
      child: Row(
        children: [
          if (immersive)
            IconButton(
              tooltip: 'Home',
              onPressed: () => AppNavigation.instance.goHome(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppTheme.textPrimary),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          _ProgressRing(pct: _overallPct, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Tasks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.95),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _HeaderIcon(
            tooltip: 'Filter by project',
            icon: Icons.folder_outlined,
            active: projectActive,
            onTap: _openFiltersSheet,
          ),
          _HeaderIcon(
            tooltip: 'Refresh',
            icon: Icons.refresh_rounded,
            onTap: () => _load(),
          ),
          if (immersive)
            _HeaderIcon(
              tooltip: 'New task',
              icon: Icons.add_rounded,
              active: true,
              onTap: _openCreateTask,
            ),
          if (immersive)
            Tooltip(
              message: 'Dashboard',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => AppNavigation.instance.goHome(),
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: AppLogo(size: 28, showBorder: false),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _searchQuery = v),
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      cursorColor: AppTheme.primaryBright,
      decoration: InputDecoration(
        hintText: 'Search tasks, projects, people…',
        hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7), fontSize: 13.5),
        prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMuted.withValues(alpha: 0.8), size: 20),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                onPressed: () => setState(() {
                  _searchCtrl.clear();
                  _searchQuery = '';
                }),
                icon: Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted.withValues(alpha: 0.8)),
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primaryBright.withValues(alpha: 0.45)),
        ),
      ),
    );
  }

  Widget _buildSegmentedFilter() {
    Widget seg(String label, String value, int count) {
      final active = _filter == value;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _filter = value),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: active ? AppTheme.primary.withValues(alpha: 0.28) : Colors.transparent,
              ),
              child: Text(
                '$label $count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? AppTheme.textPrimary : AppTheme.textMuted,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          seg('To do', 'pending', _pendingCount),
          seg('Done', 'completed', _completedCount),
          seg('All', 'all', _searchScopedTasks.length),
        ],
      ),
    );
  }

  Widget _buildProjectContext(String projectName, List<Map<String, dynamic>> stages) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() {
                _selectedProjectId = null;
                _clearStageFilter();
              }),
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: AppTheme.primary.withValues(alpha: 0.14),
                  border: Border.all(color: AppTheme.primaryBright.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_outlined, size: 14, color: AppTheme.primaryBright),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.primaryBright,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.close_rounded, size: 15, color: AppTheme.textMuted.withValues(alpha: 0.9)),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (stages.isNotEmpty) ...[
          const SizedBox(height: 8),
          _stageRail(stages),
        ],
      ],
    );
  }

  Widget _stageRail(List<Map<String, dynamic>> stages) {
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      int? count,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.04),
              border: Border.all(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppTheme.accent : AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: selected
                          ? AppTheme.accent
                          : AppTheme.textMuted.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final allSelected = !_unstagedSelected && _selectedStageId == null;

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(
            label: 'All stages',
            selected: allSelected,
            count: _scopedTasks.length,
            onTap: () => setState(_clearStageFilter),
          ),
          const SizedBox(width: 6),
          for (final stage in stages) ...[
            Builder(
              builder: (_) {
                final rawId = stage['id'];
                final stageId = rawId == null
                    ? null
                    : (rawId is int ? rawId : int.tryParse('$rawId'));
                final selected = rawId == null
                    ? _unstagedSelected
                    : (!_unstagedSelected && _selectedStageId == stageId);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: chip(
                    label: stage['name']?.toString() ?? 'Stage',
                    selected: selected,
                    count: _stageTaskCount(stage),
                    onTap: () => setState(() {
                      if (rawId == null) {
                        _unstagedSelected = true;
                        _selectedStageId = null;
                      } else {
                        _unstagedSelected = false;
                        _selectedStageId = stageId;
                      }
                    }),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _fab() {
    return Material(
      color: Colors.transparent,
      elevation: 4,
      shadowColor: AppTheme.accent.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: _openCreateTask,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accent,
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Color(0xFF0A1628), size: 28),
        ),
      ),
    );
  }

  Future<void> _openCreateTask() async {
    final ok = await showCreateTaskSheet(
      context: context,
      apiService: widget.apiService,
      projects: _projects,
      initialProjectId: _selectedProjectId,
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _openFiltersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF152238),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            void apply(VoidCallback fn) {
              setState(fn);
              setModal(() {});
            }

            return SafeArea(
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
                          color: Colors.white.withValues(alpha: 0.2),
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
                    const SizedBox(height: 4),
                    Text(
                      'Then pick a stage from that project',
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * 0.48,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          _projectFilterTile(
                            label: 'All Projects',
                            count: _countInProject(null),
                            pct: _overallPct,
                            selected: _selectedProjectId == null,
                            onTap: () {
                              apply(() {
                                _selectedProjectId = null;
                                _clearStageFilter();
                              });
                              Navigator.pop(ctx);
                            },
                          ),
                          const SizedBox(height: 6),
                          ..._projects.map(
                            (p) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _projectFilterTile(
                                label: p['name']?.toString() ?? 'Project',
                                count: _countInProject(_projectId(p)),
                                pct: _projectPct(p),
                                selected: _selectedProjectId == _projectId(p),
                                onTap: () {
                                  apply(() {
                                    final next = _projectId(p);
                                    if (_selectedProjectId != next) {
                                      _clearStageFilter();
                                    }
                                    _selectedProjectId = next;
                                  });
                                  Navigator.pop(ctx);
                                },
                              ),
                            ),
                          ),
                        ],
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
  }

  Widget _projectFilterTile({
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryBright.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
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
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.accent : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? const Color(0xFF0A1628) : AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool stageFilterActive}) {
    final searching = _searchQuery.trim().isNotEmpty;
    final filteredAway = _tasks.isNotEmpty && _filteredTasks.isEmpty;
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
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.12),
                border: Border.all(color: AppTheme.primaryBright.withValues(alpha: 0.22)),
              ),
              child: Icon(
                searching
                    ? Icons.search_off_rounded
                    : (filteredAway ? Icons.filter_alt_off_rounded : LucideIcons.listChecks),
                color: AppTheme.primaryBright,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              searching
                  ? 'No matching tasks'
                  : (filteredAway
                      ? 'Nothing in this filter'
                      : (_filter == 'pending' ? 'All clear' : 'No tasks here')),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try another keyword, or clear search.'
                  : (filteredAway
                      ? (stageFilterActive
                          ? 'Try All stages, or clear the project filter.'
                          : 'Try All, or clear the project filter.')
                      : (_filter == 'pending'
                          ? 'Assigned work will show up here.'
                          : 'Switch to To do to see open work.')),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
            ),
            if (searching || filteredAway) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() {
                  if (searching) {
                    _searchCtrl.clear();
                    _searchQuery = '';
                  } else {
                    _filter = 'pending';
                    _selectedProjectId = null;
                    _clearStageFilter();
                  }
                }),
                child: Text(searching ? 'Clear search' : 'Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  const _HeaderIcon({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: 22,
        color: active ? AppTheme.primaryBright : AppTheme.textMuted,
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final int pct;
  final double size;

  const _ProgressRing({required this.pct, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final t = (pct.clamp(0, 100)) / 100.0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: t),
        child: Center(
          child: Text(
            '$pct%',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: size * 0.22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;

  _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final bg = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = AppTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
