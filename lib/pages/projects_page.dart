import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ProjectsPage extends StatefulWidget {
  final ApiService apiService;
  const ProjectsPage({required this.apiService});
  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  List<dynamic> _projects = [];
  bool _isLoading = true;
  String _search = '';
  @override
  void initState() { super.initState(); _loadProjects(); }
  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    final r = await widget.apiService.getProjects();
    if (r['success'] && mounted) setState(() { _projects = r['data'] ?? []; _isLoading = false; });
    else if (mounted) setState(() => _isLoading = false);
  }
  List<dynamic> get _filtered {
    if (_search.isEmpty) return _projects;
    final q = _search.toLowerCase();
    return _projects.where((p) => (p['name'] ?? '').toString().toLowerCase().contains(q)).toList();
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
        }, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8B5CF6)), child: Text('Create'))],
    ));
  }
Widget _dtf(TextEditingController c, String h, {int ml=1}) => TextField(controller: c, maxLines: ml, style: TextStyle(color: Colors.white),
    decoration: InputDecoration(hintText: h, hintStyle: TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)));
  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2563eb), Color(0xFF1e40af), Color(0xFF1e3a5f), Color(0xFF0f172a)])),
      child: SafeArea(child: Column(children: [
        Padding(padding: EdgeInsets.fromLTRB(24, 20, 24, 12), child: Row(children: [
          Icon(Icons.folder_open, color: Color(0xFF8B5CF6), size: 28), SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Projects', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('${_projects.length} projects', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ])),
          GestureDetector(onTap: _showCreateProjectDialog, child: Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: Color(0xFF8B5CF6), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.add, color: Colors.white, size: 20))),
          SizedBox(width: 8),
          GestureDetector(onTap: _loadProjects, child: Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.refresh, color: Colors.white54, size: 20))),
        ])),
        Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: TextField(onChanged: (v) => setState(() => _search = v), style: TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(hintText: 'Search projects...', hintStyle: TextStyle(color: Colors.white30), prefixIcon: Icon(Icons.search, color: Colors.white30, size: 20),
            filled: true, fillColor: Colors.white.withOpacity(0.06), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none), contentPadding: EdgeInsets.symmetric(vertical: 12)))),
        SizedBox(height: 16),
        Expanded(child: _isLoading ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)))
          : filtered.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.folder_open, size: 64, color: Colors.white24), SizedBox(height: 12), Text('No Projects Yet', style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.bold))]))
          : ListView.builder(padding: EdgeInsets.symmetric(horizontal: 24), itemCount: filtered.length, itemBuilder: (ctx, i) => _projectCard(filtered[i]))),
      ])),
    );
  }
  Widget _projectCard(dynamic p) {
    final comp = (p['completion_percentage'] ?? 0).toDouble();
    final st = p['status'] ?? 'planning'; final pri = p['priority'] ?? 'medium';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ProjectDetailPage(apiService: widget.apiService, projectId: p['id'], projectName: p['name'] ?? ''))).then((_) => _loadProjects()),
      child: Container(margin: EdgeInsets.only(bottom: 16), padding: EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(0.08))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Color(0xFF8B5CF6).withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.folder_open, color: Color(0xFF8B5CF6), size: 22)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name'] ?? '', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              Text(p['project_manager'] ?? '', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ])),
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _prc(pri))),
          ]),
          if ((p['description'] ?? '').toString().isNotEmpty) ...[SizedBox(height: 10), Text(p['description'], style: TextStyle(color: Colors.white38, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)],
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
        ])),
    );
  }
}

class _ProjectDetailPage extends StatefulWidget {
  final ApiService apiService; final int projectId; final String projectName;
  const _ProjectDetailPage({required this.apiService, required this.projectId, required this.projectName});
  @override
  State<_ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<_ProjectDetailPage> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _project; bool _isLoading = true;
  late TabController _tabCtrl; DateTime _calMonth = DateTime.now();
  @override
  void initState() { super.initState(); _tabCtrl = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }
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
        }, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8B5CF6)), child: Text('Add'))],
    )));
  }
  void _deleteStage(int sid, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: Color(0xFF1e293b),
      title: Text('Delete "$name"?', style: TextStyle(color: Colors.white)), content: Text('Tasks move to another stage.', style: TextStyle(color: Colors.white54)),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: TextStyle(color: Colors.red)))]));
    if (ok == true) { await widget.apiService.deleteStage(widget.projectId, sid); _load(); }
  }
  void _deleteTask(int tid) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: Color(0xFF1e293b),
      title: Text('Delete Task?', style: TextStyle(color: Colors.white)), content: Text('All subtasks deleted too.', style: TextStyle(color: Colors.white54)),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: TextStyle(color: Colors.red)))]));
    if (ok == true) { await widget.apiService.deleteTask(tid); _load(); }
  }
  void _showMoveTaskDialog(dynamic task) {
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: Color(0xFF1e293b), title: Text('Move Task', style: TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: _stages.map((s) => ListTile(
        leading: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: _parseHex(s['color'] ?? '#3B82F6'))),
        title: Text(s['name'] ?? '', style: TextStyle(color: Colors.white)),
        onTap: () async { Navigator.pop(ctx); await widget.apiService.moveTask(task['id'], s['id']); _load(); },
      )).toList())));
  }
  void _showEditProjectDialog() {
    final nc = TextEditingController(text: _project?['name'] ?? '');
    final dc = TextEditingController(text: _project?['description'] ?? '');
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: Color(0xFF1e293b), title: Text('Edit Project', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [_tf(nc, 'Project Name *'), SizedBox(height: 10), _tf(dc, 'Description', ml: 3)])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async { if (nc.text.trim().isEmpty) return; Navigator.pop(ctx);
          await widget.apiService.updateProject(widget.projectId, {'name': nc.text.trim(), 'description': dc.text.trim()}); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8B5CF6)), child: Text('Save'))],
    ));
  }
  void _deleteProject() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: Color(0xFF1e293b),
      title: Text('Delete Project?', style: TextStyle(color: Colors.white)),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: TextStyle(color: Colors.red)))]));
    if (ok == true) { await widget.apiService.deleteProject(widget.projectId); if (mounted) Navigator.pop(context); }
  }
  void _showCreateTaskInStageDialog(int stageId) {
    final nc = TextEditingController(); final dc = TextEditingController();
    String pri = 'medium'; int? assignee; String? due;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: Color(0xFF1e293b), title: Text('Create Task', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _tf(nc, 'Task Name *'), SizedBox(height: 10), _tf(dc, 'Description', ml: 2), SizedBox(height: 10),
        Row(children: ['low','medium','high'].map((p) { final s = pri == p; final c = _pc(p);
          return Expanded(child: GestureDetector(onTap: () => setD(() => pri = p), child: Container(margin: EdgeInsets.symmetric(horizontal: 3), padding: EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: s ? c.withOpacity(0.3) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: s ? c : Colors.white12)),
            child: Text(p[0].toUpperCase()+p.substring(1), textAlign: TextAlign.center, style: TextStyle(color: s ? c : Colors.white54, fontSize: 11, fontWeight: FontWeight.w600))))); }).toList()),
        if (_employees.isNotEmpty) ...[SizedBox(height: 10),
          Container(padding: EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
            child: DropdownButtonHideUnderline(child: DropdownButton<int?>(isExpanded: true, value: assignee, hint: Text('Assign to...', style: TextStyle(color: Colors.white30, fontSize: 13)), dropdownColor: Color(0xFF1e293b),
              items: [DropdownMenuItem<int?>(value: null, child: Text('Unassigned', style: TextStyle(color: Colors.white54, fontSize: 13))),
                ..._employees.map((e) => DropdownMenuItem<int?>(value: e['id'], child: Text(e['full_name'] ?? e['username'] ?? '', style: TextStyle(color: Colors.white, fontSize: 13))))],
              onChanged: (v) => setD(() => assignee = v))))],
        SizedBox(height: 10),
        GestureDetector(onTap: () async {
          final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2030),
            builder: (c, ch) => Theme(data: ThemeData.dark().copyWith(colorScheme: ColorScheme.dark(primary: Color(0xFF8B5CF6))), child: ch!));
          if (picked != null) setD(() => due = "${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}");
        }, child: Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [Icon(Icons.calendar_today, size: 16, color: Colors.white38), SizedBox(width: 8), Text(due ?? 'Due date', style: TextStyle(color: due != null ? Colors.white : Colors.white30, fontSize: 13))]))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async { if (nc.text.trim().isEmpty) return; Navigator.pop(ctx);
          await widget.apiService.createTask(name: nc.text.trim(), description: dc.text.trim(), priority: pri, dueDate: due, projectId: widget.projectId, stageId: stageId); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8B5CF6)), child: Text('Create'))],
    )));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2563eb), Color(0xFF1e40af), Color(0xFF1e3a5f), Color(0xFF0f172a)])),
      child: SafeArea(child: _isLoading ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)))
        : _project == null ? Center(child: Text('Failed to load', style: TextStyle(color: Colors.white54)))
        : Column(children: [_buildHeader(), _buildStats(), SizedBox(height: 8),
            TabBar(controller: _tabCtrl, indicatorColor: Color(0xFF8B5CF6), labelColor: Colors.white, unselectedLabelColor: Colors.white38, tabs: [Tab(text: 'Board'), Tab(text: 'Calendar')]),
            Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildBoard(), _buildCalendar()]))])),
    ));
  }
  Widget _buildHeader() {
    final p = _project!; final comp = (p['completion_percentage'] ?? 0).toDouble();
    return Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.arrow_back, color: Colors.white54, size: 22)), SizedBox(width: 10),
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
  Widget _buildStats() {
    final s = _project!['stats'] ?? {};
    return Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _sc('${s["total_tasks"]??0}','Tasks',Color(0xFF64748B)), SizedBox(width: 6), _sc('${s["in_progress_tasks"]??0}','Active',Color(0xFF3B82F6)),
      SizedBox(width: 6), _sc('${s["completed_tasks"]??0}','Done',Color(0xFF10B981)), SizedBox(width: 6),
      _sc('${s["total_subtasks"]??0}','Subtasks',Color(0xFF64748B)), SizedBox(width: 6), _sc('${(_project!["completion_percentage"]??0).toInt()}%','Progress',Color(0xFF8B5CF6)),
    ])));
  }
  Widget _sc(String v, String l, Color c) => Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.2))),
    child: Column(children: [Text(v, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)), Text(l, style: TextStyle(color: Colors.white38, fontSize: 9))]));
  Widget _buildBoard() {
    final stages = _stages; final unassigned = (_project!['unassigned_tasks'] as List?) ?? [];
    if (stages.isEmpty && unassigned.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.view_column, size: 64, color: Colors.white24), SizedBox(height: 12), Text('No stages yet', style: TextStyle(color: Colors.white54, fontSize: 16)), SizedBox(height: 12),
      ElevatedButton.icon(onPressed: _showAddStageDialog, icon: Icon(Icons.add, size: 18), label: Text('Add Stage'), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8B5CF6)))]));
    return ListView(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
      ...stages.map((s) => _stageSection(s)),
      if (unassigned.isNotEmpty) _stageSection({'name': 'No Stage', 'color': '#64748B', 'tasks': unassigned, 'id': null}),
      SizedBox(height: 80)]);
  }
  Widget _stageSection(dynamic stage) {
    final tasks = (stage['tasks'] as List?) ?? []; final color = _parseHex(stage['color'] ?? '#3B82F6'); final stageId = stage['id'];
    return Container(margin: EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.fromLTRB(12, 10, 4, 6), child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)), SizedBox(width: 8),
          Expanded(child: Text((stage['name'] ?? '').toString().toUpperCase(), style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1))),
          Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
            child: Text('${tasks.length}', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold))),
          if (stageId != null) ...[SizedBox(width: 4),
            PopupMenuButton<String>(icon: Icon(Icons.more_vert, color: Colors.white30, size: 18), color: Color(0xFF1e293b), padding: EdgeInsets.zero,
              onSelected: (v) { if (v=='add_task') _showCreateTaskInStageDialog(stageId); else if (v=='delete') _deleteStage(stageId, stage['name'] ?? ''); },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'add_task', child: Row(children: [Icon(Icons.add_task, color: Color(0xFF10B981), size: 16), SizedBox(width: 8), Text('Add Task', style: TextStyle(color: Colors.white, fontSize: 13))])),
                PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 16), SizedBox(width: 8), Text('Delete Stage', style: TextStyle(color: Colors.redAccent, fontSize: 13))]))])],
        ])),
        ...tasks.map((t) => _taskCard(t, color)),
        if (tasks.isEmpty) Padding(padding: EdgeInsets.only(left: 30, bottom: 12), child: Text('No tasks', style: TextStyle(color: Colors.white24, fontSize: 11))),
      ]));
  }
  Widget _taskCard(dynamic t, Color stageColor) {
    final sc = t['subtask_count'] ?? 0; final cs = t['completed_subtask_count'] ?? 0; final pr = (t['subtask_progress'] ?? 0).toDouble();
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _TaskSubtasksPage(
        apiService: widget.apiService, taskId: t['id'], taskName: t['name'] ?? '', taskDesc: t['description'] ?? '', employees: _employees, isManager: _isManager))).then((_) => _load()),
      child: Container(margin: EdgeInsets.symmetric(horizontal: 10, vertical: 4), padding: EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: t['priority']=='high' ? Color(0xFFEF4444) : stageColor, width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: _pc(t['priority'] ?? 'medium').withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
              child: Text((t['priority'] ?? 'medium').toString().toUpperCase(), style: TextStyle(color: _pc(t['priority'] ?? 'medium'), fontSize: 9, fontWeight: FontWeight.w700))),
            Spacer(),
            PopupMenuButton<String>(icon: Icon(Icons.more_horiz, color: Colors.white30, size: 18), color: Color(0xFF1e293b), padding: EdgeInsets.zero,
              onSelected: (v) { if (v=='move') _showMoveTaskDialog(t); else if (v=='delete') _deleteTask(t['id']); },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.swap_horiz, color: Color(0xFF3B82F6), size: 16), SizedBox(width: 8), Text('Move to Stage', style: TextStyle(color: Colors.white, fontSize: 13))])),
                PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 16), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13))]))])]),
          SizedBox(height: 6), Text(t['name'] ?? '', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          if ((t['description'] ?? '').toString().isNotEmpty) ...[SizedBox(height: 4), Text(t['description'], style: TextStyle(color: Colors.white30, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis)],
          if (sc > 0) ...[SizedBox(height: 10), Row(children: [Text('Subtasks: $cs/$sc', style: TextStyle(color: Colors.white38, fontSize: 10)), Spacer(), Text('${pr.toInt()}%', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))]),
            SizedBox(height: 4), ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: pr / 100, backgroundColor: Colors.white.withOpacity(0.08), valueColor: AlwaysStoppedAnimation(Color(0xFF8B5CF6)), minHeight: 3))],
          SizedBox(height: 8),
          Row(children: [
            if (t['user_name'] != null) ...[CircleAvatar(radius: 10, backgroundColor: Color(0xFF334155), child: Text((t['user_name'] ?? '?')[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: 9))),
              SizedBox(width: 6), Text(t['user_name'] ?? '', style: TextStyle(color: Colors.white30, fontSize: 10))],
            Spacer(), Text('subtasks >', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 9, fontWeight: FontWeight.w600)),
            if (t['due_date'] != null) ...[SizedBox(width: 8), Icon(Icons.schedule, size: 10, color: Colors.white24), SizedBox(width: 3), Text(t['due_date'] ?? '', style: TextStyle(color: Colors.white24, fontSize: 10))]])])));
  }
  Widget _buildCalendar() {
    final y = _calMonth.year; final m = _calMonth.month;
    final dim = DateTime(y, m + 1, 0).day; final fw = DateTime(y, m, 1).weekday;
    final mn = ['','January','February','March','April','May','June','July','August','September','October','November','December'];
    final ebd = <String, List<dynamic>>{}; for (final e in _calEvents) { final d = e['date'] ?? ''; ebd.putIfAbsent(d, () => []); ebd[d]!.add(e); }
    return Column(children: [
      Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [
        GestureDetector(onTap: () => setState(() => _calMonth = DateTime(y, m - 1)), child: Icon(Icons.chevron_left, color: Colors.white54)),
        Expanded(child: Text('${mn[m]} $y', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
        GestureDetector(onTap: () => setState(() => _calMonth = DateTime(y, m + 1)), child: Icon(Icons.chevron_right, color: Colors.white54))])),
      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Row(children: ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].map((d) =>
        Expanded(child: Text(d, textAlign: TextAlign.center, style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.w600)))).toList())),
      SizedBox(height: 4),
      Expanded(child: GridView.builder(padding: EdgeInsets.symmetric(horizontal: 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.75),
        itemCount: (fw - 1) + dim,
        itemBuilder: (ctx, i) {
          if (i < fw - 1) return SizedBox();
          final day = i - (fw - 1) + 1; if (day > dim) return SizedBox();
          final ds = '$y-${m.toString().padLeft(2,"0")}-${day.toString().padLeft(2,"0")}';
          final evts = ebd[ds] ?? []; final isToday = DateTime.now().year == y && DateTime.now().month == m && DateTime.now().day == day;
          return Container(margin: EdgeInsets.all(1),
            decoration: BoxDecoration(color: isToday ? Color(0xFF8B5CF6).withOpacity(0.2) : evts.isNotEmpty ? Colors.white.withOpacity(0.03) : Colors.transparent,
              borderRadius: BorderRadius.circular(6), border: isToday ? Border.all(color: Color(0xFF8B5CF6), width: 1) : null),
            child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [SizedBox(height: 2),
              Text('$day', style: TextStyle(color: isToday ? Color(0xFF8B5CF6) : Colors.white54, fontSize: 11, fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
              ...evts.take(3).map((e) { final c = e['type']=='deadline' ? Color(0xFFEF4444) : e['type']=='due_date' ? Color(0xFF10B981) : _pc(e['priority'] ?? 'medium');
                return Container(margin: EdgeInsets.symmetric(horizontal: 2, vertical: 1), padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(color: c.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                  child: Text(e['title'] ?? '', style: TextStyle(color: c, fontSize: 6, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)); })]));
        }))]);
  }
}

class _TaskSubtasksPage extends StatefulWidget {
  final ApiService apiService; final int taskId; final String taskName, taskDesc; final List<dynamic> employees; final bool isManager;
  const _TaskSubtasksPage({required this.apiService, required this.taskId, required this.taskName, required this.taskDesc, required this.employees, required this.isManager});
  @override
  State<_TaskSubtasksPage> createState() => _TaskSubtasksPageState();
}
class _TaskSubtasksPageState extends State<_TaskSubtasksPage> {
  List<dynamic> _subtasks = []; bool _isLoading = true;
  int get _total => _subtasks.length;
  int get _done => _subtasks.where((s) => s['completed'] == true).length;
  double get _progress => _total == 0 ? 0 : (_done / _total) * 100;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _isLoading = true);
    final r = await widget.apiService.getSubTasks(widget.taskId);
    if (r['success'] && mounted) setState(() { _subtasks = r['data'] ?? []; _isLoading = false; });
    else if (mounted) setState(() => _isLoading = false);
  }
  Future<void> _toggle(int id) async { await widget.apiService.toggleSubTask(widget.taskId, id); _load(); }
  Future<void> _del(int id, String s) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: Color(0xFF1e293b),
      title: Text('Delete "$s"?', style: TextStyle(color: Colors.white)),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: TextStyle(color: Colors.red)))]));
    if (ok == true) { await widget.apiService.deleteSubTask(widget.taskId, id); _load(); }
  }
  Color _pc(String p) { switch(p){ case 'high': return Color(0xFFEF4444); case 'medium': return Color(0xFFF59E0B); default: return Color(0xFF10B981); } }
  Color _stc(String s) { switch(s){ case 'in_progress': return Color(0xFF3B82F6); case 'done': return Color(0xFF10B981); default: return Color(0xFF94A3B8); } }
  Widget _tf(TextEditingController c, String h, {int ml=1}) => TextField(controller: c, maxLines: ml, style: TextStyle(color: Colors.white),
    decoration: InputDecoration(hintText: h, hintStyle: TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)));
  void _showDialog({dynamic st}) {
    final sc = TextEditingController(text: st?['summary'] ?? ''); final dc = TextEditingController(text: st?['description'] ?? '');
    String pri = st?['priority'] ?? 'medium'; String status = st?['status'] ?? 'to_do'; int? assignee = st?['assignee']; final isEdit = st != null;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: Color(0xFF1e293b), title: Text(isEdit ? 'Edit SubTask' : 'Add SubTask', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _tf(sc, 'Summary *'), SizedBox(height: 10), _tf(dc, 'Description', ml: 3), SizedBox(height: 10),
        Row(children: ['low','medium','high'].map((p) { final s = pri == p; final c = _pc(p);
          return Expanded(child: GestureDetector(onTap: () => setD(() => pri = p), child: Container(margin: EdgeInsets.symmetric(horizontal: 3), padding: EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: s ? c.withOpacity(0.3) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: s ? c : Colors.white12)),
            child: Text(p[0].toUpperCase()+p.substring(1), textAlign: TextAlign.center, style: TextStyle(color: s ? c : Colors.white54, fontSize: 10, fontWeight: FontWeight.w600))))); }).toList()),
        SizedBox(height: 10),
        Row(children: ['to_do','in_progress','done'].map((k) { final s = status == k; final c = _stc(k); final lb = k == 'to_do' ? 'To Do' : k == 'in_progress' ? 'Active' : 'Done';
          return Expanded(child: GestureDetector(onTap: () => setD(() => status = k), child: Container(margin: EdgeInsets.symmetric(horizontal: 3), padding: EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: s ? c.withOpacity(0.3) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: s ? c : Colors.white12)),
            child: Text(lb, textAlign: TextAlign.center, style: TextStyle(color: s ? c : Colors.white54, fontSize: 9, fontWeight: FontWeight.w600))))); }).toList()),
        if (widget.employees.isNotEmpty) ...[SizedBox(height: 10),
          Container(padding: EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
            child: DropdownButtonHideUnderline(child: DropdownButton<int?>(isExpanded: true, value: assignee, hint: Text('Assign to...', style: TextStyle(color: Colors.white30, fontSize: 13)), dropdownColor: Color(0xFF1e293b),
              items: [DropdownMenuItem<int?>(value: null, child: Text('Unassigned', style: TextStyle(color: Colors.white54, fontSize: 13))),
                ...widget.employees.map((e) => DropdownMenuItem<int?>(value: e['id'], child: Text(e['full_name'] ?? '', style: TextStyle(color: Colors.white, fontSize: 13))))],
              onChanged: (v) => setD(() => assignee = v))))],
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async { if (sc.text.trim().isEmpty) return; Navigator.pop(ctx);
          if (isEdit) { final data = <String, dynamic>{'summary': sc.text.trim(), 'description': dc.text.trim(), 'priority': pri, 'status': status};
            if (assignee != null) data['assignee_id'] = assignee;
            await widget.apiService.updateSubTask(widget.taskId, st['id'], data);
          } else { await widget.apiService.createSubTask(widget.taskId, summary: sc.text.trim(), description: dc.text.trim(), priority: pri); }
          _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8B5CF6)), child: Text('Save'))],
    )));
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
              Text(widget.taskName, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (widget.taskDesc.isNotEmpty) Text(widget.taskDesc, style: TextStyle(color: Colors.white30, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          ]),
          SizedBox(height: 12),
          Row(children: [_hs('$_total','Total',Color(0xFF64748B)), SizedBox(width: 10), _hs('$_done','Done',Color(0xFF10B981)), SizedBox(width: 10), _hs('${_progress.toInt()}%','Progress',Color(0xFF8B5CF6))]),
          SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _progress / 100, backgroundColor: Colors.white.withOpacity(0.1), valueColor: AlwaysStoppedAnimation(Color(0xFF8B5CF6)), minHeight: 4)),
        ])),
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
    final isDone = st['completed'] == true; final status = st['status'] ?? 'to_do'; final pri = st['priority'] ?? 'medium';
    final sl = {'to_do': 'To Do', 'in_progress': 'In Progress', 'done': 'Done'};
    return Container(margin: EdgeInsets.only(bottom: 12), padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(onTap: () => _toggle(st['id']), child: Container(width: 22, height: 22,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: isDone ? Color(0xFF10B981) : Colors.white38, width: 2), color: isDone ? Color(0xFF10B981) : Colors.transparent),
            child: isDone ? Icon(Icons.check, size: 14, color: Colors.white) : null)),
          SizedBox(width: 8),
          Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: _pc(pri).withOpacity(0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: _pc(pri).withOpacity(0.3))),
            child: Text(pri.toUpperCase(), style: TextStyle(color: _pc(pri), fontSize: 9, fontWeight: FontWeight.w700))),
          Spacer(),
          GestureDetector(onTap: () => _showDialog(st: st), child: Container(padding: EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)), child: Icon(Icons.edit, size: 14, color: Colors.white38))),
          SizedBox(width: 6),
          GestureDetector(onTap: () => _del(st['id'], st['summary'] ?? ''), child: Container(padding: EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)), child: Icon(Icons.delete, size: 14, color: Colors.redAccent.withOpacity(0.6)))),
        ]),
        SizedBox(height: 10),
        Text(st['summary'] ?? '', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, decoration: isDone ? TextDecoration.lineThrough : null)),
        if ((st['description'] ?? '').toString().isNotEmpty) ...[SizedBox(height: 6), Text(st['description'], style: TextStyle(color: Colors.white30, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)],
        SizedBox(height: 10),
        Row(children: [
          if (st['assignee_name'] != null) ...[CircleAvatar(radius: 10, backgroundColor: Color(0xFF334155), child: Text((st['assignee_name'] ?? '?')[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: 9))),
            SizedBox(width: 6), Text(st['assignee_name'] ?? '', style: TextStyle(color: Colors.white38, fontSize: 11))]
          else Text('Unassigned', style: TextStyle(color: Colors.white24, fontSize: 11)),
          Spacer(),
          if (st['due_date'] != null) ...[Icon(Icons.schedule, size: 11, color: Colors.white24), SizedBox(width: 3), Text(st['due_date'], style: TextStyle(color: Colors.white24, fontSize: 10)), SizedBox(width: 8)],
          Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _stc(status).withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: _stc(status).withOpacity(0.3))),
            child: Text(sl[status] ?? status, style: TextStyle(color: _stc(status), fontSize: 9, fontWeight: FontWeight.w700))),
        ]),
      ]));
  }
}
