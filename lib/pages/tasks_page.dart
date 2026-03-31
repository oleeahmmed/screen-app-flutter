// tasks_page.dart - Jira-style Tasks Page with SubTasks

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class TasksPage extends StatefulWidget {
  final ApiService apiService;
  const TasksPage({required this.apiService});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  List<dynamic> _tasks = [];
  bool _isLoading = true;
  String _filter = 'all'; // all, pending, completed
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
      setState(() {
        _tasks = result['data'] ?? [];
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _filteredTasks {
    if (_filter == 'pending') return _tasks.where((t) => !(t['completed'] ?? false)).toList();
    if (_filter == 'completed') return _tasks.where((t) => t['completed'] ?? false).toList();
    return _tasks;
  }

  Future<void> _toggleTask(int taskId) async {
    final result = await widget.apiService.toggleTask(taskId);
    if (result['success']) _loadTasks();
  }

  Future<void> _deleteTask(int taskId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF1e293b),
        title: Text('Delete Task?', style: TextStyle(color: Colors.white)),
        content: Text('This will also delete all subtasks.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await widget.apiService.deleteTask(taskId);
      _loadTasks();
    }
  }

  void _showCreateTaskDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'medium';
    bool isAttachmentRequired = false;
    PlatformFile? pickedFile;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Color(0xFF1e293b),
          title: Text('New Task', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogTextField(nameCtrl, 'Task Name'),
                SizedBox(height: 12),
                _dialogTextField(descCtrl, 'Description', maxLines: 3),
                SizedBox(height: 12),
                _prioritySelector(priority, (v) => setDialogState(() => priority = v)),
                SizedBox(height: 12),
                // Attachment Required checkbox
                Row(children: [
                  SizedBox(width: 24, height: 24, child: Checkbox(
                    value: isAttachmentRequired,
                    onChanged: (v) => setDialogState(() => isAttachmentRequired = v ?? false),
                    activeColor: Color(0xFF3B82F6), checkColor: Colors.white,
                  )),
                  SizedBox(width: 8),
                  Text('Attachment Required', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
                SizedBox(height: 12),
                // File picker
                GestureDetector(
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
                    if (result != null && result.files.isNotEmpty) {
                      setDialogState(() => pickedFile = result.files.first);
                    }
                  },
                  child: Container(
                    width: double.infinity, padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: pickedFile != null ? Color(0xFF3B82F6) : Colors.white12)),
                    child: Row(children: [
                      Icon(pickedFile != null ? Icons.check_circle : Icons.attach_file,
                        color: pickedFile != null ? Color(0xFF22C55E) : Colors.white38, size: 20),
                      SizedBox(width: 8),
                      Expanded(child: Text(pickedFile?.name ?? 'Attach file (optional)',
                        style: TextStyle(color: pickedFile != null ? Colors.white : Colors.white38, fontSize: 13),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (pickedFile != null) GestureDetector(
                        onTap: () => setDialogState(() => pickedFile = null),
                        child: Icon(Icons.close, color: Colors.white38, size: 16)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                List<int>? bytes;
                if (pickedFile != null && pickedFile!.path != null) {
                  bytes = await File(pickedFile!.path!).readAsBytes();
                }
                await widget.apiService.createTask(
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  priority: priority,
                  isAttachmentRequired: isAttachmentRequired,
                  attachmentBytes: bytes,
                  attachmentName: pickedFile?.name,
                );
                _loadTasks();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF3B82F6)),
              child: Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTaskDialog(dynamic task) {
    final nameCtrl = TextEditingController(text: task['name'] ?? '');
    final descCtrl = TextEditingController(text: task['description'] ?? '');
    String priority = task['priority'] ?? 'medium';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Color(0xFF1e293b),
          title: Text('Edit Task', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogTextField(nameCtrl, 'Task Name'),
                SizedBox(height: 12),
                _dialogTextField(descCtrl, 'Description', maxLines: 3),
                SizedBox(height: 12),
                _prioritySelector(priority, (v) => setDialogState(() => priority = v)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await widget.apiService.updateTask(task['id'], {
                  'name': nameCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'priority': priority,
                });
                _loadTasks();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF3B82F6)),
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogTextField(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _prioritySelector(String current, Function(String) onChanged) {
    return Row(
      children: ['low', 'medium', 'high'].map((p) {
        final isSelected = current == p;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(p),
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 4),
              padding: EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _getPriorityColor(p).withOpacity(0.3) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSelected ? _getPriorityColor(p) : Colors.white12),
              ),
              child: Text(
                p[0].toUpperCase() + p.substring(1),
                textAlign: TextAlign.center,
                style: TextStyle(color: isSelected ? _getPriorityColor(p) : Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _tasks.where((t) => !(t['completed'] ?? false)).length;
    final completed = _tasks.where((t) => t['completed'] ?? false).length;
    final displayTasks = _filteredTasks;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
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
                  Text('Tasks', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  Row(children: [
                    _iconBtn(Icons.refresh, _loadTasks),
                    SizedBox(width: 8),
                    _iconBtn(Icons.add, _showCreateTaskDialog, color: Color(0xFF3B82F6)),
                  ]),
                ],
              ),
            ),
            // Stats
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(child: _statCard('Pending', '$pending', Color(0xFFF59E0B))),
                SizedBox(width: 12),
                Expanded(child: _statCard('Done', '$completed', Color(0xFF10B981))),
              ]),
            ),
            SizedBox(height: 16),
            // Filter tabs
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _filterTab('All', 'all'),
                  SizedBox(width: 8),
                  _filterTab('Pending', 'pending'),
                  SizedBox(width: 8),
                  _filterTab('Done', 'completed'),
                ],
              ),
            ),
            SizedBox(height: 16),
            // Task list
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : displayTasks.isEmpty
                      ? Center(child: Text('No tasks found', style: TextStyle(color: Colors.white54, fontSize: 16)))
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          itemCount: displayTasks.length,
                          itemBuilder: (ctx, i) => _TaskCard(
                            task: displayTasks[i],
                            apiService: widget.apiService,
                            onToggle: () => _toggleTask(displayTasks[i]['id']),
                            onEdit: () => _showEditTaskDialog(displayTasks[i]),
                            onDelete: () => _deleteTask(displayTasks[i]['id']),
                            onRefresh: _loadTasks,
                            colorIndex: i,
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (color ?? Colors.white).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color ?? Colors.white54, size: 20),
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

  Widget _filterTab(String label, String value) {
    final isActive = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Color(0xFF3B82F6).withOpacity(0.3) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? Color(0xFF3B82F6) : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high': return Color(0xFFE74C3C);
      case 'medium': return Color(0xFFF59E0B);
      case 'low': return Color(0xFF10B981);
      default: return Color(0xFF3B82F6);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

// ─── Task Card with Expandable SubTasks (Jira-style) ───

class _TaskCard extends StatefulWidget {
  final dynamic task;
  final ApiService apiService;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;
  final int colorIndex;

  const _TaskCard({
    required this.task,
    required this.apiService,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
    required this.colorIndex,
  });

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _expanded = false;
  List<dynamic> _subtasks = [];
  bool _loadingSubtasks = false;

  Future<void> _loadSubtasks() async {
    setState(() => _loadingSubtasks = true);
    final result = await widget.apiService.getSubTasks(widget.task['id']);
    if (result['success'] && mounted) {
      setState(() {
        _subtasks = result['data'] ?? [];
        _loadingSubtasks = false;
      });
    } else if (mounted) {
      setState(() => _loadingSubtasks = false);
    }
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _subtasks.isEmpty) _loadSubtasks();
  }

  void _showCreateSubtaskDialog() {
    final summaryCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'medium';
    bool isAttachmentRequired = false;
    PlatformFile? pickedFile;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Color(0xFF1e293b),
          title: Text('New Subtask', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dialogField(summaryCtrl, 'Summary'),
              SizedBox(height: 12),
              _dialogField(descCtrl, 'Description', maxLines: 2),
              SizedBox(height: 12),
              _miniPrioritySelector(priority, (v) => setDialogState(() => priority = v)),
              SizedBox(height: 12),
              Row(children: [
                SizedBox(width: 24, height: 24, child: Checkbox(
                  value: isAttachmentRequired,
                  onChanged: (v) => setDialogState(() => isAttachmentRequired = v ?? false),
                  activeColor: Color(0xFF3B82F6), checkColor: Colors.white,
                )),
                SizedBox(width: 8),
                Text('Attachment Required', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
              SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final result = await FilePicker.platform.pickFiles(allowMultiple: false);
                  if (result != null && result.files.isNotEmpty) {
                    setDialogState(() => pickedFile = result.files.first);
                  }
                },
                child: Container(
                  width: double.infinity, padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: pickedFile != null ? Color(0xFF3B82F6) : Colors.white12)),
                  child: Row(children: [
                    Icon(pickedFile != null ? Icons.check_circle : Icons.attach_file,
                      color: pickedFile != null ? Color(0xFF22C55E) : Colors.white38, size: 20),
                    SizedBox(width: 8),
                    Expanded(child: Text(pickedFile?.name ?? 'Attach file (optional)',
                      style: TextStyle(color: pickedFile != null ? Colors.white : Colors.white38, fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (pickedFile != null) GestureDetector(
                      onTap: () => setDialogState(() => pickedFile = null),
                      child: Icon(Icons.close, color: Colors.white38, size: 16)),
                  ]),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (summaryCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                List<int>? bytes;
                if (pickedFile != null && pickedFile!.path != null) {
                  bytes = await File(pickedFile!.path!).readAsBytes();
                }
                await widget.apiService.createSubTask(
                  widget.task['id'],
                  summary: summaryCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  priority: priority,
                  isAttachmentRequired: isAttachmentRequired,
                  attachmentBytes: bytes,
                  attachmentName: pickedFile?.name,
                );
                _loadSubtasks();
                widget.onRefresh();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF3B82F6)),
              child: Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSubtaskDialog(dynamic subtask) {
    final summaryCtrl = TextEditingController(text: subtask['summary'] ?? '');
    final descCtrl = TextEditingController(text: subtask['description'] ?? '');
    String priority = subtask['priority'] ?? 'medium';
    String subtaskStatus = subtask['status'] ?? 'to_do';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Color(0xFF1e293b),
          title: Text('Edit Subtask', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dialogField(summaryCtrl, 'Summary'),
              SizedBox(height: 12),
              _dialogField(descCtrl, 'Description', maxLines: 2),
              SizedBox(height: 12),
              _miniPrioritySelector(priority, (v) => setDialogState(() => priority = v)),
              SizedBox(height: 12),
              _statusSelector(subtaskStatus, (v) => setDialogState(() => subtaskStatus = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await widget.apiService.updateSubTask(widget.task['id'], subtask['id'], {
                  'summary': summaryCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'priority': priority,
                  'status': subtaskStatus,
                });
                _loadSubtasks();
                widget.onRefresh();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF3B82F6)),
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSubtask(int subtaskId) async {
    await widget.apiService.deleteSubTask(widget.task['id'], subtaskId);
    _loadSubtasks();
    widget.onRefresh();
  }

  Future<void> _toggleSubtask(int subtaskId) async {
    await widget.apiService.toggleSubTask(widget.task['id'], subtaskId);
    _loadSubtasks();
    widget.onRefresh();
  }

  Widget _dialogField(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl, maxLines: maxLines,
      style: TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint, hintStyle: TextStyle(color: Colors.white38),
        filled: true, fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _miniPrioritySelector(String current, Function(String) onChanged) {
    return Row(
      children: ['low', 'medium', 'high'].map((p) {
        final sel = current == p;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(p),
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 3),
              padding: EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: sel ? _priorityColor(p).withOpacity(0.3) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: sel ? _priorityColor(p) : Colors.white12),
              ),
              child: Text(p[0].toUpperCase() + p.substring(1), textAlign: TextAlign.center,
                style: TextStyle(color: sel ? _priorityColor(p) : Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _statusSelector(String current, Function(String) onChanged) {
    final statuses = {'to_do': 'To Do', 'in_progress': 'In Progress', 'done': 'Done'};
    final colors = {'to_do': Color(0xFF94A3B8), 'in_progress': Color(0xFF3B82F6), 'done': Color(0xFF10B981)};
    return Row(
      children: statuses.entries.map((e) {
        final sel = current == e.key;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(e.key),
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 3),
              padding: EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: sel ? colors[e.key]!.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: sel ? colors[e.key]! : Colors.white12),
              ),
              child: Text(e.value, textAlign: TextAlign.center,
                style: TextStyle(color: sel ? colors[e.key] : Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ),
        );
      }).toList(),
    );
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
    final colors = [Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF59E0B)];
    final accent = colors[widget.colorIndex % colors.length];

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Main task row
          InkWell(
            onTap: _toggleExpand,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  // Checkbox
                  GestureDetector(
                    onTap: widget.onToggle,
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: isCompleted ? accent : Colors.white54, width: 2),
                        color: isCompleted ? accent : Colors.transparent,
                      ),
                      child: isCompleted ? Icon(Icons.check, size: 14, color: Colors.white) : null,
                    ),
                  ),
                  SizedBox(width: 12),
                  // Task info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['name'] ?? 'Task',
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white,
                            decoration: isCompleted ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 6),
                        Row(children: [
                          if (task['priority'] != null) _priorityBadge(task['priority']),
                          if (subtaskCount > 0) ...[
                            SizedBox(width: 8),
                            Icon(Icons.account_tree, size: 12, color: Colors.white38),
                            SizedBox(width: 3),
                            Text('$completedSubtasks/$subtaskCount', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                          if (task['due_date'] != null) ...[
                            SizedBox(width: 8),
                            Icon(Icons.calendar_today, size: 11, color: accent),
                            SizedBox(width: 3),
                            Text(task['due_date'], style: TextStyle(color: accent, fontSize: 11)),
                          ],
                        ]),
                      ],
                    ),
                  ),
                  // Actions
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.white38, size: 20),
                    color: Color(0xFF1e293b),
                    onSelected: (v) {
                      if (v == 'edit') widget.onEdit();
                      if (v == 'delete') widget.onDelete();
                      if (v == 'subtask') _showCreateSubtaskDialog();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'subtask', child: Text('+ Add Subtask', style: TextStyle(color: Colors.white))),
                      PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(color: Colors.white))),
                      PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                  // Expand arrow
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white38, size: 20,
                  ),
                ],
              ),
            ),
          ),
          // Subtask progress bar
          if (subtaskCount > 0)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: subtaskCount > 0 ? completedSubtasks / subtaskCount : 0,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation(accent),
                  minHeight: 3,
                ),
              ),
            ),
          // Expanded subtasks
          if (_expanded) ...[
            Divider(color: Colors.white.withOpacity(0.08), height: 1),
            if (_loadingSubtasks)
              Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white54)))))
            else ...[
              // Add subtask button
              InkWell(
                onTap: _showCreateSubtaskDialog,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF3B82F6)),
                    SizedBox(width: 8),
                    Text('Add Subtask', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
              // Subtask list
              ..._subtasks.map((st) => _buildSubtaskRow(st)),
              SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSubtaskRow(dynamic st) {
    final isDone = st['completed'] ?? false;
    final status = st['status'] ?? 'to_do';
    return InkWell(
      onTap: () => _showEditSubtaskDialog(st),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 12),
            // Toggle checkbox
            GestureDetector(
              onTap: () => _toggleSubtask(st['id']),
              child: Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isDone ? Color(0xFF10B981) : Colors.white38, width: 1.5),
                  color: isDone ? Color(0xFF10B981) : Colors.transparent,
                ),
                child: isDone ? Icon(Icons.check, size: 12, color: Colors.white) : null,
              ),
            ),
            SizedBox(width: 10),
            // Summary
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    st['summary'] ?? '',
                    style: TextStyle(
                      color: Colors.white, fontSize: 12,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Row(children: [
                    _statusBadge(status),
                    if (st['priority'] != null) ...[SizedBox(width: 6), _priorityBadge(st['priority'], small: true)],
                    if (st['assignee_name'] != null) ...[
                      SizedBox(width: 6),
                      Icon(Icons.person, size: 10, color: Colors.white38),
                      SizedBox(width: 2),
                      Text(st['assignee_name'], style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ]),
                ],
              ),
            ),
            // Delete subtask
            GestureDetector(
              onTap: () => _deleteSubtask(st['id']),
              child: Icon(Icons.close, size: 16, color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priorityBadge(String priority, {bool small = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 8, vertical: small ? 1 : 2),
      decoration: BoxDecoration(
        color: _priorityColor(priority).withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        priority[0].toUpperCase() + priority.substring(1),
        style: TextStyle(color: _priorityColor(priority), fontSize: small ? 9 : 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final labels = {'to_do': 'To Do', 'in_progress': 'In Progress', 'done': 'Done'};
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _statusColor(status).withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        labels[status] ?? status,
        style: TextStyle(color: _statusColor(status), fontSize: 9, fontWeight: FontWeight.w600),
      ),
    );
  }
}
