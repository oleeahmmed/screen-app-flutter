import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/task_status_dropdown.dart';

int? _parseUserId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// Dedupes employees by id; if [currentUserId] is set but not in the project list, adds one menu row (API user id).
List<DropdownMenuItem<int?>> buildTaskAssigneeDropdownItems(
  List<dynamic> employees,
  Map<String, dynamic> task,
  int? currentUserId,
) {
  const unassignedStyle = TextStyle(color: Colors.white54, fontSize: 13);
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
      child: Text(e['full_name'] ?? e['username'] ?? '$id', style: itemStyle),
    ));
  }
  if (currentUserId != null && !seen.contains(currentUserId)) {
    final label = task['user_name']?.toString().trim();
    items.add(DropdownMenuItem<int?>(
      value: currentUserId,
      child: Text(
        (label != null && label.isNotEmpty) ? label : 'User #$currentUserId',
        style: itemStyle.copyWith(color: const Color(0xFFe2e8f0)),
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

class ProjectsPage extends StatefulWidget {
  final ApiService apiService;
  /// When true (Work hub tab), no full-screen gradient — matches web "list inside app shell".
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
      setState(() {
        _projects = (r['data'] as List?)?.cast<dynamic>() ?? [];
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
  Color _stc(String s) { switch(s){ case 'active': return Color(0xFF10B981); case 'on_hold': return Color(0xFFF59E0B); case 'completed': return Color(0xFF8B5CF6); case 'cancelled': return Color(0xFFEF4444); default: return Color(0xFF3B82F6); } }
  Color _prc(String p) { switch(p){ case 'high': case 'critical': return Color(0xFFEF4444); case 'medium': return Color(0xFF3B82F6); default: return Color(0xFF64748B); } }
  void _showCreateProjectDialog() {
    final nc = TextEditingController(); final dc = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Color(0xFF1e293b), title: Text('New Project', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _dtf(nc, 'Project Name *'), SizedBox(height: 12), _dtf(dc, 'Description', ml: 3)])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async { if (nc.text.trim().isEmpty) return; Navigator.pop(ctx);
          await widget.apiService.createProject(name: nc.text.trim(), description: dc.text.trim()); _loadProjects();
        }, style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ), child: Text('Create'))],
    ));
  }
Widget _dtf(TextEditingController c, String h, {int ml=1}) => TextField(controller: c, maxLines: ml, style: TextStyle(color: Colors.white),
    decoration: InputDecoration(hintText: h, hintStyle: TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)));
  InputDecoration _searchDecoration() {
    return InputDecoration(
      hintText: 'Search name, description, client…',
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
        dropdownColor: widget.embeddedInParent ? AppTheme.surface2 : const Color(0xFF1e293b),
        style: TextStyle(
          color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white,
          fontSize: 14,
        ),
        hint: Text(
          hint,
          style: TextStyle(
            color: widget.embeddedInParent ? AppTheme.textMuted : Colors.white54,
            fontSize: 14,
          ),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padH = widget.embeddedInParent ? 16.0 : 24.0;
    final list = _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBright))
        : _projects.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open, size: 64, color: AppTheme.textMuted.withValues(alpha: 0.35)),
                    const SizedBox(height: 12),
                    Text(
                      _archived ? 'No archived projects' : 'No projects yet',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
            : LayoutBuilder(
                builder: (ctx, c) {
                  final cross = c.maxWidth >= 560 ? 2 : 1;
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(padH, 0, padH, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cross,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: cross == 2 ? 1.15 : 1.35,
                    ),
                    itemCount: _projects.length,
                    itemBuilder: (ctx, i) => _projectCard(_projects[i]),
                  );
                },
              );

    final header = Padding(
      padding: EdgeInsets.fromLTRB(padH, widget.embeddedInParent ? 4 : 20, padH, 12),
      child: Row(
        children: [
          Icon(Icons.folder_open, color: const Color(0xFFA78BFA), size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _archived ? 'Archived projects' : 'All projects',
                  style: TextStyle(
                    fontSize: widget.embeddedInParent ? 20 : 24,
                    fontWeight: FontWeight.bold,
                    color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white,
                  ),
                ),
                Text(
                  '${_projects.length} project${_projects.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: widget.embeddedInParent ? AppTheme.textMuted : Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!_archived)
            Material(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _showCreateProjectDialog,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ),
            ),
          if (!_archived) const SizedBox(width: 8),
          Material(
            color: AppTheme.surface2.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _loadProjects,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.refresh_rounded, color: AppTheme.textMuted, size: 20),
              ),
            ),
          ),
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
          tilePadding: EdgeInsets.zero,
          title: Text(
            'Filters',
            style: TextStyle(
              color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 14,
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
                      '${d['project_name'] ?? ''} · ${d['name'] ?? ''}',
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
                    color: widget.embeddedInParent ? AppTheme.primary : const Color(0xFFA78BFA),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        archiveChips,
        const SizedBox(height: 8),
        searchField,
        const SizedBox(height: 8),
        filtersPanel,
        const SizedBox(height: 8),
        Expanded(child: list),
      ],
    );

    if (widget.embeddedInParent) {
      return body;
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2563eb),
            Color(0xFF1e40af),
            Color(0xFF1e3a5f),
            Color(0xFF0f172a),
          ],
        ),
      ),
      child: SafeArea(child: body),
    );
  }
  Widget _projectCard(dynamic p) {
    final comp = (p['completion_percentage'] ?? 0).toDouble();
    final st = p['status'] ?? 'planning';
    final pri = p['priority'] ?? 'medium';
    final pid = p['id'] is int ? p['id'] as int : (p['id'] as num).toInt();
    final canArchive = p['can_archive'] == true;
    final isArc = p['is_archived'] == true;
    final muted = widget.embeddedInParent ? AppTheme.textMuted : Colors.white38;
    final descColor = widget.embeddedInParent ? AppTheme.textMuted.withValues(alpha: 0.9) : Colors.white38;
    return GestureDetector(
      onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ProjectDetailView(
                apiService: widget.apiService,
                projectId: pid,
                projectName: p['name']?.toString() ?? '',
              ),
            ),
          ).then((_) => _loadProjects()),
      child: Container(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.embeddedInParent
              ? AppTheme.surface2.withValues(alpha: 0.55)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: widget.embeddedInParent
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(0xFF8B5CF6).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.folder_open, color: Color(0xFF8B5CF6), size: 22),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['name'] ?? '',
                      style: TextStyle(
                        color: widget.embeddedInParent ? AppTheme.textPrimary : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((p['customer_name'] ?? '').toString().isNotEmpty)
                      Text(
                        '${p['customer_name']}',
                        style: TextStyle(color: muted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      p['project_manager'] ?? '',
                      style: TextStyle(color: muted, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (canArchive)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(Icons.more_vert, color: muted, size: 22),
                  color: widget.embeddedInParent ? AppTheme.surface2 : const Color(0xFF1e293b),
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
                    if (isArc) const PopupMenuItem(value: 'restore', child: Text('Restore')),
                  ],
                ),
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _prc(pri))),
            ],
          ),
          if ((p['description'] ?? '').toString().isNotEmpty) ...[
            SizedBox(height: 10),
            Text(
              p['description'],
              style: TextStyle(color: descColor, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          SizedBox(height: 12),
          Row(children: [
            Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: _stc(st).withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: _stc(st).withOpacity(0.3))),
              child: Text(st.replaceAll('_', ' ').toUpperCase(), style: TextStyle(color: _stc(st), fontSize: 10, fontWeight: FontWeight.w700))),
            Spacer(), Text(p['created_at']?.toString().substring(0, 10) ?? '', style: TextStyle(color: Colors.white24, fontSize: 10)),
          ]),
          SizedBox(height: 14),
          Row(children: [Text('Progress', style: TextStyle(color: Colors.white38, fontSize: 11)), Spacer(), Text('${comp.toInt()}%', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))]),
          SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: comp / 100, backgroundColor: Colors.white.withOpacity(0.1), valueColor: AlwaysStoppedAnimation(Color(0xFF8B5CF6)), minHeight: 5)),
          SizedBox(height: 10),
          Row(children: [
            Icon(Icons.checklist, size: 12, color: Colors.white30), SizedBox(width: 3), Text('${p['total_tasks'] ?? 0} tasks', style: TextStyle(color: Colors.white38, fontSize: 10)),
            SizedBox(width: 12), Icon(Icons.account_tree, size: 12, color: Colors.white30), SizedBox(width: 3), Text('${p['total_subtasks'] ?? 0} subtasks', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
        ],
      ),
    ),
    );
  }
}

class ProjectDetailView extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  final String projectName;
  /// When true (e.g. Work hub), hide back button — user switches project from parent menu.
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
  Map<String, dynamic>? _project; bool _isLoading = true;
  late TabController _tabCtrl; DateTime _calMonth = DateTime.now();
  /// Horizontal Kanban board scroll — must be shared with [Scrollbar] for dragging/sync.
  final ScrollController _boardHScrollController = ScrollController();
  @override
  void initState() { super.initState(); _tabCtrl = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() {
    _boardHScrollController.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }
  Future<void> _load() async {
    setState(() => _isLoading = true);
    final r = await widget.apiService.getProjectDetail(widget.projectId);
    if (r['success'] && mounted) setState(() { _project = r['data']; _isLoading = false; });
    else if (mounted) setState(() => _isLoading = false);
  }
  bool get _isManager => _project?['is_manager'] == true;
  List<dynamic> get _employees => (_project?['employees'] as List?) ?? [];
  List<dynamic> get _stages => (_project?['stages'] as List?) ?? [];
  List<dynamic> get _calEvents => (_project?['calendar_events'] as List?) ?? [];
  Color _pc(String p) { switch(p){ case 'high': case 'critical': return Color(0xFFEF4444); case 'medium': return Color(0xFFF59E0B); default: return Color(0xFF10B981); } }
  Color _parseHex(String h) { try { return Color(int.parse(h.replaceFirst('#', '0xFF'))); } catch(_) { return Color(0xFF3B82F6); } }
  Widget _tf(TextEditingController c, String h, {int ml=1}) => TextField(controller: c, maxLines: ml, style: TextStyle(color: Colors.white),
    decoration: InputDecoration(hintText: h, hintStyle: TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)));
  void _showAddStageDialog() {
    final nc = TextEditingController(); String color = '#3B82F6';
    final cls = ['#3B82F6','#10B981','#F59E0B','#EF4444','#8B5CF6','#EC4899','#64748B','#06B6D4'];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: Color(0xFF1e293b), title: Text('Add Stage', style: TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [_tf(nc, 'Stage Name *'), SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: cls.map((c) => GestureDetector(onTap: () => setD(() => color = c),
          child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _parseHex(c), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 2))))).toList())]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async { if (nc.text.trim().isEmpty) return; Navigator.pop(ctx);
          await widget.apiService.createStage(widget.projectId, name: nc.text.trim(), color: color); _load();
        }, style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ), child: Text('Add'))],
    )));
  }
  void _deleteStage(int sid, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: Color(0xFF1e293b),
      title: Text('Delete "$name"?', style: TextStyle(color: Colors.white)), content: Text('Tasks move to another stage.', style: TextStyle(color: Colors.white54)),
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
    final name = t['name']?.toString() ?? 'this task';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Color(0xFF1e293b),
        title: Text('Delete task?', style: TextStyle(color: Colors.white)),
        content: Text('Delete "$name"? This cannot be undone.', style: TextStyle(color: Colors.white70)),
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
        'name': t['name'] ?? '',
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
          backgroundColor: Color(0xFF1e293b),
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
                            style: TextStyle(color: sel ? c : Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
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
                        activeColor: Color(0xFF8B5CF6),
                        checkColor: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Attachment required to complete',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
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
                        dropdownColor: Color(0xFF1e293b),
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
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text('Cancel', style: TextStyle(color: Colors.white54))),
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
                backgroundColor: Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
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
    if (v == null) return '—';
    final s = v.toString();
    return s.isEmpty ? '—' : s;
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
            backgroundColor: const Color(0xFF0f172a),
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
                      color: const Color(0xFF1e293b),
                      child: Row(
                        children: [
                          const Icon(Icons.image_outlined, color: Color(0xFFA78BFA), size: 20),
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
                            icon: const Icon(Icons.close_rounded, color: Colors.white54),
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
                                  child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                                ),
                              );
                            },
                            errorBuilder: (c, e, s) => const Padding(
                              padding: EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
                                  SizedBox(height: 8),
                                  Text('Could not load preview', style: TextStyle(color: Colors.white54)),
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
              color: const Color(0xFF8B5CF6).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFFA78BFA)),
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
                      child: const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6), strokeWidth: 2)),
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
                  color: const Color(0xFFA78BFA),
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
                            [if (sizeStr.isNotEmpty) sizeStr, if (uploaded != null && uploaded.isNotEmpty) '· $uploaded']
                                .join(' '),
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: url == null || url.isEmpty ? null : () => _previewAttachment(dialogCtx, url, name),
                  icon: const Icon(Icons.visibility_outlined, size: 16, color: Color(0xFF93C5FD)),
                  label: const Text('Preview', style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                TextButton.icon(
                  onPressed: url == null || url.isEmpty ? null : () => _openAttachmentUrl(url),
                  icon: const Icon(Icons.download_outlined, size: 16, color: Color(0xFF34D399)),
                  label: const Text('Open', style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600)),
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
      _chip(_fmtTaskField(task['status']), const Color(0xFF3B82F6)),
      _chip(_fmtTaskField(task['priority']), const Color(0xFFF59E0B)),
      if (task['completed'] == true) _chip('Done', const Color(0xFF10B981)),
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
            '${_fmtTaskField(task['completed_subtask_count'])} / ${_fmtTaskField(task['subtask_count'])} · ${_fmtTaskField(task['subtask_progress'])}%',
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
    if (text == '—') return const SizedBox.shrink();
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
    final taskId = t['id'] as int;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (c) => Center(
        child: Card(
          elevation: 16,
          color: const Color(0xFF1e293b),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: Color(0xFF8B5CF6), strokeWidth: 2.5),
          ),
        ),
      ),
    );
    Map<String, dynamic> task;
    List<dynamic> attachments = [];
    try {
      final results = await Future.wait([
        widget.apiService.getTask(taskId),
        widget.apiService.getTaskAttachments(taskId),
      ]);
      final r = results[0];
      final rAtt = results[1];
      if (!mounted) return;
      if (r['success'] == true && r['data'] != null) {
        task = Map<String, dynamic>.from(r['data'] as Map);
      } else {
        task = Map<String, dynamic>.from(t as Map);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(r['error']?.toString() ?? 'Showing saved card data')),
          );
        }
      }
      if (rAtt['success'] == true) {
        final raw = rAtt['data'];
        attachments = raw is List ? List<dynamic>.from(raw) : <dynamic>[];
      }
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
    if (!mounted) return;

    final title = _fmtTaskField(task['name']);
    final maxH = MediaQuery.of(context).size.height * 0.9;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
        child: SizedBox(
          width: 460,
          height: maxH,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1e293b), Color(0xFF0f172a)],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
              boxShadow: [
                BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.15), blurRadius: 28, offset: const Offset(0, 12)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF7C3AED).withOpacity(0.45),
                        const Color(0xFF2563EB).withOpacity(0.22),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TASK DETAILS',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.65),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(dialogCtx),
                        icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.7), size: 22),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _buildTaskDetailContent(dialogCtx, task, attachments),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
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

  void _showEditProjectDialog() {
    final nc = TextEditingController(text: _project?['name'] ?? '');
    final dc = TextEditingController(text: _project?['description'] ?? '');
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: Color(0xFF1e293b), title: Text('Edit Project', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [_tf(nc, 'Project Name *'), SizedBox(height: 10), _tf(dc, 'Description', ml: 3)])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async { if (nc.text.trim().isEmpty) return; Navigator.pop(ctx);
          await widget.apiService.updateProject(widget.projectId, {'name': nc.text.trim(), 'description': dc.text.trim()}); _load();
        }, style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ), child: Text('Save'))],
    ));
  }
  void _deleteProject() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: Color(0xFF1e293b),
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
    String pri = 'medium'; int? assignee; String? due;
    bool isAttReq = false; PlatformFile? pickedFile;
    final createAssigneeItems = buildTaskAssigneeDropdownItems(_employees, {}, null);
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: Color(0xFF1e293b), title: Text('Create Task', style: TextStyle(color: Colors.white)),
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
                    style: TextStyle(color: s ? c : Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (createAssigneeItems.length > 1) ...[
          SizedBox(height: 10),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: assignee,
                hint: Text('Assign to...', style: TextStyle(color: Colors.white30, fontSize: 13)),
                dropdownColor: Color(0xFF1e293b),
                items: createAssigneeItems,
                onChanged: (v) => setD(() => assignee = v),
              ),
            ),
          ),
        ],
        SizedBox(height: 10),
        GestureDetector(onTap: () async {
          final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2030),
            builder: (c, ch) => Theme(data: ThemeData.dark().copyWith(colorScheme: ColorScheme.dark(primary: Color(0xFF8B5CF6))), child: ch!));
          if (picked != null) setD(() => due = "${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}");
        }, child: Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [Icon(Icons.calendar_today, size: 16, color: Colors.white38), SizedBox(width: 8), Text(due ?? 'Due date', style: TextStyle(color: due != null ? Colors.white : Colors.white30, fontSize: 13))]))),
        SizedBox(height: 10),
        // Attachment Required checkbox
        Row(children: [
          SizedBox(width: 24, height: 24, child: Checkbox(value: isAttReq, onChanged: (v) => setD(() => isAttReq = v ?? false), activeColor: Color(0xFF8B5CF6), checkColor: Colors.white)),
          SizedBox(width: 8), Text('Attachment Required', style: TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
        SizedBox(height: 10),
        GestureDetector(
          onTap: () async { final r = await FilePicker.platform.pickFiles(allowMultiple: false); if (r != null && r.files.isNotEmpty) setD(() => pickedFile = r.files.first); },
          child: Container(width: double.infinity, padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: pickedFile != null ? Color(0xFF8B5CF6) : Colors.white12)),
            child: Row(children: [
              Icon(pickedFile != null ? Icons.check_circle : Icons.attach_file, color: pickedFile != null ? Color(0xFF22C55E) : Colors.white38, size: 20),
              SizedBox(width: 8), Expanded(child: Text(pickedFile?.name ?? 'Attach file', style: TextStyle(color: pickedFile != null ? Colors.white : Colors.white30, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (pickedFile != null) GestureDetector(onTap: () => setD(() => pickedFile = null), child: Icon(Icons.close, color: Colors.white38, size: 16)),
            ]))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async {
          if (nc.text.trim().isEmpty) return;
          Navigator.pop(ctx);
          List<int>? bytes; if (pickedFile != null && pickedFile!.path != null) bytes = await File(pickedFile!.path!).readAsBytes();
          await widget.apiService.createTask(name: nc.text.trim(), description: dc.text.trim(), priority: pri, dueDate: due, projectId: widget.projectId, stageId: stageId,
            isAttachmentRequired: isAttReq, attachmentBytes: bytes, attachmentName: pickedFile?.name); _load();
        }, style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ), child: Text('Create'))],
    )));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2563eb), Color(0xFF1e40af), Color(0xFF1e3a5f), Color(0xFF0f172a)])),
      child: SafeArea(child: _isLoading ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)))
        : _project == null ? Center(child: Text('Failed to load', style: TextStyle(color: Colors.white54)))
        : Column(children: [
            _buildHeader(),
            _buildStats(),
            const SizedBox(height: 8),
            _buildBoardToolbar(),
            TabBar(
              controller: _tabCtrl,
              indicatorColor: Color(0xFF8B5CF6),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              tabs: const [Tab(text: 'Board'), Tab(text: 'Calendar')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [_buildBoard(), _buildCalendar()],
              ),
            ),
          ])),
    ));
  }
  Widget _buildHeader() {
    final p = _project!; final comp = (p['completion_percentage'] ?? 0).toDouble();
    return Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (!widget.embedded)
          GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.arrow_back, color: Colors.white54, size: 22)),
        if (!widget.embedded) SizedBox(width: 10),
        if (widget.embedded) ...[Icon(Icons.hub_outlined, color: Colors.white38, size: 22), SizedBox(width: 10)],
        Container(width: 40, height: 40, decoration: BoxDecoration(color: Color(0xFF8B5CF6).withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.folder_open, color: Color(0xFF8B5CF6), size: 20)),
        SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p['name'] ?? '', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          Text('${(p["status"] ?? "").toString().replaceAll("_", " ")} priority', style: TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        PopupMenuButton<String>(icon: Icon(Icons.more_vert, color: Colors.white54, size: 22), color: Color(0xFF1e293b),
          onSelected: (v) { if (v=='add_stage') _showAddStageDialog(); else if (v=='edit') _showEditProjectDialog(); else if (v=='delete') _deleteProject(); else if (v=='refresh') _load(); },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'add_stage', child: Row(children: [Icon(Icons.view_column, color: Color(0xFF8B5CF6), size: 18), SizedBox(width: 8), Text('Add Stage', style: TextStyle(color: Colors.white))])),
            PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, color: Colors.white54, size: 18), SizedBox(width: 8), Text('Edit Project', style: TextStyle(color: Colors.white))])),
            PopupMenuItem(value: 'refresh', child: Row(children: [Icon(Icons.refresh, color: Colors.white54, size: 18), SizedBox(width: 8), Text('Refresh', style: TextStyle(color: Colors.white))])),
            if (_isManager) PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 18), SizedBox(width: 8), Text('Delete Project', style: TextStyle(color: Colors.redAccent))])),
          ]),
      ]),
      SizedBox(height: 10),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: comp / 100, backgroundColor: Colors.white.withOpacity(0.1), valueColor: AlwaysStoppedAnimation(Color(0xFF8B5CF6)), minHeight: 4)),
    ]));
  }

  Widget _buildBoardToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.35)),
              ),
              child: const Icon(Icons.view_column, size: 18, color: Color(0xFFC4B5FD)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Project tasks',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Board or calendar — same data as the web. Drag the ⋮⋮ handle or long-press a card, then drop on a stage column.',
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 10, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final s = _project!['stats'] ?? {};
    final stageOverview = (_project!['stage_overview'] as List?) ?? [];
    final doneStageName = s['done_stage_name'] ?? 'Done';
    return Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        _sc('${s["total_tasks"]??0}','Tasks',Color(0xFF64748B)), SizedBox(width: 6),
        _sc('${s["completed_tasks"]??0}','In $doneStageName',Color(0xFF10B981)), SizedBox(width: 6),
        _sc('${s["total_subtasks"]??0}','Subtasks',Color(0xFF64748B)), SizedBox(width: 6),
        _sc('${(_project!["completion_percentage"]??0).toInt()}%','Progress',Color(0xFF8B5CF6)),
      ])),
      // Stage Overview
      if (stageOverview.isNotEmpty) ...[
        SizedBox(height: 10),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: stageOverview.map((st) {
          final tc = st['task_count'] ?? 0;
          final sc = st['subtask_count'] ?? 0;
          final sd = st['subtask_done'] ?? 0;
          final clr = _hexColor(st['color'] ?? '#3B82F6');
          return Container(margin: EdgeInsets.only(right: 6), padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: clr.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: clr.withOpacity(0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: clr)),
              SizedBox(width: 6),
              Text('${st["name"]}', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
              SizedBox(width: 4),
              Container(padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: clr.withOpacity(0.3), borderRadius: BorderRadius.circular(6)),
                child: Text('$tc', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
              if (sc > 0) ...[SizedBox(width: 3),
                Text('$sd/$sc', style: TextStyle(color: Colors.white38, fontSize: 9))],
            ]));
        }).toList())),
      ],
    ]));
  }
  Color _hexColor(String hex) { hex = hex.replaceAll('#', ''); if (hex.length == 6) hex = 'FF$hex'; return Color(int.parse(hex, radix: 16)); }
  Widget _sc(String v, String l, Color c) => Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.2))),
    child: Column(children: [Text(v, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)), Text(l, style: TextStyle(color: Colors.white38, fontSize: 9))]));
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
            Text('No stages yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
            SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _showAddStageDialog,
              icon: Icon(Icons.add, size: 18),
              label: Text('Add Stage'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
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
                  width: 302,
                  height: h,
                  child: _stageColumnDnD(s),
                ),
              ),
              if (unassigned.isNotEmpty)
                SizedBox(
                  width: 302,
                  height: h,
                  child: _unassignedKanbanColumn(List<dynamic>.from(unassigned)),
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
    final r = await widget.apiService.moveTask(data.taskId, targetStageId);
    if (!mounted) return;
    if (r['success'] == true) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not move task')),
      );
    }
  }

  Widget _stageColumnDnD(dynamic stage) {
    final stageId = stage['id'] as int;
    final tasks = (stage['tasks'] as List?) ?? [];
    final color = _parseHex(stage['color'] ?? '#3B82F6');
    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (details) => !_sameStage(details.data, stageId),
      onAcceptWithDetails: (details) => _onTaskDropOnStage(details.data, stageId),
      builder: (context, candidate, rejected) {
        final hi = candidate.isNotEmpty;
        return Container(
          margin: EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(hi ? 0.1 : 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hi ? Color(0xFF34D399) : Colors.white.withOpacity(0.06),
              width: hi ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kanbanStageHeader(stage, color, stageId, tasks.length),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text(
                          'Drag tasks here',
                          style: TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(bottom: 12),
                        itemCount: tasks.length,
                        itemBuilder: (ctx, i) => _draggableTaskWrap(tasks[i], color, stageId),
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
              style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
            child: Text('$taskCount', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 2),
          Tooltip(
            message: 'Add task to this stage',
            child: IconButton(
              onPressed: () => _showCreateTaskInStageDialog(stageId),
              icon: Icon(Icons.add_task, color: Color(0xFF10B981), size: 20),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(width: 32, height: 32),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.white30, size: 18),
            color: Color(0xFF1e293b),
            padding: EdgeInsets.zero,
            onSelected: (v) {
              if (v == 'add_task') _showCreateTaskInStageDialog(stageId);
              if (v == 'delete') _deleteStage(stageId, stage['name'] ?? '');
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'add_task',
                child: Row(children: [Icon(Icons.add_task, color: Color(0xFF10B981), size: 16), SizedBox(width: 8), Text('Add Task', style: TextStyle(color: Colors.white, fontSize: 13))]),
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

  Widget _unassignedKanbanColumn(List<dynamic> tasks) {
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
                    style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                ),
                Text('${tasks.length}', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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
    final feedbackCard = Material(
      color: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 268,
        child: Opacity(
          opacity: 0.95,
          child: _taskCard(t, stageColor, withSideMargin: false),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Draggable<TaskDragPayload>(
            data: payload,
            feedback: feedbackCard,
            childWhenDragging: Opacity(
              opacity: 0.35,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(Icons.drag_indicator, size: 22, color: Colors.white24),
              ),
            ),
            child: Tooltip(
              message: 'Drag to another stage (like web)',
              child: Padding(
                padding: const EdgeInsets.only(right: 4, top: 8),
                child: Icon(Icons.drag_indicator, size: 24, color: Colors.white.withOpacity(0.45)),
              ),
            ),
          ),
          Expanded(
            child: LongPressDraggable<TaskDragPayload>(
              data: payload,
              feedback: feedbackCard,
              childWhenDragging: Opacity(
                opacity: 0.38,
                child: _taskCard(t, stageColor, withSideMargin: false),
              ),
              child: _taskCard(t, stageColor, withSideMargin: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(dynamic t, Color stageColor, {bool withSideMargin = true}) {
    final sc = t['subtask_count'] ?? 0; final cs = t['completed_subtask_count'] ?? 0; final pr = (t['subtask_progress'] ?? 0).toDouble();
    final done = t['completed'] == true;
    final canDelete = t['can_delete'] == true;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: withSideMargin ? 10 : 0, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _TaskSubtasksPage(
          apiService: widget.apiService, taskId: t['id'], taskName: t['name'] ?? '', taskDesc: t['description'] ?? '', employees: _employees, isManager: _isManager))).then((_) => _load()),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: AppTheme.glassPanel(borderRadius: 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: stageColor),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        TaskStatusDropdown(
                          key: ValueKey<String>('kt_${t['id']}_${t['status']}_${t['completed']}'),
                          taskId: t['id'] as int,
                          task: t,
                          apiService: widget.apiService,
                          onUpdated: _load,
                          compact: true,
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _showTaskViewKanban(t),
                                    icon: Icon(Icons.visibility_outlined, size: 15, color: Color(0xFF93C5FD)),
                                    label: Text('View', style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11, fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      side: BorderSide(color: Color(0xFF3B82F6).withOpacity(0.55)),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _showEditTaskKanban(t),
                                    icon: Icon(Icons.edit_outlined, size: 15, color: Color(0xFFA78BFA)),
                                    label: Text('Edit', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      side: BorderSide(color: Color(0xFF8B5CF6).withOpacity(0.5)),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _uploadTaskFileFromKanban(t),
                                    icon: Icon(Icons.upload_file_rounded, size: 15, color: Color(0xFF34D399)),
                                    label: Text('Upload file', style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      side: BorderSide(color: Color(0xFF10B981).withOpacity(0.45)),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: done
                              ? OutlinedButton.icon(
                                  onPressed: () => _toggleTaskComplete(t),
                                  icon: Icon(Icons.replay_rounded, size: 16, color: Color(0xFFFBBF24)),
                                  label: Text('Restore', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.w600)),
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    side: BorderSide(color: Color(0xFFFBBF24).withOpacity(0.5)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                )
                              : FilledButton.icon(
                                  onPressed: () => _toggleTaskComplete(t),
                                  icon: Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.white),
                                  label: Text('Mark complete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Color(0xFF10B981).withOpacity(0.9),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                        ),
                        SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                t['name'] ?? '',
                                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, decoration: done ? TextDecoration.lineThrough : null),
                              ),
                            ),
                            SizedBox(width: 8),
                            TaskStatusBadge(task: t),
                          ],
                        ),
                        if ((t['description'] ?? '').toString().isNotEmpty) ...[SizedBox(height: 4), Text(t['description'], style: TextStyle(color: Colors.white30, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis)],
                        if (sc > 0) ...[SizedBox(height: 10), Row(children: [Text('Subtasks: $cs/$sc', style: TextStyle(color: Colors.white38, fontSize: 10)), Spacer(), Text('${pr.toInt()}%', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))]),
                          SizedBox(height: 4), ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: pr / 100, backgroundColor: Colors.white.withOpacity(0.08), valueColor: AlwaysStoppedAnimation(Color(0xFF8B5CF6)), minHeight: 3))],
                        SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (t['user_name'] != null) ...[
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Color(0xFF334155),
                                    child: Text((t['user_name'] ?? '?')[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: 9)),
                                  ),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      t['user_name'] ?? '',
                                      style: TextStyle(color: Colors.white30, fontSize: 10),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                if (canDelete)
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    constraints: BoxConstraints.tightFor(width: 28, height: 28),
                                    tooltip: 'Delete task',
                                    onPressed: () => _deleteTask(t),
                                  ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Text('subtasks >', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 9, fontWeight: FontWeight.w600)),
                                if (t['due_date'] != null) ...[
                                  Spacer(),
                                  Icon(Icons.schedule, size: 10, color: Colors.white24),
                                  SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      t['due_date'] ?? '',
                                      style: TextStyle(color: Colors.white24, fontSize: 10),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
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
              child: Icon(Icons.chevron_left, color: Colors.white54, size: 20))),
          Expanded(child: Text('${mn[m]} $y', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          GestureDetector(onTap: () => setState(() => _calMonth = DateTime(y, m + 1)),
            child: Container(padding: EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.chevron_right, color: Colors.white54, size: 20))),
          SizedBox(width: 8),
          GestureDetector(onTap: () => setState(() => _calMonth = now),
            child: Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Color(0xFF8B5CF6).withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: Color(0xFF8B5CF6).withOpacity(0.3))),
              child: Text('Today', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.w700)))),
        ])),
      // Day headers
      Container(margin: EdgeInsets.symmetric(horizontal: 16), padding: EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), border: Border.symmetric(vertical: BorderSide(color: Colors.white.withOpacity(0.06)))),
        child: Row(children: ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map((d) =>
          Expanded(child: Text(d, textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)))).toList())),
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
                color: isToday ? Color(0xFF8B5CF6).withOpacity(0.08) : Colors.transparent),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Day number
                Padding(padding: EdgeInsets.fromLTRB(6, 4, 6, 2), child: isToday
                  ? Container(width: 22, height: 22, decoration: BoxDecoration(color: Color(0xFF8B5CF6).withOpacity(0.25), borderRadius: BorderRadius.circular(6)),
                      child: Center(child: Text('$day', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.w800))))
                  : Text('$day', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600))),
                // Events
                ...evts.take(3).map((e) => _calEvent(e)),
                if (evts.length > 3) Padding(padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('+${evts.length - 3} more', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 7, fontWeight: FontWeight.w700))),
              ]));
          }))),
      // Legend
      Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Row(children: [
        _legendDot(Color(0xFF8B5CF6), 'Task'), SizedBox(width: 10),
        _legendDot(Color(0xFFF59E0B), 'High'), SizedBox(width: 10),
        _legendDot(Color(0xFF3B82F6), 'Active'), SizedBox(width: 10),
        _legendDot(Color(0xFF10B981), 'Done/Due'),
      ])),
    ]);
  }

  Widget _calEvent(dynamic e) {
    final type = e['type'] ?? 'task';
    final completed = e['completed'] == true;
    final priority = e['priority'] ?? 'medium';
    Color bg;
    if (type == 'deadline') { bg = Color(0xFFEF4444); }
    else if (type == 'due_date') { bg = Color(0xFF10B981); }
    else if (completed) { bg = Color(0xFF10B981); }
    else if (priority == 'high') { bg = Color(0xFFF59E0B); }
    else { bg = Color(0xFF8B5CF6); }

    return GestureDetector(
      onTap: () {
        final taskId = e['id'];
        if (taskId != null && taskId != 0) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => _TaskSubtasksPage(
            apiService: widget.apiService, taskId: taskId, taskName: e['title'] ?? '', taskDesc: '', employees: _employees, isManager: _isManager,
          ))).then((_) => _load());
        }
      },
      child: Container(margin: EdgeInsets.fromLTRB(3, 0, 3, 2), padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(e['title'] ?? '', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
    );
  }

  Widget _legendDot(Color c, String label) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    SizedBox(width: 4), Text(label, style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600)),
  ]);
}

class _TaskSubtasksPage extends StatefulWidget {
  final ApiService apiService; final int taskId; final String taskName, taskDesc; final List<dynamic> employees; final bool isManager;
  const _TaskSubtasksPage({required this.apiService, required this.taskId, required this.taskName, required this.taskDesc, required this.employees, required this.isManager});
  @override
  State<_TaskSubtasksPage> createState() => _TaskSubtasksPageState();
}
class _TaskSubtasksPageState extends State<_TaskSubtasksPage> {
  List<dynamic> _subtasks = [];
  bool _isLoading = true;
  Map<String, dynamic>? _taskDetail;
  List<dynamic> _taskAttachments = [];
  int get _total => _subtasks.length;
  int get _done => _subtasks.where((s) => s['completed'] == true).length;
  double get _progress => _total == 0 ? 0 : (_done / _total) * 100;
  String get _displayName => (_taskDetail?['name'] ?? widget.taskName).toString();
  String get _displayDesc => (_taskDetail?['description'] ?? widget.taskDesc).toString();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final rTask = await widget.apiService.getTask(widget.taskId);
    final r = await widget.apiService.getSubTasks(widget.taskId);
    final rAtt = await widget.apiService.getTaskAttachments(widget.taskId);
    if (!mounted) return;
    if (rTask['success'] == true && rTask['data'] != null) {
      _taskDetail = Map<String, dynamic>.from(rTask['data'] as Map);
    }
    if (r['success'] == true) {
      _subtasks = r['data'] ?? [];
    }
    if (rAtt['success'] == true) {
      final raw = rAtt['data'];
      _taskAttachments = raw is List ? List<dynamic>.from(raw) : <dynamic>[];
    }
    setState(() => _isLoading = false);
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  Future<void> _pickAndUploadTaskFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    List<int>? bytes = f.bytes?.toList();
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null || f.name.isEmpty) return;
    final up = await widget.apiService.uploadTaskAttachment(widget.taskId, bytes, f.name);
    if (!mounted) return;
    if (up['success'] == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File uploaded')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(up['error']?.toString() ?? 'Upload failed')),
      );
    }
  }

  Future<void> _uploadSubtaskFile(dynamic st) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    List<int>? bytes = f.bytes?.toList();
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) return;
    final up = await widget.apiService.uploadSubTaskAttachment(
      widget.taskId,
      st['id'] as int,
      bytes,
      f.name,
    );
    if (!mounted) return;
    if (up['success'] == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File uploaded')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(up['error']?.toString() ?? 'Upload failed')),
      );
    }
  }

  Future<void> _showSubtaskFiles(dynamic st) async {
    final id = st['id'] as int;
    final res = await widget.apiService.getSubTaskAttachments(widget.taskId, id);
    final list = (res['success'] == true) ? (res['data'] as List<dynamic>? ?? []) : <dynamic>[];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  st['summary']?.toString() ?? 'Subtask',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const Text('No files yet', style: TextStyle(color: AppTheme.textMuted))
                else
                  ...list.map(
                    (a) => ListTile(
                      leading: const Icon(Icons.attach_file, color: AppTheme.primaryBright),
                      title: Text(
                        a['file_name']?.toString() ?? 'file',
                        style: const TextStyle(color: AppTheme.textPrimary),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openUrl(a['file_url']?.toString());
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _uploadSubtaskFile(st);
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload file'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditTaskDialog() {
    final t = _taskDetail;
    final taskMap = t ?? <String, dynamic>{};
    final nc = TextEditingController(text: _displayName);
    final dc = TextEditingController(text: _displayDesc.isEmpty ? '' : _displayDesc);
    final dueC = TextEditingController(text: (t?['due_date'] ?? '').toString());
    String pri = (t?['priority'] ?? 'medium').toString();
    if (!['low', 'medium', 'high'].contains(pri)) pri = 'medium';
    final rawAssignee = _parseUserId(taskMap['user']) ?? _parseUserId(taskMap['user_id']);
    final assigneeMenuItems = buildTaskAssigneeDropdownItems(widget.employees, taskMap, rawAssignee);
    int? assignee = coerceAssigneeDropdownValue(rawAssignee, assigneeMenuItems);
    bool attReq = t?['is_attachment_required'] == true;
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          title: Text('Edit task', style: TextStyle(color: AppTheme.textPrimary)),
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
                            style: TextStyle(color: sel ? c : Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Attachment required to complete', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                  value: attReq,
                  onChanged: (v) => setD(() => attReq = v),
                  activeThumbColor: Color(0xFF8B5CF6),
                ),
                if (assigneeMenuItems.length > 1) ...[
                  SizedBox(height: 6),
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
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text('Cancel', style: TextStyle(color: AppTheme.primaryBright))),
            FilledButton(
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
                if (d.isNotEmpty) {
                  body['due_date'] = d;
                }
                if (assignee != null) body['assignee_id'] = assignee;
                final nav = Navigator.of(dialogCtx);
                final r = await widget.apiService.updateTask(widget.taskId, body);
                if (!mounted) return;
                if (r['success'] == true) {
                  nav.pop();
                  _load();
                } else {
                  messenger.showSnackBar(SnackBar(content: Text(r['error']?.toString() ?? 'Could not save')));
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
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
  Future<void> _toggle(int id) async {
    final r = await widget.apiService.toggleSubTask(widget.taskId, id);
    if (!mounted) return;
    if (r['success'] == true) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not update subtask')),
      );
    }
  }
  Future<void> _del(int id, String s) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: Color(0xFF1e293b),
      title: Text('Delete "$s"?', style: TextStyle(color: Colors.white)),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: TextStyle(color: Colors.red)))]));
    if (ok == true) { await widget.apiService.deleteSubTask(widget.taskId, id); _load(); }
  }
  Color _pc(String p) { switch(p){ case 'high': return Color(0xFFEF4444); case 'medium': return Color(0xFFF59E0B); default: return Color(0xFF10B981); } }
  Widget _tf(TextEditingController c, String h, {int ml=1}) => TextField(controller: c, maxLines: ml, style: TextStyle(color: Colors.white),
    decoration: InputDecoration(hintText: h, hintStyle: TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)));
  void _showDialog({dynamic st}) {
    final sc = TextEditingController(text: st?['summary'] ?? '');
    final dc = TextEditingController(text: st?['description'] ?? '');
    String pri = st?['priority'] ?? 'medium';
    String status = st?['status'] ?? 'to_do';
    final rawAssignee = _parseUserId(st?['assignee']);
    final assigneeMenuItems = buildTaskAssigneeDropdownItems(
      widget.employees,
      {'user_name': st?['assignee_name']},
      rawAssignee,
    );
    int? assignee = coerceAssigneeDropdownValue(rawAssignee, assigneeMenuItems);
    final isEdit = st != null;
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.1))),
          title: Text(isEdit ? 'Edit SubTask' : 'Add SubTask', style: TextStyle(color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tf(sc, 'Summary *'),
                SizedBox(height: 10),
                _tf(dc, 'Description', ml: 3),
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
                            style: TextStyle(color: sel ? c : Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
                Text('Status', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: ['to_do', 'in_progress', 'done'].contains(status) ? status : 'to_do',
                      isExpanded: true,
                      dropdownColor: AppTheme.surface2,
                      icon: Icon(Icons.expand_more_rounded, color: AppTheme.textMuted),
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 'to_do', child: Text('To do')),
                        DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
                        DropdownMenuItem(value: 'done', child: Text('Done')),
                      ],
                      onChanged: (v) => setD(() => status = v ?? 'to_do'),
                    ),
                  ),
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
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text('Cancel', style: TextStyle(color: AppTheme.primaryBright))),
            FilledButton(
              onPressed: () async {
                if (sc.text.trim().isEmpty) {
                  messenger.showSnackBar(const SnackBar(content: Text('Enter a summary')));
                  return;
                }
                final nav = Navigator.of(dialogCtx);
                if (isEdit) {
                  final data = <String, dynamic>{
                    'summary': sc.text.trim(),
                    'description': dc.text.trim(),
                    'priority': pri,
                    'status': status,
                  };
                  if (assignee != null) data['assignee_id'] = assignee;
                  final r = await widget.apiService.updateSubTask(widget.taskId, st['id'] as int, data);
                  if (!mounted) return;
                  if (r['success'] == true) {
                    nav.pop();
                    _load();
                  } else {
                    messenger.showSnackBar(SnackBar(content: Text(r['error']?.toString() ?? 'Could not save')));
                  }
                } else {
                  final r = await widget.apiService.createSubTask(
                    widget.taskId,
                    summary: sc.text.trim(),
                    description: dc.text.trim(),
                    priority: pri,
                    status: status,
                    assigneeId: assignee,
                  );
                  if (!mounted) return;
                  if (r['success'] == true) {
                    nav.pop();
                    _load();
                  } else {
                    messenger.showSnackBar(SnackBar(content: Text(r['error']?.toString() ?? 'Could not create subtask')));
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2563eb), Color(0xFF1e40af), Color(0xFF1e3a5f), Color(0xFF0f172a)])),
      child: SafeArea(child: Column(children: [
        Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.arrow_back, color: Colors.white54, size: 22)), SizedBox(width: 10),
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Color(0xFF8B5CF6).withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.checklist, color: Color(0xFF8B5CF6), size: 20)),
            SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_displayName, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (_displayDesc.isNotEmpty) Text(_displayDesc, style: TextStyle(color: Colors.white30, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            IconButton(
              tooltip: 'Edit task',
              onPressed: _showEditTaskDialog,
              icon: Icon(Icons.edit_outlined, color: Colors.white54, size: 22),
            ),
          ]),
          SizedBox(height: 12),
          Row(children: [_hs('$_total','Total',Color(0xFF64748B)), SizedBox(width: 10), _hs('$_done','Done',Color(0xFF10B981)), SizedBox(width: 10), _hs('${_progress.toInt()}%','Progress',Color(0xFF8B5CF6))]),
          SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _progress / 100, backgroundColor: Colors.white.withOpacity(0.1), valueColor: AlwaysStoppedAnimation(Color(0xFF8B5CF6)), minHeight: 4)),
        ])),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.attach_file_rounded, size: 18, color: Color(0xFFA78BFA)),
                  SizedBox(width: 8),
                  Text('Files on this task', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  Spacer(),
                  TextButton.icon(
                    onPressed: _isLoading ? null : _pickAndUploadTaskFile,
                    icon: Icon(Icons.upload_file_rounded, size: 16, color: Color(0xFF8B5CF6)),
                    label: Text('Upload', style: TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              if (_taskAttachments.isEmpty)
                Text('No files yet — tap Upload to add.', style: TextStyle(color: Colors.white38, fontSize: 11))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _taskAttachments.map<Widget>((a) {
                    final name = a['file_name']?.toString() ?? 'file';
                    return ActionChip(
                      avatar: Icon(Icons.insert_drive_file_outlined, size: 16, color: Colors.white70),
                      label: Text(name, overflow: TextOverflow.ellipsis),
                      backgroundColor: Colors.white.withOpacity(0.06),
                      labelStyle: TextStyle(color: Colors.white70, fontSize: 12),
                      onPressed: () => _openUrl(a['file_url']?.toString()),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
          Text('SubTasks ($_total)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), Spacer(),
          GestureDetector(onTap: () => _showDialog(), child: Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Color(0xFF8B5CF6), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [Icon(Icons.add, color: Colors.white, size: 16), SizedBox(width: 4), Text('Add', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))]))),
        ])),
        Expanded(child: _isLoading ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)))
          : _subtasks.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.checklist, size: 64, color: Colors.white24), SizedBox(height: 12), Text('No SubTasks Yet', style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.bold))]))
          : ListView.builder(padding: EdgeInsets.symmetric(horizontal: 16), itemCount: _subtasks.length, itemBuilder: (ctx, i) => _stCard(_subtasks[i]))),
      ]))));
  }
  Widget _hs(String v, String l, Color c) => Expanded(child: Container(padding: EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.2))),
    child: Column(children: [Text(v, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), Text(l, style: TextStyle(color: Colors.white38, fontSize: 10))])));
  Widget _stCard(dynamic st) {
    final isDone = st['completed'] == true;
    return Container(margin: EdgeInsets.only(bottom: 12), padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(onTap: () => _toggle(st['id']), child: Container(width: 22, height: 22,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: isDone ? Color(0xFF10B981) : Colors.white38, width: 2), color: isDone ? Color(0xFF10B981) : Colors.transparent),
            child: isDone ? Icon(Icons.check, size: 14, color: Colors.white) : null)),
          SizedBox(width: 8),
          SubtaskStatusBadge(subtask: st),
          Spacer(),
          GestureDetector(onTap: () => _showDialog(st: st), child: Container(padding: EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)), child: Icon(Icons.edit, size: 14, color: Colors.white38))),
          SizedBox(width: 6),
          GestureDetector(onTap: () => _del(st['id'], st['summary'] ?? ''), child: Container(padding: EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)), child: Icon(Icons.delete, size: 14, color: Colors.redAccent.withOpacity(0.6)))),
        ]),
        SizedBox(height: 10),
        Text(st['summary'] ?? '', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, decoration: isDone ? TextDecoration.lineThrough : null)),
        if ((st['description'] ?? '').toString().isNotEmpty) ...[SizedBox(height: 6), Text(st['description'], style: TextStyle(color: Colors.white30, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)],
        SizedBox(height: 10),
        SubtaskStatusDropdown(
          key: ValueKey<String>('pss_${st['id']}_${st['status']}_${st['completed']}'),
          taskId: widget.taskId,
          subtaskId: st['id'] as int,
          subtask: st,
          apiService: widget.apiService,
          onUpdated: _load,
        ),
        SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: isDone
              ? OutlinedButton.icon(
                  onPressed: () => _toggle(st['id'] as int),
                  icon: Icon(Icons.replay_rounded, size: 16, color: Color(0xFFFBBF24)),
                  label: Text('Restore', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: Color(0xFFFBBF24).withOpacity(0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                )
              : FilledButton.icon(
                  onPressed: () => _toggle(st['id'] as int),
                  icon: Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.white),
                  label: Text('Mark complete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Color(0xFF10B981).withOpacity(0.9),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
        ),
        SizedBox(height: 10),
        Row(children: [
          if (st['assignee_name'] != null) ...[CircleAvatar(radius: 10, backgroundColor: Color(0xFF334155), child: Text((st['assignee_name'] ?? '?')[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: 9))),
            SizedBox(width: 6), Text(st['assignee_name'] ?? '', style: TextStyle(color: Colors.white38, fontSize: 11))]
          else Text('Unassigned', style: TextStyle(color: Colors.white24, fontSize: 11)),
          Spacer(),
          if (st['due_date'] != null) ...[Icon(Icons.schedule, size: 11, color: Colors.white24), SizedBox(width: 3), Text(st['due_date'], style: TextStyle(color: Colors.white24, fontSize: 10))],
        ]),
        SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.attach_file_rounded, size: 14, color: Colors.white38),
            SizedBox(width: 6),
            Text(
              '${st['attachment_count'] ?? 0} file(s)',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            if (st['is_attachment_required'] == true) ...[
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(0xFFF59E0B).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Required', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 9, fontWeight: FontWeight.w600)),
              ),
            ],
            Spacer(),
            TextButton.icon(
              onPressed: () => _uploadSubtaskFile(st),
              icon: Icon(Icons.upload_file_rounded, size: 14, color: Color(0xFF8B5CF6)),
              label: Text('Upload', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 12, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
            TextButton(
              onPressed: () => _showSubtaskFiles(st),
              child: Text('View', style: TextStyle(color: Colors.white54, fontSize: 12)),
              style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ],
        ),
      ]));
  }
}
