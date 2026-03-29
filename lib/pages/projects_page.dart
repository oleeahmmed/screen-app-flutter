// projects_page.dart - Jira-style Project Management with Tasks & SubTasks

import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';

class ProjectsPage extends StatefulWidget {
  final ApiService apiService;
  const ProjectsPage({required this.apiService});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  List<dynamic> _tasks = [];
  bool _isLoading = true;
  int? _selectedTaskId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _refreshTimer = Timer.periodic(Duration(seconds: 30), (_) => _loadTasks());
  }

  Future<void> _loadTasks() async {
    final result = await widget.apiService.getTasks();
    if (result['success'] && mounted) {
      setState(() { _tasks = result['data'] ?? []; _isLoading = false; });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Group tasks by project
  Map<String, List<dynamic>> get _groupedTasks {
    final map = <String, List<dynamic>>{};
    for (final t in _tasks) {
      final projectName = t['project_name'] ?? 'No Project';
      map.putIfAbsent(projectName, () => []);
      map[projectName]!.add(t);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF2563eb), Color(0xFF1e40af), Color(0xFF1e3a5f), Color(0xFF0f172a)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Projects', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  GestureDetector(
                    onTap: _loadTasks,
                    child: Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.refresh, color: Colors.white54, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            // Stats
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(child: _statCard('Projects', '${_groupedTasks.length}', Color(0xFF8B5CF6))),
                SizedBox(width: 12),
                Expanded(child: _statCard('Total Tasks', '${_tasks.length}', Color(0xFF3B82F6))),
              ]),
            ),
            SizedBox(height: 16),
            // Project list
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : _tasks.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.folder_open, size: 64, color: Colors.white24),
                          SizedBox(height: 12),
                          Text('No projects yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
                          SizedBox(height: 4),
                          Text('Tasks assigned to you will appear here', style: TextStyle(color: Colors.white38, fontSize: 13)),
                        ]))
                      : ListView(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          children: _groupedTasks.entries.map((entry) => _buildProjectSection(entry.key, entry.value)).toList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectSection(String projectName, List<dynamic> tasks) {
    final completedCount = tasks.where((t) => t['completed'] ?? false).length;
    final totalSubtasks = tasks.fold<int>(0, (sum, t) => sum + ((t['subtask_count'] ?? 0) as int));
    final completedSubtasks = tasks.fold<int>(0, (sum, t) => sum + ((t['completed_subtask_count'] ?? 0) as int));
    final progress = tasks.isEmpty ? 0.0 : completedCount / tasks.length;

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project header
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.folder, color: Color(0xFF8B5CF6), size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text(projectName, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                  Text('$completedCount/${tasks.length}', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
                SizedBox(height: 8),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation(Color(0xFF8B5CF6)),
                    minHeight: 4,
                  ),
                ),
                SizedBox(height: 6),
                Row(children: [
                  Text('${(progress * 100).toInt()}% complete', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  if (totalSubtasks > 0) ...[
                    SizedBox(width: 12),
                    Icon(Icons.account_tree, size: 11, color: Colors.white38),
                    SizedBox(width: 3),
                    Text('$completedSubtasks/$totalSubtasks subtasks', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ]),
              ],
            ),
          ),
          // Tasks in this project
          ...tasks.map((task) => _ProjectTaskTile(
            task: task,
            apiService: widget.apiService,
            isSelected: _selectedTaskId == task['id'],
            onTap: () => setState(() => _selectedTaskId = _selectedTaskId == task['id'] ? null : task['id']),
            onRefresh: _loadTasks,
          )),
          SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
      ]),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

// ─── Project Task Tile with expandable subtasks ───

class _ProjectTaskTile extends StatefulWidget {
  final dynamic task;
  final ApiService apiService;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const _ProjectTaskTile({
    required this.task,
    required this.apiService,
    required this.isSelected,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  State<_ProjectTaskTile> createState() => _ProjectTaskTileState();
}

class _ProjectTaskTileState extends State<_ProjectTaskTile> {
  List<dynamic> _subtasks = [];
  bool _loading = false;

  @override
  void didUpdateWidget(covariant _ProjectTaskTile old) {
    super.didUpdateWidget(old);
    if (widget.isSelected && !old.isSelected) _loadSubtasks();
  }

  Future<void> _loadSubtasks() async {
    setState(() => _loading = true);
    final result = await widget.apiService.getSubTasks(widget.task['id']);
    if (result['success'] && mounted) {
      setState(() { _subtasks = result['data'] ?? []; _loading = false; });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleSubtask(int subtaskId) async {
    await widget.apiService.toggleSubTask(widget.task['id'], subtaskId);
    _loadSubtasks();
    widget.onRefresh();
  }

  Color _priorityColor(String p) {
    switch (p) { case 'high': return Color(0xFFE74C3C); case 'medium': return Color(0xFFF59E0B); default: return Color(0xFF10B981); }
  }

  Color _statusColor(String s) {
    switch (s) { case 'in_progress': return Color(0xFF3B82F6); case 'done': return Color(0xFF10B981); default: return Color(0xFF94A3B8); }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isCompleted = task['completed'] ?? false;
    final subtaskCount = task['subtask_count'] ?? 0;
    final completedSubtasks = task['completed_subtask_count'] ?? 0;
    final status = task['status'] ?? 'pending';

    return Column(
      children: [
        InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted ? Color(0xFF10B981) : _statusColor(status),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task['name'] ?? '',
                        style: TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 3),
                      Row(children: [
                        if (task['priority'] != null) ...[
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: _priorityColor(task['priority']).withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                            child: Text(task['priority'], style: TextStyle(color: _priorityColor(task['priority']), fontSize: 9, fontWeight: FontWeight.w600)),
                          ),
                          SizedBox(width: 6),
                        ],
                        if (subtaskCount > 0) ...[
                          Icon(Icons.account_tree, size: 10, color: Colors.white38),
                          SizedBox(width: 2),
                          Text('$completedSubtasks/$subtaskCount', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                        if (task['due_date'] != null) ...[
                          SizedBox(width: 6),
                          Icon(Icons.schedule, size: 10, color: Colors.white38),
                          SizedBox(width: 2),
                          Text(task['due_date'], style: TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ]),
                    ],
                  ),
                ),
                Icon(widget.isSelected ? Icons.expand_less : Icons.expand_more, color: Colors.white24, size: 18),
              ],
            ),
          ),
        ),
        // Expanded subtasks
        if (widget.isSelected) ...[
          if (_loading)
            Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white38))))
          else if (_subtasks.isEmpty)
            Padding(padding: EdgeInsets.only(left: 40, bottom: 8), child: Text('No subtasks', style: TextStyle(color: Colors.white24, fontSize: 11)))
          else
            ..._subtasks.map((st) {
              final isDone = st['completed'] ?? false;
              final stStatus = st['status'] ?? 'to_do';
              final statusLabels = {'to_do': 'To Do', 'in_progress': 'In Progress', 'done': 'Done'};
              return InkWell(
                onTap: () => _toggleSubtask(st['id']),
                child: Padding(
                  padding: EdgeInsets.only(left: 40, right: 16, top: 4, bottom: 4),
                  child: Row(children: [
                    Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: isDone ? Color(0xFF10B981) : Colors.white30, width: 1.5),
                        color: isDone ? Color(0xFF10B981) : Colors.transparent,
                      ),
                      child: isDone ? Icon(Icons.check, size: 10, color: Colors.white) : null,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        st['summary'] ?? '',
                        style: TextStyle(color: Colors.white70, fontSize: 12, decoration: isDone ? TextDecoration.lineThrough : null),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: _statusColor(stStatus).withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                      child: Text(statusLabels[stStatus] ?? stStatus, style: TextStyle(color: _statusColor(stStatus), fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              );
            }),
          SizedBox(height: 4),
        ],
      ],
    );
  }
}
