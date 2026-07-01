import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_quick_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/task_status_dropdown.dart';
import '../widgets/kanban_assignee_picker.dart';
import '../widgets/project_vault_tab.dart';
import 'task_detail_page.dart';

int? _parseUserId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is Map) {
    return _parseUserId(v['id']);
  }
  return int.tryParse(v.toString());
}

String _displayStr(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is Map) {
    for (final key in ['full_name', 'name', 'username', 'email']) {
      final x = v[key];
      if (x != null && x.toString().trim().isNotEmpty) return x.toString();
    }
    return v['id']?.toString() ?? '';
  }
  return v.toString();
}

List<int> _taskAssigneeIds(Map<String, dynamic> task) {
  final raw = task['assignee_ids'];
  if (raw is List && raw.isNotEmpty) {
    return raw.map((e) => int.tryParse('$e')).whereType<int>().toList();
  }
  final uid = _parseUserId(task['user_id']);
  return uid != null ? [uid] : [];
}

List<Map<String, dynamic>> _taskAssigneeList(Map<String, dynamic> task) {
  final assignees = task['assignees'];
  if (assignees is List && assignees.isNotEmpty) {
    return assignees
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
  final ids = _taskAssigneeIds(task);
  if (ids.isEmpty) return [];
  final name = task['user_name']?.toString() ?? 'User';
  return ids.map((id) => {'id': id, 'name': name}).toList();
}

String _formatShortDate(String? iso) {
  if (iso == null || iso.length < 10) return '';
  try {
    final d = DateTime.parse(iso);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  } catch (_) {
    return iso.substring(0, 10);
  }
}

String _projectSubtitle(dynamic p) {
  final dept = _displayStr(p['department_name']);
  if (dept.isNotEmpty) return dept;
  final desc = _displayStr(p['description']);
  if (desc.isEmpty) return '';
  final first = desc.split('\n').first.trim();
  if (first.length <= 48) return first;
  return '${first.substring(0, 45)}...';
}

Widget _gradientProgressBar(double pct, {double height = 6}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Stack(
      children: [
        Container(height: height, color: Colors.white.withValues(alpha: 0.08)),
        FractionallySizedBox(
          widthFactor: (pct / 100).clamp(0.0, 1.0),
          child: Container(
            height: height,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.featureVault]),
            ),
          ),
        ),
      ],
    ),
  );
}

Color _avatarColorForName(String name) {
  const palette = [
    AppTheme.primary,
    AppTheme.success,
    AppTheme.warning,
    AppTheme.danger,
    AppTheme.featureVault,
    Color(0xFF06B6D4),
  ];
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h + c) % palette.length;
  }
  return palette[h];
}

/// Dedupes employees by id; if [currentUserId] is set but not in the project list, adds one menu row (API user id).
List<DropdownMenuItem<int?>> buildTaskAssigneeDropdownItems(
  List<dynamic> employees,
  Map<String, dynamic> task,
  int? currentUserId,
) {
  const unassignedStyle = TextStyle(color: AppTheme.textMuted, fontSize: 13);
  const itemStyle = TextStyle(color: Colors.white, fontSize: 13);
  final seen = <int>{};
  final items = <DropdownMenuItem<int?>>[
    DropdownMenuItem<int?>(value: null, child: Text('Unassigned', style: unassignedStyle)),
  ];
  for (final e in employees) {
    final id = _parseUserId(e['id']);
    if (id == null || seen.contains(id)) continue;
    seen.add(id);
    items.add(DropdownMenuItem<int?>(
      value: id,
      child: Text(
        _displayStr(e['full_name'] ?? e['username'] ?? id),
        style: itemStyle,
      ),
    ));
  }
  if (currentUserId != null && !seen.contains(currentUserId)) {
    final label = task['user_name']?.toString().trim();
    items.add(DropdownMenuItem<int?>(
      value: currentUserId,
      child: Text(
        (label != null && label.isNotEmpty) ? label : 'User #$currentUserId',
        style: itemStyle.copyWith(color: AppTheme.textPrimary),
      ),
    ));
  }
  return items;
}

int? coerceAssigneeDropdownValue(int? desired, List<DropdownMenuItem<int?>> items) {
  final allowed = items.map((e) => e.value).toSet();
  if (desired == null) return null;
  if (allowed.contains(desired)) return desired;
  return null;
}

/// Drag-and-drop payload for moving tasks between stages (Kanban).
class TaskDragPayload {
  final int taskId;
  /// `null` = task had no stage (unassigned).
  final int? sourceStageId;

  TaskDragPayload({required this.taskId, this.sourceStageId});
}

enum _ProjectTasksView { kanban, calendar, list }

class ProjectsPage extends StatefulWidget {
  final ApiService apiService;
  /// When true (Work hub tab), no full-screen gradient ??? matches web "list inside app shell".
  final bool embeddedInParent;

  const ProjectsPage({
    required this.apiService,
    this.embeddedInParent = false,
  });

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  List<dynamic> _projects = [];
  Map<String, dynamic>? _meta;
  bool _isLoading = true;
  bool _archived = false;
  String _sort = 'newest';
  int? _customerId;
  int? _userId;
  int? _projectDeptId;
  String _status = '';
  String _priority = '';
  late final TextEditingController _searchCtrl;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _loadMeta();
    _loadProjects();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final r = await widget.apiService.getProjectFiltersMeta();
    if (r['success'] == true && mounted) {
      setState(() => _meta = r['data'] as Map<String, dynamic>?);
    }
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    final r = await widget.apiService.getProjects(
      archived: _archived,
      customerId: _customerId,
      userId: _userId,
      projectDepartmentId: _projectDeptId,
      status: _status.isEmpty ? null : _status,
      priority: _priority.isEmpty ? null : _priority,
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      sort: _sort,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      final raw = r['data'];
      final list = raw is List ? raw.cast<dynamic>() : <dynamic>[];
      setState(() {
        _projects = list;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      final err = r['error'];
      if (mounted && err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
      }
    }
  }

  void _scheduleSearchReload() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _loadProjects();
    });
  }

  void _setArchived(bool v) {
    if (_archived == v) return;
    setState(() => _archived = v);
    _loadProjects();
  }

  void _resetFilters() {
    setState(() {
      _customerId = null;
      _userId = null;
      _projectDeptId = null;
      _status = '';
      _priority = '';
      _sort = 'newest';
      _searchCtrl.clear();
    });
    _loadProjects();
  }

  static int? _metaInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  List<Map<String, dynamic>> get _customers {
    final raw = _meta?['customers'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<Map<String, dynamic>> get _employees {
    final raw = _meta?['employees'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<Map<String, dynamic>> get _projectDepts {
    final raw = _meta?['project_departments'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  Color _stc(String s) {
    switch (s) {
      case 'active':
        return AppTheme.statusActive;
      case 'on_hold':
        return AppTheme.statusPending;
      case 'completed':
        return AppTheme.featureVault;
      case 'cancelled':
        return AppTheme.danger;
      default:
        return AppTheme.primary;
    }
  }

  Color _prc(String p) {
    switch (p) {
      case 'high':
      case 'critical':
        return AppTheme.priorityHigh;
      case 'medium':
        return AppTheme.priorityMedium;
      default:
        return AppTheme.priorityLow;
    }
  }
  void _showCreateProjectDialog() {
    final nc = TextEditingController();
    final dc = TextEditingController();
    final customers = _customers;
    int? customerId = customers.isNotEmpty ? _metaInt(customers.first['id']) : null;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
      backgroundColor: AppTheme.surface2, title: Text('New Project', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (customers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Add a customer in the web monitor before creating a project.',
              style: TextStyle(color: Colors.orange.shade200, fontSize: 12),
            ),
          )
        else ...[
          DropdownButtonFormField<int>(
            value: customerId,
            dropdownColor: AppTheme.surface2,
            decoration: InputDecoration(
              labelText: 'Customer *',
              labelStyle: TextStyle(color: AppTheme.textMuted),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
            items: customers
                .map((c) => DropdownMenuItem<int>(
                      value: _metaInt(c['id']),
                      child: Text('${c['name']}', style: TextStyle(color: Colors.white)),
                    ))
                .toList(),
            onChanged: (v) => setD(() => customerId = v),
          ),
          SizedBox(height: 12),
        ],
        _dtf(nc, 'Project Name *'), SizedBox(height: 12), _dtf(dc, 'Description', ml: 3)])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async {
          if (nc.text.trim().isEmpty || customerId == null) return;
          Navigator.pop(ctx);
          final r = await widget.apiService.createProject(
            name: nc.text.trim(),
            customerId: customerId!,
            description: dc.text.trim(),
          );
          if (!mounted) return;
          if (r['success'] != true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(r['error']?.toString() ?? 'Could not create project')),
            );
          }
          _loadProjects();
        }, style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.featureVault,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppTheme.textPrimary.withValues(alpha: 0.7),
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ), child: Text('Create'))],
        ),
      ),
    );
  }

  Widget _dtf(TextEditingController c, String h, {int ml=1}) => TextField(controller: c, maxLines: ml, style: TextStyle(color: Colors.white),
    decoration: InputDecoration(hintText: h, hintStyle: TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)));
  InputDecoration _searchDecoration() {
    return InputDecoration(
      hintText: widget.embeddedInParent ? 'Search projects…' : 'Search name, description, client…',
      hintStyle: TextStyle(
        color: widget.embeddedInParent ? AppTheme.textMuted : Colors.white30,
      ),
      prefixIcon: Icon(
        Icons.search,
        color: widget.embeddedInParent ? AppTheme.textMuted : Colors.white30,
        size: 20,
      ),
      filled: true,
      fillColor: widget.embeddedInParent
          ? AppTheme.surface2.withValues(alpha: 0.45)
          : Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    );
  }

  Widget _filterDropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T?>> items,
    required void Function(T?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<T?>(
        value: value,
        isExpanded: true,
        decoration: _searchDecoration(),
        dropdownColor: widget.embeddedInParent ? AppTheme.surface2 : AppTheme.surface2,
        style: TextStyle(
          color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white,
          fontSize: 14,
        ),
        hint: Text(
          hint,
          style: TextStyle(
            color: widget.embeddedInParent ? AppTheme.textMuted : AppTheme.textMuted,
            fontSize: 14,
          ),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _inlineFilterDropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T?>> items,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T?>(
      value: value,
      isExpanded: true,
      isDense: true,
      decoration: _searchDecoration().copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8)),
      dropdownColor: AppTheme.surface2,
      style: TextStyle(color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white, fontSize: 13),
      hint: Text(hint, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildEmbeddedFilterBar(double padH) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padH, 4, padH, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 760;
          final search = TextField(
            controller: _searchCtrl,
            onChanged: (_) => _scheduleSearchReload(),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: _searchDecoration(),
          );
          final status = _inlineFilterDropdown<String>(
            value: _status.isEmpty ? null : _status,
            hint: 'All Status',
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('All Status')),
              DropdownMenuItem(value: 'planning', child: Text('Planning')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'on_hold', child: Text('On hold')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
            ],
            onChanged: (v) {
              setState(() => _status = v ?? '');
              _loadProjects();
            },
          );
          final priority = _inlineFilterDropdown<String>(
            value: _priority.isEmpty ? null : _priority,
            hint: 'All Priority',
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('All Priority')),
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'high', child: Text('High')),
              DropdownMenuItem(value: 'critical', child: Text('Critical')),
            ],
            onChanged: (v) {
              setState(() => _priority = v ?? '');
              _loadProjects();
            },
          );
          final sort = _inlineFilterDropdown<String>(
            value: _sort,
            hint: 'Sort',
            items: const [
              DropdownMenuItem(value: 'newest', child: Text('Newest first')),
              DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
              DropdownMenuItem(value: 'name_asc', child: Text('Name A–Z')),
              DropdownMenuItem(value: 'name_desc', child: Text('Name Z–A')),
              DropdownMenuItem(value: 'progress_desc', child: Text('Progress high → low')),
              DropdownMenuItem(value: 'progress_asc', child: Text('Progress low → high')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _sort = v);
              _loadProjects();
            },
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: search),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: status),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: priority),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: sort),
                const SizedBox(width: 6),
                _iconBtn(Icons.add, AppTheme.primary, _showCreateProjectDialog),
                _iconBtn(Icons.refresh_rounded, AppTheme.surface2.withValues(alpha: 0.65), _loadProjects),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: status),
                  const SizedBox(width: 8),
                  Expanded(child: priority),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: sort),
                  const SizedBox(width: 8),
                  _iconBtn(Icons.add, AppTheme.primary, _showCreateProjectDialog),
                  const SizedBox(width: 6),
                  _iconBtn(Icons.refresh_rounded, AppTheme.surface2.withValues(alpha: 0.65), _loadProjects),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padH = widget.embeddedInParent ? Responsive.pagePadding(context) : 24.0;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(padH, widget.embeddedInParent ? 6 : 20, padH, 8),
      child: Row(
        children: [
          if (!widget.embeddedInParent)
            Icon(Icons.folder_open, color: AppTheme.featureVault, size: 28),
          if (!widget.embeddedInParent) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _archived ? 'Archived projects' : 'All projects',
                  style: TextStyle(
                    fontSize: widget.embeddedInParent ? 16 : 24,
                    fontWeight: FontWeight.bold,
                    color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white,
                  ),
                ),
                Text(
                  '${_projects.length} project${_projects.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (!_archived)
            _iconBtn(Icons.add, AppTheme.primary, _showCreateProjectDialog),
          if (!_archived) const SizedBox(width: 6),
          _iconBtn(Icons.refresh_rounded, AppTheme.surface2.withValues(alpha: 0.65), _loadProjects),
        ],
      ),
    );

    final archiveChips = Padding(
      padding: EdgeInsets.symmetric(horizontal: padH),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Active'),
            selected: !_archived,
            onSelected: (_) => _setArchived(false),
            selectedColor: AppTheme.primary.withValues(alpha: 0.35),
            labelStyle: TextStyle(
              color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white,
              fontSize: 13,
            ),
          ),
          ChoiceChip(
            label: const Text('Archived'),
            selected: _archived,
            onSelected: (_) => _setArchived(true),
            selectedColor: AppTheme.primary.withValues(alpha: 0.35),
            labelStyle: TextStyle(
              color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );

    final searchField = Padding(
      padding: EdgeInsets.symmetric(horizontal: padH),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (_) => _scheduleSearchReload(),
        style: TextStyle(
          color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white,
          fontSize: 14,
        ),
        decoration: _searchDecoration(),
      ),
    );

    final filtersPanel = Padding(
      padding: EdgeInsets.symmetric(horizontal: padH),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: !widget.embeddedInParent,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(
            'Filters',
            style: TextStyle(
              color: AppTheme.textPrimary.withValues(alpha: widget.embeddedInParent ? 0.9 : 0.7),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          children: [
            _filterDropdown<int>(
              value: _customerId,
              hint: 'Client',
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('All clients')),
                ..._customers.map(
                  (c) => DropdownMenuItem<int?>(
                    value: _metaInt(c['id']),
                    child: Text('${c['name'] ?? ''}', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _customerId = v);
                _loadProjects();
              },
            ),
            _filterDropdown<int>(
              value: _userId,
              hint: 'Team member',
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Anyone')),
                ..._employees.map(
                  (e) => DropdownMenuItem<int?>(
                    value: _metaInt(e['user_id']),
                    child: Text('${e['full_name'] ?? ''}', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _userId = v);
                _loadProjects();
              },
            ),
            _filterDropdown<int>(
              value: _projectDeptId,
              hint: 'Project department',
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('All departments')),
                ..._projectDepts.map(
                  (d) => DropdownMenuItem<int?>(
                    value: _metaInt(d['id']),
                    child: Text(
                      '${d['project_name'] ?? ''} ? ${d['name'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _projectDeptId = v);
                _loadProjects();
              },
            ),
            _filterDropdown<String>(
              value: _status.isEmpty ? null : _status,
              hint: 'Status',
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('Any status')),
                DropdownMenuItem(value: 'planning', child: Text('Planning')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'on_hold', child: Text('On hold')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              onChanged: (v) {
                setState(() => _status = v ?? '');
                _loadProjects();
              },
            ),
            _filterDropdown<String>(
              value: _priority.isEmpty ? null : _priority,
              hint: 'Priority',
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('Any priority')),
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
                DropdownMenuItem(value: 'critical', child: Text('Critical')),
              ],
              onChanged: (v) {
                setState(() => _priority = v ?? '');
                _loadProjects();
              },
            ),
            _filterDropdown<String>(
              value: _sort,
              hint: 'Sort',
              items: const [
                DropdownMenuItem(value: 'newest', child: Text('Newest first')),
                DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
                DropdownMenuItem(value: 'name_asc', child: Text('Name A–Z')),
                DropdownMenuItem(value: 'name_desc', child: Text('Name Z–A')),
                DropdownMenuItem(value: 'progress_desc', child: Text('Progress high → low')),
                DropdownMenuItem(value: 'progress_asc', child: Text('Progress low → high')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _sort = v);
                _loadProjects();
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _resetFilters,
                child: Text(
                  'Reset filters',
                  style: TextStyle(
                    color: widget.embeddedInParent ? AppTheme.primary : AppTheme.featureVault,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final scrollBody = CustomScrollView(
      slivers: widget.embeddedInParent
          ? [
              SliverToBoxAdapter(child: _buildEmbeddedFilterBar(padH)),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              _projectGridSliver(padH),
            ]
          : [
              SliverToBoxAdapter(child: header),
              SliverToBoxAdapter(child: archiveChips),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(child: searchField),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(child: filtersPanel),
              const SliverToBoxAdapter(child: SizedBox(height: 6)),
              _projectGridSliver(padH),
            ],
    );

    if (widget.embeddedInParent) {
      return scrollBody;
    }

    return Container(
      decoration: AppTheme.screenGradient(),
      child: SafeArea(child: scrollBody),
    );
  }

  Widget _iconBtn(IconData icon, Color bg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: bg == AppTheme.primary ? Colors.white : AppTheme.textMuted, size: 18),
        ),
      ),
    );
  }

  Widget _projectGridSliver(double padH) {
    if (_isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator(color: AppTheme.primaryBright)),
      );
    }
    if (_projects.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: EmptyState(
            icon: Icons.folder_open,
            title: _archived ? 'No archived projects' : 'No projects yet',
            subtitle: _archived ? null : 'Create a project or adjust your filters',
            iconColor: AppTheme.featureVault,
          ),
        ),
      );
    }
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(padH, 0, padH, 24),
      sliver: SliverGrid(
        gridDelegate: Responsive.projectGridDelegate(
          context,
          embedded: widget.embeddedInParent,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _projectCard(_projects[i]),
          childCount: _projects.length,
        ),
      ),
    );
  }

  Widget _statusPill(String st) {
    final color = _stc(st);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        st.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _priorityPill(String pri) {
    final color = _prc(pri);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          pri.toUpperCase(),
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _projectCard(dynamic p) {
    final comp = (p['completion_percentage'] ?? p['progress'] ?? 0).toDouble();
    final st = (p['status'] ?? 'planning').toString();
    final pri = (p['priority'] ?? 'medium').toString();
    final pid = p['id'] is int ? p['id'] as int : (p['id'] as num).toInt();
    final canArchive = p['can_archive'] == true;
    final isArc = p['is_archived'] == true;
    final totalTasks = (p['total_tasks'] ?? 0) as num;
    final doneTasks = (p['completed_tasks'] ?? 0) as num;
    final remaining = (totalTasks - doneTasks).clamp(0, 999999);
    final muted = widget.embeddedInParent ? AppTheme.textMuted : AppTheme.textMuted;
    final titleColor = widget.embeddedInParent ? AppTheme.textPrimary : Colors.white;
    final cardBg = widget.embeddedInParent
        ? AppTheme.surface2.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.06);
    final subtitle = _projectSubtitle(p);

    void openDetail() {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProjectDetailView(
            apiService: widget.apiService,
            projectId: pid,
            projectName: p['name']?.toString() ?? '',
          ),
        ),
      ).then((_) => _loadProjects());
    }

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: openDetail,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayStr(p['name']),
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(color: muted, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _stc(st).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _stc(st).withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            st.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(color: _stc(st), fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _prc(pri).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _prc(pri).withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(color: _prc(pri), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  pri.toUpperCase(),
                                  style: TextStyle(color: _prc(pri), fontSize: 10, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        if (canArchive)
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.more_vert, color: muted, size: 20),
                            color: widget.embeddedInParent ? AppTheme.surface2 : AppTheme.surface2,
                            onSelected: (v) async {
                              if (v == 'archive') {
                                final r = await widget.apiService.archiveProject(pid);
                                if (!mounted) return;
                                if (r['success'] == true) {
                                  _loadProjects();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('${r['error']}')),
                                  );
                                }
                              } else if (v == 'restore') {
                                final r = await widget.apiService.restoreProject(pid);
                                if (!mounted) return;
                                if (r['success'] == true) {
                                  _loadProjects();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('${r['error']}')),
                                  );
                                }
                              }
                            },
                            itemBuilder: (ctx) => [
                              if (!isArc)
                                const PopupMenuItem(value: 'archive', child: Text('Archive')),
                              if (isArc)
                                const PopupMenuItem(value: 'restore', child: Text('Restore')),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
                if (_displayStr(p['customer_name']).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Customer: ${_displayStr(p['customer_name'])}',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('Progress', style: TextStyle(color: muted, fontSize: 11)),
                    const Spacer(),
                    Text(
                      '${comp.toStringAsFixed(comp == comp.roundToDouble() ? 0 : 2)}%',
                      style: TextStyle(color: titleColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _gradientProgressBar(comp),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text('$totalTasks', style: TextStyle(color: titleColor, fontWeight: FontWeight.bold)),
                            Text('Total Tasks', style: TextStyle(color: muted, fontSize: 10)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text('$doneTasks', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold)),
                            Text('Done', style: TextStyle(color: muted, fontSize: 10)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text('$remaining', style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.bold)),
                            Text('Remaining', style: TextStyle(color: muted, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Start: ${_formatShortDate(p['start_date']?.toString())}',
                        style: TextStyle(color: muted, fontSize: 10),
                      ),
                    ),
                    Text(
                      'End: ${_formatShortDate(p['end_date']?.toString())}',
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
                if (_displayStr(p['project_manager'] ?? p['project_manager_name']).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Manager: ${_displayStr(p['project_manager'] ?? p['project_manager_name'])}',
                    style: TextStyle(color: muted, fontSize: 10),
                  ),
                ],
                const SizedBox(height: 14),
                Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: openDetail,
                    icon: const Icon(Icons.visibility_outlined, size: 16, color: AppTheme.primaryBright),
                    label: const Text(
                      'View Detail',
                      style: TextStyle(color: AppTheme.primaryBright, fontWeight: FontWeight.w600),
                    ),
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

class ProjectDetailView extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  final String projectName;
  /// When true (e.g. Work hub), hide back button ??? user switches project from parent menu.
  final bool embedded;
  /// Called after successful delete while [embedded] (parent should clear project selection).
  final VoidCallback? onEmbeddedProjectRemoved;

  const ProjectDetailView({
    required this.apiService,
    required this.projectId,
    required this.projectName,
    this.embedded = false,
    this.onEmbeddedProjectRemoved,
  });

  @override
  State<ProjectDetailView> createState() => _ProjectDetailViewState();
}

class _ProjectDetailViewState extends State<ProjectDetailView> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _project;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _loadError;
  late TabController _tabCtrl;
  DateTime _calMonth = DateTime.now();
  _ProjectTasksView _tasksView = _ProjectTasksView.kanban;
  late final TextEditingController _taskSearchCtrl;
  /// Horizontal Kanban board scroll — must be shared with [Scrollbar] for dragging/sync.
  final ScrollController _boardHScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _taskSearchCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _taskSearchCtrl.dispose();
    _boardHScrollController.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }
  Future<void> _load({bool silent = false}) async {
    final initial = _project == null;
    if (initial || !silent) {
      setState(() {
        _isLoading = initial;
        _isRefreshing = !initial && !silent;
        _loadError = null;
      });
    }
    final r = await widget.apiService.getProjectDetail(widget.projectId);
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _project = r['data'];
        _isLoading = false;
        _isRefreshing = false;
        _loadError = null;
      });
    } else {
      final err = r['error']?.toString() ?? 'Failed to load project';
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _loadError = err;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            action: SnackBarAction(label: 'Retry', onPressed: _load),
          ),
        );
      }
    }
  }

  Map<String, dynamic>? _snapshotProject() {
    if (_project == null) return null;
    return Map<String, dynamic>.from(_project!);
  }

  void _restoreProject(Map<String, dynamic>? snapshot) {
    if (snapshot == null || !mounted) return;
    setState(() => _project = snapshot);
  }

  void _moveTaskOptimistically(TaskDragPayload data, int targetStageId) {
    if (_project == null) return;
    final project = Map<String, dynamic>.from(_project!);
    Map<String, dynamic>? taskData;

    if (data.sourceStageId == null) {
      final unassigned = List<dynamic>.from(project['unassigned_tasks'] ?? []);
      final idx = unassigned.indexWhere((t) => t['id'] == data.taskId);
      if (idx >= 0) {
        taskData = Map<String, dynamic>.from(unassigned[idx] as Map);
        unassigned.removeAt(idx);
        project['unassigned_tasks'] = unassigned;
      }
    } else {
      final stages = List<dynamic>.from(project['stages'] ?? []);
      for (var i = 0; i < stages.length; i++) {
        final stage = Map<String, dynamic>.from(stages[i] as Map);
        if (stage['id'] == data.sourceStageId) {
          final tasks = List<dynamic>.from(stage['tasks'] ?? []);
          final idx = tasks.indexWhere((t) => t['id'] == data.taskId);
          if (idx >= 0) {
            taskData = Map<String, dynamic>.from(tasks[idx] as Map);
            tasks.removeAt(idx);
            stage['tasks'] = tasks;
            stages[i] = stage;
          }
          break;
        }
      }
      project['stages'] = stages;
    }

    if (taskData == null) return;
    taskData['stage_id'] = targetStageId;

    final stages = List<dynamic>.from(project['stages'] ?? []);
    for (var i = 0; i < stages.length; i++) {
      final stage = Map<String, dynamic>.from(stages[i] as Map);
      if (stage['id'] == targetStageId) {
        final tasks = List<dynamic>.from(stage['tasks'] ?? []);
        tasks.add(taskData);
        stage['tasks'] = tasks;
        stages[i] = stage;
        break;
      }
    }
    project['stages'] = stages;
    setState(() => _project = project);
  }

  Future<void> _showKanbanAssigneePicker(Map<String, dynamic> task) async {
    final taskMap = Map<String, dynamic>.from(task);
    final ids = await showKanbanAssigneePicker(
      context: context,
      employees: _employees,
      selectedIds: _taskAssigneeIds(taskMap),
    );
    if (ids == null || !mounted) return;
    final r = await widget.apiService.updateTaskAssignees(taskMap['id'] as int, ids);
    if (!mounted) return;
    if (r['success'] == true) {
      _load(silent: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not update assignees')),
      );
    }
  }

  Widget _buildAssigneeAvatars(Map<String, dynamic> task, {bool compact = true}) {
    final people = _taskAssigneeList(task);
    final radius = compact ? 11.0 : 14.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showKanbanAssigneePicker(task),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (people.isEmpty)
                CircleAvatar(
                  radius: radius,
                  backgroundColor: AppTheme.surface2,
                  child: Icon(Icons.person_add_alt_1, size: radius, color: AppTheme.textMuted),
                )
              else
                SizedBox(
                  width: radius * 2 + (people.length.clamp(1, 3) - 1) * (radius * 1.2),
                  height: radius * 2 + 4,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < people.length && i < 3; i++)
                        Positioned(
                          left: i * (radius * 1.15),
                          child: CircleAvatar(
                            radius: radius,
                            backgroundColor: _avatarColorForName(people[i]['name']?.toString() ?? ''),
                            child: Text(
                              (people[i]['name']?.toString() ?? '?').substring(0, 1).toUpperCase(),
                              style: TextStyle(color: Colors.white, fontSize: radius * 0.85, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      if (people.length > 3)
                        Positioned(
                          left: 3 * (radius * 1.15),
                          child: CircleAvatar(
                            radius: radius,
                            backgroundColor: AppTheme.surface2,
                            child: Text('+${people.length - 3}', style: TextStyle(color: Colors.white, fontSize: radius * 0.75)),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.add, size: compact ? 14 : 16, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
  bool get _isManager => _project?['is_manager'] == true;
  List<dynamic> get _employees {
    final emp = (_project?['employees'] as List?) ?? [];
    if (emp.isNotEmpty) return emp;
    final members = (_project?['project_members'] as List?) ?? [];
    return members
        .map((m) => {
              'id': m['user_id'],
              'user_id': m['user_id'],
              'full_name': m['username'],
              'username': m['username'],
            })
        .toList();
  }
  List<dynamic> get _stages => (_project?['stages'] as List?) ?? [];
  List<dynamic> get _calEvents => (_project?['calendar_events'] as List?) ?? [];
  Color _pc(String p) { switch(p){ case 'high': case 'critical': return AppTheme.danger; case 'medium': return AppTheme.warning; default: return AppTheme.success; } }
  Color _parseHex(String h) { try { return Color(int.parse(h.replaceFirst('#', '0xFF'))); } catch(_) { return AppTheme.primary; } }
  Widget _tf(TextEditingController c, String h, {int ml=1}) => TextField(controller: c, maxLines: ml, style: TextStyle(color: Colors.white),
    decoration: InputDecoration(hintText: h, hintStyle: TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)));
  void _showAddStageDialog() {
    final nc = TextEditingController(); String color = '#3B82F6';
    final cls = ['#3B82F6','#10B981','#F59E0B','#EF4444','#8B5CF6','#EC4899','#64748B','#06B6D4'];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: AppTheme.surface2, title: Text('Add Stage', style: TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [_tf(nc, 'Stage Name *'), SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: cls.map((c) => GestureDetector(onTap: () => setD(() => color = c),
          child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _parseHex(c), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 2))))).toList())]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async { if (nc.text.trim().isEmpty) return; Navigator.pop(ctx);
          await widget.apiService.createStage(widget.projectId, name: nc.text.trim(), color: color); _load();
        }, style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.featureVault,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppTheme.textPrimary.withValues(alpha: 0.7),
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ), child: Text('Add'))],
    )));
  }
  void _deleteStage(int sid, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: AppTheme.surface2,
      title: Text('Delete "$name"?', style: TextStyle(color: Colors.white)), content: Text('Tasks move to another stage.', style: TextStyle(color: AppTheme.textMuted)),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: TextStyle(color: Colors.red)))]));
    if (ok == true) { await widget.apiService.deleteStage(widget.projectId, sid); _load(); }
  }

  Future<void> _toggleTaskComplete(dynamic t) async {
    final r = await widget.apiService.toggleTask(t['id'] as int);
    if (!mounted) return;
    if (r['success'] == true) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not update task')),
      );
    }
  }

  Future<void> _deleteTask(dynamic t) async {
    final name = t['name']?.toString() ?? t['title']?.toString() ?? 'this task';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: Text('Delete task?', style: TextStyle(color: Colors.white)),
        content: Text('Delete "$name"? This cannot be undone.', style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.7))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final r = await widget.apiService.deleteTask(t['id'] as int);
    if (!mounted) return;
    if (r['success'] == true) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Task deleted')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not delete task')),
      );
    }
  }

  Future<void> _uploadTaskFileFromKanban(dynamic t) async {
    final taskId = t['id'] as int;
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    List<int>? bytes = f.bytes?.toList();
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null || f.name.isEmpty) return;
    final up = await widget.apiService.uploadTaskAttachment(taskId, bytes, f.name);
    if (!mounted) return;
    if (up['success'] == true) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File uploaded')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(up['error']?.toString() ?? 'Upload failed')),
      );
    }
  }

  Future<void> _showEditTaskKanban(dynamic t) async {
    final taskId = t['id'] as int;
    final r = await widget.apiService.getTask(taskId);
    if (!mounted) return;
    Map<String, dynamic> task;
    if (r['success'] == true && r['data'] != null) {
      task = Map<String, dynamic>.from(r['data'] as Map);
    } else {
      task = <String, dynamic>{
        'name': t['name'] ?? t['title'] ?? '',
        'description': t['description'] ?? '',
        'due_date': t['due_date'],
        'priority': t['priority'] ?? 'medium',
        'user': t['user_id'],
        'is_attachment_required': t['is_attachment_required'] == true,
      };
    }
    final nc = TextEditingController(text: task['name']?.toString() ?? '');
    final dc = TextEditingController(text: task['description']?.toString() ?? '');
    final dueC = TextEditingController(text: (task['due_date'] ?? '').toString());
    String pri = (task['priority'] ?? 'medium').toString();
    if (!['low', 'medium', 'high'].contains(pri)) pri = 'medium';
    final rawAssignee = _parseUserId(task['user']) ?? _parseUserId(task['user_id']);
    final assigneeMenuItems = buildTaskAssigneeDropdownItems(_employees, task, rawAssignee);
    int? assignee = coerceAssigneeDropdownValue(rawAssignee, assigneeMenuItems);
    bool attReq = task['is_attachment_required'] == true;
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit task', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tf(nc, 'Task name *'),
                SizedBox(height: 10),
                _tf(dc, 'Description', ml: 3),
                SizedBox(height: 10),
                _tf(dueC, 'Due date (YYYY-MM-DD)', ml: 1),
                SizedBox(height: 10),
                Row(
                  children: ['low', 'medium', 'high'].map((p) {
                    final sel = pri == p;
                    final c = _pc(p);
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setD(() => pri = p),
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: 3),
                          padding: EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? c.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: sel ? c : Colors.white12),
                          ),
                          child: Text(
                            p[0].toUpperCase() + p.substring(1),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: sel ? c : AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: attReq,
                        onChanged: (v) => setD(() => attReq = v ?? false),
                        activeColor: AppTheme.featureVault,
                        checkColor: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Attachment required to complete',
                        style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.7), fontSize: 13),
                      ),
                    ),
                  ],
                ),
                if (assigneeMenuItems.length > 1) ...[
                  SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        value: assignee,
                        hint: Text('Assign to...', style: TextStyle(color: Colors.white30, fontSize: 13)),
                        dropdownColor: AppTheme.surface2,
                        items: assigneeMenuItems,
                        onChanged: (v) => setD(() => assignee = v),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
            ElevatedButton(
              onPressed: () async {
                if (nc.text.trim().isEmpty) {
                  messenger.showSnackBar(const SnackBar(content: Text('Enter a task name')));
                  return;
                }
                final body = <String, dynamic>{
                  'name': nc.text.trim(),
                  'description': dc.text.trim(),
                  'priority': pri,
                  'is_attachment_required': attReq,
                };
                final d = dueC.text.trim();
                if (d.isNotEmpty) body['due_date'] = d;
                if (assignee != null) body['assignee_id'] = assignee;
                final nav = Navigator.of(dialogCtx);
                final res = await widget.apiService.updateTask(taskId, body);
                if (!mounted) return;
                if (res['success'] == true) {
                  nav.pop();
                  _load();
                } else {
                  messenger.showSnackBar(SnackBar(content: Text(res['error']?.toString() ?? 'Could not save')));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.featureVault,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppTheme.textPrimary.withValues(alpha: 0.7),
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTaskField(dynamic v) {
    if (v == null) return '???';
    final s = v.toString();
    return s.isEmpty ? '???' : s;
  }

  String _formatFileSize(dynamic bytes) {
    if (bytes == null) return '';
    final n = int.tryParse(bytes.toString());
    if (n == null || n <= 0) return '';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool _isImageFileName(String name) {
    final l = name.toLowerCase();
    return l.endsWith('.png') ||
        l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.gif') ||
        l.endsWith('.webp') ||
        l.endsWith('.bmp');
  }

  Future<void> _openAttachmentUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open file')));
    }
  }

  void _previewAttachment(BuildContext context, String? url, String fileName) {
    if (url == null || url.isEmpty) return;
    if (_isImageFileName(fileName)) {
      showDialog<void>(
        context: context,
        builder: (ctx) {
          final h = MediaQuery.of(ctx).size.height * 0.82;
          final w = MediaQuery.of(ctx).size.width * 0.95;
          return Dialog(
            backgroundColor: AppTheme.bgDeep,
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: w,
                height: h,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: AppTheme.surface2,
                      child: Row(
                        children: [
                          const Icon(Icons.image_outlined, color: AppTheme.featureVault, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fileName,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: InteractiveViewer(
                        minScale: 0.4,
                        maxScale: 5,
                        child: Center(
                          child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            loadingBuilder: (c, child, p) {
                              if (p == null) return child;
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(48),
                                  child: CircularProgressIndicator(color: AppTheme.featureVault),
                                ),
                              );
                            },
                            errorBuilder: (c, e, s) => const Padding(
                              padding: EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image_outlined, color: AppTheme.textMuted, size: 48),
                                  SizedBox(height: 8),
                                  Text('Could not load preview', style: TextStyle(color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                          ),
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
    } else {
      _openAttachmentUrl(url);
    }
  }

  Widget _taskDetailKvRow(String label, String value, {bool dense = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 8 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskDetailSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.featureVault.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppTheme.featureVault),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskDetailPanel({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildTaskAttachmentTile(BuildContext dialogCtx, dynamic att) {
    final name = att['file_name']?.toString() ?? 'file';
    final url = att['file_url']?.toString();
    final sizeStr = _formatFileSize(att['file_size']);
    final uploaded = att['uploaded_by_name']?.toString();
    final isImg = _isImageFileName(name);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        color: Colors.white.withOpacity(0.03),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isImg && url != null && url.isNotEmpty)
            GestureDetector(
              onTap: () => _previewAttachment(dialogCtx, url, name),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (c, w, p) {
                    if (p == null) return w;
                    return Container(
                      color: Colors.black26,
                      child: const Center(child: CircularProgressIndicator(color: AppTheme.featureVault, strokeWidth: 2)),
                    );
                  },
                  errorBuilder: (c, e, s) => Container(
                    color: Colors.white.withOpacity(0.06),
                    child: const Center(
                      child: Icon(Icons.hide_image_outlined, color: Colors.white24, size: 40),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isImg ? Icons.image_outlined : Icons.insert_drive_file_outlined,
                  color: AppTheme.featureVault,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (sizeStr.isNotEmpty || (uploaded != null && uploaded.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [if (sizeStr.isNotEmpty) sizeStr, if (uploaded != null && uploaded.isNotEmpty) '? $uploaded']
                                .join(' '),
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: url == null || url.isEmpty ? null : () => _previewAttachment(dialogCtx, url, name),
                  icon: const Icon(Icons.visibility_outlined, size: 16, color: AppTheme.primaryBright),
                  label: const Text('Preview', style: TextStyle(color: AppTheme.primaryBright, fontSize: 11, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                TextButton.icon(
                  onPressed: url == null || url.isEmpty ? null : () => _openAttachmentUrl(url),
                  icon: const Icon(Icons.download_outlined, size: 16, color: AppTheme.success),
                  label: const Text('Open', style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTaskDetailContent(
    BuildContext dialogCtx,
    Map<String, dynamic> task,
    List<dynamic> attachments,
  ) {
    final chips = <Widget>[
      _chip(_fmtTaskField(task['status']), AppTheme.primary),
      _chip(_fmtTaskField(task['priority']), AppTheme.warning),
      if (task['completed'] == true) _chip('Done', AppTheme.success),
    ];

    final shown = {
      'id', 'name', 'description', 'task_type', 'status', 'priority', 'completed',
      'project', 'project_name', 'stage', 'stage_name', 'user', 'user_id', 'user_name',
      'company', 'company_name', 'date', 'due_date', 'estimated_hours', 'actual_hours',
      'is_attachment_required', 'has_attachments', 'attachment_count',
      'subtask_count', 'completed_subtask_count', 'subtask_progress',
      'review_status', 'review_comment', 'submitted_at', 'reviewed_at',
      'created_at', 'updated_at', 'completed_at',
    };

    final extra = <Widget>[];
    for (final e in task.entries) {
      if (shown.contains(e.key)) continue;
      extra.add(_taskDetailKvRow(e.key, _fmtTaskField(e.value), dense: true));
    }

    return [
      Wrap(spacing: 8, runSpacing: 8, children: chips),
      const SizedBox(height: 8),
      _taskDetailSectionTitle('Overview', Icons.article_outlined),
      _taskDetailPanel(
        children: [
          _taskDetailKvRow('ID', _fmtTaskField(task['id'])),
          _taskDetailKvRow('Name', _fmtTaskField(task['name'])),
          _taskDetailKvRow('Description', _fmtTaskField(task['description'])),
          _taskDetailKvRow('Task type', _fmtTaskField(task['task_type'])),
        ],
      ),
      _taskDetailSectionTitle('Placement', Icons.folder_outlined),
      _taskDetailPanel(
        children: [
          _taskDetailKvRow('Project', _fmtTaskField(task['project_name'] ?? task['project'])),
          _taskDetailKvRow('Stage', _fmtTaskField(task['stage_name'] ?? task['stage'])),
          _taskDetailKvRow('Company', _fmtTaskField(task['company_name'] ?? task['company'])),
        ],
      ),
      _taskDetailSectionTitle('People & time', Icons.people_outline_rounded),
      _taskDetailPanel(
        children: [
          _taskDetailKvRow('Assignee', _fmtTaskField(task['user_name'] ?? task['user_id'] ?? task['user'])),
          _taskDetailKvRow('Date', _fmtTaskField(task['date'])),
          _taskDetailKvRow('Due date', _fmtTaskField(task['due_date'])),
          _taskDetailKvRow('Est. hours', _fmtTaskField(task['estimated_hours'])),
          _taskDetailKvRow('Actual hours', _fmtTaskField(task['actual_hours'])),
        ],
      ),
      _taskDetailSectionTitle('Attachments policy', Icons.policy_outlined),
      _taskDetailPanel(
        children: [
          _taskDetailKvRow('Required', _fmtTaskField(task['is_attachment_required'])),
          _taskDetailKvRow('Has files', _fmtTaskField(task['has_attachments'])),
          _taskDetailKvRow('Count', _fmtTaskField(task['attachment_count'])),
        ],
      ),
      _taskDetailSectionTitle('Subtasks', Icons.checklist_rounded),
      _taskDetailPanel(
        children: [
          _taskDetailKvRow(
            'Progress',
            '${_fmtTaskField(task['completed_subtask_count'])} / ${_fmtTaskField(task['subtask_count'])} ? ${_fmtTaskField(task['subtask_progress'])}%',
          ),
        ],
      ),
      _taskDetailSectionTitle('Review', Icons.rate_review_outlined),
      _taskDetailPanel(
        children: [
          _taskDetailKvRow('Status', _fmtTaskField(task['review_status'])),
          _taskDetailKvRow('Comment', _fmtTaskField(task['review_comment'])),
          _taskDetailKvRow('Submitted', _fmtTaskField(task['submitted_at'])),
          _taskDetailKvRow('Reviewed', _fmtTaskField(task['reviewed_at'])),
        ],
      ),
      _taskDetailSectionTitle('Files', Icons.attach_file_rounded),
      if (attachments.isEmpty)
        _taskDetailPanel(
          children: [
            Text(
              'No files uploaded yet.',
              style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
            ),
          ],
        )
      else
        ...attachments.map((a) => _buildTaskAttachmentTile(dialogCtx, a)),
      _taskDetailSectionTitle('Record', Icons.schedule_rounded),
      _taskDetailPanel(
        children: [
          _taskDetailKvRow('Created', _fmtTaskField(task['created_at'])),
          _taskDetailKvRow('Updated', _fmtTaskField(task['updated_at'])),
          _taskDetailKvRow('Completed at', _fmtTaskField(task['completed_at'])),
        ],
      ),
      if (extra.isNotEmpty) ...[
        _taskDetailSectionTitle('Extra fields', Icons.more_horiz_rounded),
        _taskDetailPanel(children: extra),
      ],
    ];
  }

  Widget _chip(String text, Color accent) {
    if (text == '???') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(color: accent.withOpacity(0.95), fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _showTaskViewKanban(dynamic t) async {
    _openTaskDetailPage(t);
  }

  void _openTaskDetailPage(dynamic t) {
    final customer = _project?['customer'];
    final customerName = _displayStr(_project?['customer_name']).isNotEmpty
        ? _displayStr(_project?['customer_name'])
        : (customer is Map ? _displayStr(customer['name']) : '');
    openTaskDetailPage(
      context,
      apiService: widget.apiService,
      taskId: t['id'] as int,
      projectId: widget.projectId,
      projectName: widget.projectName,
      customerName: customerName,
      initialTask: t is Map ? Map<String, dynamic>.from(t as Map) : null,
      employees: _employees,
      stages: _stages,
      isManager: _isManager,
      onClosed: () => _load(silent: true),
    );
  }

  void _showEditProjectDialog() {
    final nc = TextEditingController(text: _project?['name'] ?? '');
    final dc = TextEditingController(text: _project?['description'] ?? '');
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: AppTheme.surface2, title: Text('Edit Project', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [_tf(nc, 'Project Name *'), SizedBox(height: 10), _tf(dc, 'Description', ml: 3)])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async { if (nc.text.trim().isEmpty) return; Navigator.pop(ctx);
          await widget.apiService.updateProject(widget.projectId, {'name': nc.text.trim(), 'description': dc.text.trim()}); _load();
        }, style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.featureVault,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppTheme.textPrimary.withValues(alpha: 0.7),
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ), child: Text('Save'))],
    ));
  }
  void _deleteProject() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: AppTheme.surface2,
      title: Text('Delete Project?', style: TextStyle(color: Colors.white)),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: TextStyle(color: Colors.red)))]));
    if (ok == true) {
      await widget.apiService.deleteProject(widget.projectId);
      if (!mounted) return;
      if (widget.embedded && widget.onEmbeddedProjectRemoved != null) {
        widget.onEmbeddedProjectRemoved!();
      } else {
        Navigator.pop(context);
      }
    }
  }
  void _showCreateTaskInStageDialog(int stageId) {
    final nc = TextEditingController(); final dc = TextEditingController();
    String pri = 'medium'; List<int> assigneeIds = []; String? due;
    bool isAttReq = false; PlatformFile? pickedFile;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: AppTheme.surface2, title: Text('Create Task', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _tf(nc, 'Task Name *'), SizedBox(height: 10), _tf(dc, 'Description', ml: 2), SizedBox(height: 10),
        Row(
          children: ['low', 'medium', 'high'].map((p) {
            final s = pri == p;
            final c = _pc(p);
            return Expanded(
              child: GestureDetector(
                onTap: () => setD(() => pri = p),
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 3),
                  padding: EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: s ? c.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: s ? c : Colors.white12),
                  ),
                  child: Text(
                    p[0].toUpperCase() + p.substring(1),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s ? c : AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final ids = await showKanbanAssigneePicker(
              context: ctx,
              employees: _employees,
              selectedIds: assigneeIds,
            );
            if (ids != null) setD(() => assigneeIds = ids);
          },
          icon: Icon(Icons.group_add_outlined, color: AppTheme.featureVault, size: 18),
          label: Text(
            assigneeIds.isEmpty ? 'Assign people' : '${assigneeIds.length} assigned',
            style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.7)),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppTheme.featureVault.withOpacity(0.4)),
            minimumSize: Size(double.infinity, 42),
          ),
        ),
        SizedBox(height: 10),
        GestureDetector(onTap: () async {
          final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2030),
            builder: (c, ch) => Theme(data: ThemeData.dark().copyWith(colorScheme: ColorScheme.dark(primary: AppTheme.featureVault)), child: ch!));
          if (picked != null) setD(() => due = "${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}");
        }, child: Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [Icon(Icons.calendar_today, size: 16, color: AppTheme.textMuted), SizedBox(width: 8), Text(due ?? 'Due date', style: TextStyle(color: due != null ? Colors.white : Colors.white30, fontSize: 13))]))),
        SizedBox(height: 10),
        // Attachment Required checkbox
        Row(children: [
          SizedBox(width: 24, height: 24, child: Checkbox(value: isAttReq, onChanged: (v) => setD(() => isAttReq = v ?? false), activeColor: AppTheme.featureVault, checkColor: Colors.white)),
          SizedBox(width: 8), Text('Attachment Required', style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.7), fontSize: 13)),
        ]),
        SizedBox(height: 10),
        GestureDetector(
          onTap: () async { final r = await FilePicker.platform.pickFiles(allowMultiple: false); if (r != null && r.files.isNotEmpty) setD(() => pickedFile = r.files.first); },
          child: Container(width: double.infinity, padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: pickedFile != null ? AppTheme.featureVault : Colors.white12)),
            child: Row(children: [
              Icon(pickedFile != null ? Icons.check_circle : Icons.attach_file, color: pickedFile != null ? Color(0xFF22C55E) : AppTheme.textMuted, size: 20),
              SizedBox(width: 8), Expanded(child: Text(pickedFile?.name ?? 'Attach file', style: TextStyle(color: pickedFile != null ? Colors.white : Colors.white30, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (pickedFile != null) GestureDetector(onTap: () => setD(() => pickedFile = null), child: Icon(Icons.close, color: AppTheme.textMuted, size: 16)),
            ]))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async {
          if (nc.text.trim().isEmpty) return;
          Navigator.pop(ctx);
          List<int>? bytes; if (pickedFile != null && pickedFile!.path != null) bytes = await File(pickedFile!.path!).readAsBytes();
          await widget.apiService.createTask(name: nc.text.trim(), description: dc.text.trim(), priority: pri, dueDate: due, projectId: widget.projectId, stageId: stageId,
            assigneeIds: assigneeIds.isNotEmpty ? assigneeIds : null,
            isAttachmentRequired: isAttReq, attachmentBytes: bytes, attachmentName: pickedFile?.name); _load();
        }, style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.featureVault,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppTheme.textPrimary.withValues(alpha: 0.7),
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ), child: Text('Create'))],
    )));
  }
  @override
  Widget build(BuildContext context) {
    final stats = _project?['stats'] as Map<String, dynamic>? ?? {};
    final totalTasks = stats['total_tasks'] ?? 0;
    return Scaffold(
      body: Container(
        decoration: AppTheme.screenGradient(),
        child: SafeArea(
          child: _isLoading && _project == null
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBright))
              : _project == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_loadError ?? 'Failed to load', style: const TextStyle(color: AppTheme.textMuted), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          TextButton(onPressed: _load, child: const Text('Retry', style: TextStyle(color: Colors.white))),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        if (_isRefreshing)
                          const LinearProgressIndicator(
                            minHeight: 2,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation(AppTheme.featureVault),
                          ),
                        _buildHeader(),
                        TabBar(
                          controller: _tabCtrl,
                          indicatorColor: AppTheme.primary,
                          labelColor: Colors.white,
                          unselectedLabelColor: AppTheme.textMuted,
                          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          tabs: [
                            Tab(text: 'Tasks ($totalTasks)'),
                            const Tab(text: 'Vault'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabCtrl,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildTasksToolbar(),
                                  Expanded(child: _buildTasksContent()),
                                ],
                              ),
                              ProjectVaultTab(apiService: widget.apiService, projectId: widget.projectId),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
  Widget _buildHeader() {
    final p = _project!;
    final comp = (p['completion_percentage'] ?? 0).toDouble();
    final st = (p['status'] ?? 'planning').toString();
    final subtitle = _projectSubtitle(p);
    final s = p['stats'] as Map<String, dynamic>? ?? {};
    final total = (s['total_tasks'] ?? 0) as num;
    final done = (s['completed_tasks'] ?? 0) as num;
    final pending = (total - done).clamp(0, 999999);
    final pad = Responsive.pagePadding(context);

    Color statusColor(String status) {
      switch (status) {
        case 'active':
          return AppTheme.success;
        case 'planning':
          return AppTheme.primary;
        case 'on_hold':
          return AppTheme.warning;
        case 'completed':
          return AppTheme.featureVault;
        default:
          return AppTheme.textMuted;
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 10, pad, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.embedded) const AppBackButton(color: AppTheme.textMuted),
              if (!widget.embedded) const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _displayStr(p['name']),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: Responsive.isMobile(context) ? 17 : 20,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor(st).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor(st).withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            st.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(color: statusColor(st), fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const AppQuickMenuButton(iconColor: AppTheme.textMuted, iconSize: 20),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 22),
                color: AppTheme.surface2,
                onSelected: (v) {
                  if (v == 'add_stage') _showAddStageDialog();
                  else if (v == 'edit') _showEditProjectDialog();
                  else if (v == 'delete') _deleteProject();
                  else if (v == 'refresh') _load();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'add_stage', child: Text('Add Stage')),
                  const PopupMenuItem(value: 'edit', child: Text('Edit Project')),
                  const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                  if (_isManager) const PopupMenuItem(value: 'delete', child: Text('Delete Project', style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _headerStatPill('$pending', 'pending', AppTheme.warning),
                const SizedBox(width: 8),
                _headerStatPill('$done', 'completed', AppTheme.success),
                const SizedBox(width: 8),
                _headerStatPill('0', 'archived', AppTheme.textMuted),
                const SizedBox(width: 12),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: (comp / 100).clamp(0.0, 1.0),
                        strokeWidth: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                      ),
                      Text('${comp.toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStatPill(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTasksToolbar() {
    final pad = Responsive.pagePadding(context);
    final stageCount = _stages.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final search = TextField(
            controller: _taskSearchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search tasks…',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
              prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.35), size: 18),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          );
          final viewToggle = Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _viewToggle('Kanban', Icons.view_column, _ProjectTasksView.kanban),
                _viewToggle('Calendar', Icons.calendar_month, _ProjectTasksView.calendar),
                _viewToggle('List', Icons.view_list, _ProjectTasksView.list),
              ],
            ),
          );
          final addBtn = FilledButton.icon(
            onPressed: _showQuickAddTask,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Task'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          );
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archived tasks — use web monitor for full archive view'))),
                  icon: const Icon(Icons.archive_outlined, size: 16),
                  label: const Text('Archive'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textMuted, side: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                ),
                const SizedBox(width: 8),
                viewToggle,
                const SizedBox(width: 8),
                addBtn,
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showAddStageDialog,
                  icon: const Icon(Icons.account_tree_outlined, size: 16),
                  label: Text('Stages ($stageCount)'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textMuted, side: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    viewToggle,
                    const SizedBox(width: 8),
                    addBtn,
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _showAddStageDialog,
                      child: Text('Stages ($stageCount)'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _viewToggle(String label, IconData icon, _ProjectTasksView mode) {
    final active = _tasksView == mode;
    return Material(
      color: active ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => setState(() => _tasksView = mode),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? AppTheme.bgDeep : AppTheme.textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? AppTheme.bgDeep : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickAddTask() {
    if (_stages.isEmpty) {
      _showAddStageDialog();
      return;
    }
    final first = _stages.first;
    _showCreateTaskInStageDialog(first['id'] as int);
  }

  Widget _buildTasksContent() {
    switch (_tasksView) {
      case _ProjectTasksView.kanban:
        return _buildBoard();
      case _ProjectTasksView.calendar:
        return _buildCalendar();
      case _ProjectTasksView.list:
        return _buildTaskListView();
    }
  }

  bool _taskMatchesSearch(Map<String, dynamic> t) {
    final q = _taskSearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final blob = '${t['name']} ${t['title']} T-${t['id']}'.toLowerCase();
    return blob.contains(q);
  }

  List<Map<String, dynamic>> _filteredTasks(List<dynamic> tasks) {
    return tasks
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where(_taskMatchesSearch)
        .toList();
  }

  List<Map<String, dynamic>> _allProjectTasks() {
    final out = <Map<String, dynamic>>[];
    for (final s in _stages) {
      for (final t in (s['tasks'] as List?) ?? []) {
        if (t is Map) out.add(Map<String, dynamic>.from(t));
      }
    }
    for (final t in (_project!['unassigned_tasks'] as List?) ?? []) {
      if (t is Map) out.add(Map<String, dynamic>.from(t));
    }
    return out;
  }

  Widget _buildTaskListView() {
    final tasks = _allProjectTasks().where(_taskMatchesSearch).toList();
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          _taskSearchCtrl.text.trim().isEmpty ? 'No tasks yet' : 'No tasks match your search',
          style: const TextStyle(color: AppTheme.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: tasks.length,
      itemBuilder: (ctx, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _taskCard(tasks[i], AppTheme.primary),
      ),
    );
  }

  Widget _buildBoard() {
    final stages = _stages;
    final unassigned = (_project!['unassigned_tasks'] as List?) ?? [];
    if (stages.isEmpty && unassigned.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_column, size: 64, color: Colors.white24),
            SizedBox(height: 12),
            Text('No stages yet', style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
            SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _showAddStageDialog,
              icon: Icon(Icons.add, size: 18),
              label: Text('Add Stage'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.featureVault,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppTheme.textPrimary.withValues(alpha: 0.7),
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Long-press a task, drag onto another column to move (same as web).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight.isFinite && constraints.maxHeight > 140
            ? constraints.maxHeight
            : 400.0;
        final colW = Responsive.kanbanColumnWidth(context);
        return Scrollbar(
          controller: _boardHScrollController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          thickness: 8,
          radius: const Radius.circular(8),
          child: ListView(
            controller: _boardHScrollController,
            primary: false,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(12, 8, 12, 16),
            children: [
              ...stages.map(
                (s) => SizedBox(
                  width: colW,
                  height: h,
                  child: _stageColumnDnD(s),
                ),
              ),
              if (unassigned.isNotEmpty)
                SizedBox(
                  width: colW,
                  height: h,
                  child: _unassignedKanbanColumn(_filteredTasks(unassigned)),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _sameStage(TaskDragPayload d, int targetStageId) =>
      d.sourceStageId != null && d.sourceStageId == targetStageId;

  Future<void> _onTaskDropOnStage(TaskDragPayload data, int targetStageId) async {
    if (_sameStage(data, targetStageId)) return;
    final snapshot = _snapshotProject();
    _moveTaskOptimistically(data, targetStageId);
    final r = await widget.apiService.moveTask(data.taskId, targetStageId);
    if (!mounted) return;
    if (r['success'] == true) {
      _load(silent: true);
    } else {
      _restoreProject(snapshot);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not move task')),
      );
    }
  }

  Widget _stageColumnDnD(dynamic stage) {
    final stageId = stage['id'] as int;
    final tasks = _filteredTasks((stage['tasks'] as List?) ?? []);
    final color = _parseHex(stage['color'] ?? '#3B82F6');
    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (details) => !_sameStage(details.data, stageId),
      onAcceptWithDetails: (details) => _onTaskDropOnStage(details.data, stageId),
      builder: (context, candidate, rejected) {
        final hi = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: hi ? 0.08 : 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hi ? AppTheme.success : Colors.white.withValues(alpha: 0.06),
              width: hi ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                ),
              ),
              _kanbanStageHeader(stage, color, stageId, tasks.length),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text(
                          hi ? 'Release to drop' : 'Drag tasks here',
                          style: TextStyle(color: hi ? AppTheme.success : Colors.white24, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: tasks.length,
                        itemBuilder: (ctx, i) => _draggableTaskWrap(tasks[i], color, stageId),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: TextButton.icon(
                  onPressed: () => _showCreateTaskInStageDialog(stageId),
                  icon: const Icon(Icons.add, size: 16, color: AppTheme.success),
                  label: const Text('Create', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kanbanStageHeader(dynamic stage, Color color, int stageId, int taskCount) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 4, 6),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              (stage['name'] ?? '').toString().toUpperCase(),
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
            child: Text('$taskCount', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 2),
          Tooltip(
            message: 'Add task to this stage',
            child: IconButton(
              onPressed: () => _showCreateTaskInStageDialog(stageId),
              icon: Icon(Icons.add_task, color: AppTheme.success, size: 20),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(width: 32, height: 32),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.white30, size: 18),
            color: AppTheme.surface2,
            padding: EdgeInsets.zero,
            onSelected: (v) {
              if (v == 'add_task') _showCreateTaskInStageDialog(stageId);
              if (v == 'delete') _deleteStage(stageId, stage['name'] ?? '');
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'add_task',
                child: Row(children: [Icon(Icons.add_task, color: AppTheme.success, size: 16), SizedBox(width: 8), Text('Add Task', style: TextStyle(color: Colors.white, fontSize: 13))]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 16), SizedBox(width: 8), Text('Delete Stage', style: TextStyle(color: Colors.redAccent, fontSize: 13))]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _unassignedKanbanColumn(List<Map<String, dynamic>> tasks) {
    final color = _parseHex('#64748B');
    return Container(
      margin: EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NO STAGE',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                ),
                Text('${tasks.length}', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: 12),
              itemCount: tasks.length,
              itemBuilder: (ctx, i) => _draggableTaskWrap(tasks[i], color, null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _draggableTaskWrap(dynamic t, Color stageColor, int? sourceStageId) {
    final payload = TaskDragPayload(taskId: t['id'] as int, sourceStageId: sourceStageId);
    final taskMap = Map<String, dynamic>.from(t as Map);
    final feedbackCard = Material(
      color: Colors.transparent,
      elevation: 10,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 268, child: _taskCard(taskMap, stageColor, withSideMargin: false)),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Padding(
        key: ValueKey('task_${t['id']}_$sourceStageId'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Draggable<TaskDragPayload>(
          data: payload,
          feedback: feedbackCard,
          childWhenDragging: Opacity(opacity: 0.35, child: _taskCard(taskMap, stageColor, withSideMargin: false)),
          child: _taskCard(taskMap, stageColor, withSideMargin: false),
        ),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> t, Color stageColor, {bool withSideMargin = true}) {
    final sc = t['subtask_count'] ?? 0;
    final cs = t['completed_subtask_count'] ?? 0;
    final pr = (t['subtask_progress'] ?? 0).toDouble();
    final done = t['completed'] == true;
    final canDelete = t['can_delete'] == true;
    final pri = (t['priority'] ?? 'medium').toString();
    final taskId = t['id'];
    final due = _formatShortDate(t['due_date']?.toString());

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: withSideMargin ? 0 : 0, vertical: 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openTaskDetailPage(t),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgDeep.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: stageColor.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: stageColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'T-$taskId',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _pc(pri).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              pri[0].toUpperCase() + pri.substring(1),
                              style: TextStyle(color: _pc(pri), fontSize: 9, fontWeight: FontWeight.w700),
                            ),
                          ),
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.more_horiz, color: AppTheme.textMuted, size: 18),
                            color: AppTheme.surface2,
                            onSelected: (v) {
                              if (v == 'view') _showTaskViewKanban(t);
                              if (v == 'edit') _showEditTaskKanban(t);
                              if (v == 'upload') _uploadTaskFileFromKanban(t);
                              if (v == 'complete') _toggleTaskComplete(t);
                              if (v == 'delete') _deleteTask(t);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'view', child: Text('View details')),
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              const PopupMenuItem(value: 'upload', child: Text('Upload file')),
                              PopupMenuItem(
                                value: 'complete',
                                child: Text(done ? 'Restore task' : 'Mark complete'),
                              ),
                              if (canDelete)
                                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _displayStr(t['name'] ?? t['title']),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (sc > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('Subtasks $cs/$sc', style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
                            const Spacer(),
                            Text('${pr.toInt()}%', style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (pr / 100).clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation(stageColor),
                            minHeight: 3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildAssigneeAvatars(t),
                          const Spacer(),
                          if (due.isNotEmpty) ...[
                            const Icon(Icons.schedule, size: 11, color: Colors.white30),
                            const SizedBox(width: 3),
                            Text(due, style: const TextStyle(color: Colors.white30, fontSize: 9)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      TaskStatusDropdown(
                        key: ValueKey<String>('kt_${t['id']}_${t['status']}_${t['completed']}'),
                        taskId: t['id'] as int,
                        task: t,
                        apiService: widget.apiService,
                        onUpdated: () => _load(silent: true),
                        compact: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildCalendar() {
    final y = _calMonth.year; final m = _calMonth.month;
    final dim = DateTime(y, m + 1, 0).day; final fw = DateTime(y, m, 1).weekday;
    final mn = ['','January','February','March','April','May','June','July','August','September','October','November','December'];
    final ebd = <String, List<dynamic>>{}; for (final e in _calEvents) { final d = e['date'] ?? ''; ebd.putIfAbsent(d, () => []); ebd[d]!.add(e); }
    final now = DateTime.now();
    return Column(children: [
      // Header with month nav
      Container(margin: EdgeInsets.fromLTRB(16, 8, 16, 0), padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.vertical(top: Radius.circular(16)), border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: Row(children: [
          GestureDetector(onTap: () => setState(() => _calMonth = DateTime(y, m - 1)),
            child: Container(padding: EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.chevron_left, color: AppTheme.textMuted, size: 20))),
          Expanded(child: Text('${mn[m]} $y', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          GestureDetector(onTap: () => setState(() => _calMonth = DateTime(y, m + 1)),
            child: Container(padding: EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20))),
          SizedBox(width: 8),
          GestureDetector(onTap: () => setState(() => _calMonth = now),
            child: Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppTheme.featureVault.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.featureVault.withOpacity(0.3))),
              child: Text('Today', style: TextStyle(color: AppTheme.featureVault, fontSize: 11, fontWeight: FontWeight.w700)))),
        ])),
      // Day headers
      Container(margin: EdgeInsets.symmetric(horizontal: 16), padding: EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), border: Border.symmetric(vertical: BorderSide(color: Colors.white.withOpacity(0.06)))),
        child: Row(children: ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map((d) =>
          Expanded(child: Text(d, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.priorityLow, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)))).toList())),
      // Calendar grid
      Expanded(child: Container(margin: EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)), border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: GridView.builder(padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.65),
          itemCount: (fw % 7) + dim,
          itemBuilder: (ctx, i) {
            if (i < fw % 7) return Container(decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.03))));
            final day = i - (fw % 7) + 1; if (day > dim) return SizedBox();
            final ds = '$y-${m.toString().padLeft(2,"0")}-${day.toString().padLeft(2,"0")}';
            final evts = ebd[ds] ?? [];
            final isToday = now.year == y && now.month == m && now.day == day;
            return Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.03)),
                color: isToday ? AppTheme.featureVault.withOpacity(0.08) : Colors.transparent),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Day number
                Padding(padding: EdgeInsets.fromLTRB(6, 4, 6, 2), child: isToday
                  ? Container(width: 22, height: 22, decoration: BoxDecoration(color: AppTheme.featureVault.withOpacity(0.25), borderRadius: BorderRadius.circular(6)),
                      child: Center(child: Text('$day', style: TextStyle(color: AppTheme.featureVault, fontSize: 11, fontWeight: FontWeight.w800))))
                  : Text('$day', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
                // Events
                ...evts.take(3).map((e) => _calEvent(e)),
                if (evts.length > 3) Padding(padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('+${evts.length - 3} more', style: TextStyle(color: AppTheme.featureVault, fontSize: 7, fontWeight: FontWeight.w700))),
              ]));
          }))),
      // Legend
      Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Row(children: [
        _legendDot(AppTheme.featureVault, 'Task'), SizedBox(width: 10),
        _legendDot(AppTheme.warning, 'High'), SizedBox(width: 10),
        _legendDot(AppTheme.primary, 'Active'), SizedBox(width: 10),
        _legendDot(AppTheme.success, 'Done/Due'),
      ])),
    ]);
  }

  Widget _calEvent(dynamic e) {
    final type = e['type'] ?? 'task';
    final completed = e['completed'] == true;
    final priority = e['priority'] ?? 'medium';
    Color bg;
    if (type == 'deadline') { bg = AppTheme.danger; }
    else if (type == 'due_date') { bg = AppTheme.success; }
    else if (completed) { bg = AppTheme.success; }
    else if (priority == 'high') { bg = AppTheme.warning; }
    else { bg = AppTheme.featureVault; }

    return GestureDetector(
      onTap: () {
        final taskId = e['id'];
        if (taskId != null && taskId != 0) {
          _openTaskDetailPage({'id': taskId, 'name': e['title'], 'title': e['title']});
        }
      },
      child: Container(margin: EdgeInsets.fromLTRB(3, 0, 3, 2), padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(e['title'] ?? '', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
    );
  }

  Widget _legendDot(Color c, String label) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    SizedBox(width: 4), Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.w600)),
  ]);
}
