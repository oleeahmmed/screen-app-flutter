// tasks_page.dart — My Task (dashboard glass theme, simple list)

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/platform_capabilities.dart';
import '../utils/responsive.dart';
import '../utils/task_helpers.dart';
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
  /// null = all stages; only used when a project is selected.
  /// Use `_unstagedSelected` for tasks with no stage.
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
      await _loadProjectMetaForTasks(tasks);
    } else {
      setState(() => _loading = false);
      if (!silent) {
        AppToast.error(context, result['error']?.toString() ?? 'Could not load tasks');
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
      return cached == null || cached.employees.isEmpty || cached.stages.isEmpty;
    }).toList();
    if (missing.isEmpty) return;

    final results = await Future.wait(
      missing.map((pid) async {
        final detail = await widget.apiService.getProjectDetail(pid);
        final employees = await _loadEmployeesForProject(pid);
        return {'pid': pid, 'detail': detail, 'employees': employees};
      }),
    );

    if (!mounted) return;
    var changed = false;
    for (final bundle in results) {
      final pid = bundle['pid'] as int;
      final detail = bundle['detail'] as Map<String, dynamic>;
      if (detail['success'] == true) {
        final data = detail['data'] as Map<String, dynamic>? ?? {};
        _projectMeta[pid] = _ProjectMeta(
          stages: data['stages'] as List? ?? [],
          employees: bundle['employees'] as List<dynamic>,
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

  /// Stages where this user has assigned tasks in the selected project.
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

    // Fallback: derive from assigned tasks if API has no stages yet.
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
    final mobile = PlatformCapabilities.immersiveChatChrome || Responsive.isMobile(context);

    final bottomSpace = Responsive.bottomNavInset(context) + 72;

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 6, pad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSearchBox(),
              const SizedBox(height: 6),
              _statusSegment(),
              if (selectedProjectName != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text(selectedProjectName),
                    avatar: const Icon(Icons.folder_outlined, size: 16),
                    onDeleted: () => setState(() {
                      _selectedProjectId = null;
                      _clearStageFilter();
                    }),
                    deleteIconColor: AppTheme.textMuted,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.14),
                    side: BorderSide(color: AppTheme.primaryBright.withValues(alpha: 0.3)),
                    labelStyle: const TextStyle(
                      color: AppTheme.primaryBright,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                if (stages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _stageChips(stages),
                ],
              ],
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryBright),
                      )
                    : RefreshIndicator(
                        color: AppTheme.primaryBright,
                        backgroundColor: AppTheme.surface,
                        onRefresh: () => _load(),
                        child: displayTasks.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.only(bottom: bottomSpace),
                                children: [
                                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
                                  _buildEmptyState(stageFilterActive: stageFilterActive),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  const gap = 10.0;
                                  final available = constraints.maxWidth.clamp(0.0, double.infinity);
                                  final cols = mobile ? 1 : Responsive.taskGridColumnsForWidth(available);
                                  final itemWidth = cols == 1
                                      ? available
                                      : (((available - gap * (cols - 1)) / cols) - 0.5)
                                          .clamp(120.0, available);
                                  final compact = cols > 1;

                                  if (mobile) {
                                    return ListView.separated(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsets.only(bottom: bottomSpace),
                                      itemCount: displayTasks.length,
                                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                                      itemBuilder: (_, i) => _buildTaskCard(
                                        displayTasks[i],
                                        width: itemWidth,
                                        compact: false,
                                      ),
                                    );
                                  }

                                  return SingleChildScrollView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.only(bottom: bottomSpace),
                                    child: Wrap(
                                      spacing: gap,
                                      runSpacing: gap,
                                      children: [
                                        for (final task in displayTasks)
                                          _buildTaskCard(
                                            task,
                                            width: itemWidth,
                                            compact: compact,
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
        ),
        Positioned(
          right: pad,
          bottom: Responsive.bottomNavInset(context) + 12,
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            child: InkWell(
              onTap: _openCreateTask,
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5B9CFF), Color(0xFF3B82F6)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
        ),
      ],
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

  Widget _stageChips(List<Map<String, dynamic>> stages) {
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
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.1),
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
                  const SizedBox(width: 6),
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
      height: 36,
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
            () {
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
            }(),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    final hasQuery = _searchQuery.trim().isNotEmpty;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(
          color: hasQuery
              ? AppTheme.primaryBright.withValues(alpha: 0.45)
              : AppTheme.primaryBright.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: hasQuery ? 0.18 : 0.08),
            blurRadius: hasQuery ? 14 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (hasQuery ? AppTheme.primaryBright : AppTheme.primary)
                  .withValues(alpha: 0.16),
            ),
            child: Icon(
              Icons.search_rounded,
              size: 15,
              color: hasQuery ? AppTheme.primaryBright : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: AppTheme.primaryBright,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search tasks…',
                hintStyle: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.62),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          if (hasQuery)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                  customBorder: const CircleBorder(),
                  child: Ink(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: AppTheme.textMuted.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }

  Widget _statusSegment() {
    final projectActive = _selectedProjectId != null;

    Widget tab(String label, String value, int count) {
      final active = _filter == value;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _filter = value),
          borderRadius: BorderRadius.circular(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '$label ($count)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? AppTheme.primaryBright : AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2.5,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: active ? AppTheme.primaryBright : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('To do', 'pending', _pendingCount),
        tab('Done', 'completed', _completedCount),
        tab('All', 'all', _searchScopedTasks.length),
        const SizedBox(width: 4),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openFiltersSheet,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 8),
              child: Icon(
                Icons.folder_outlined,
                size: 22,
                color: projectActive ? AppTheme.accent : AppTheme.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openFiltersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppTheme.modalBarrierColor,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            void apply(VoidCallback fn) {
              setState(fn);
              setModal(() {});
            }

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
                      const SizedBox(height: 6),
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
                              ctx,
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
                                  ctx,
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
              ),
            );
          },
        );
      },
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
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.12),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
              ),
              child: Icon(
                searching
                    ? Icons.search_off_rounded
                    : (filteredAway ? Icons.filter_alt_off_rounded : Icons.assignment_outlined),
                color: AppTheme.accent,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              searching
                  ? 'No matching tasks'
                  : (filteredAway
                      ? 'Nothing in this filter'
                      : (_filter == 'pending' ? 'No tasks to do' : 'No tasks here')),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
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
                          ? 'Assigned tasks will show up here.'
                          : 'Switch to To do to see open work.')),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
            ),
            if (searching || filteredAway) ...[
              const SizedBox(height: 14),
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
