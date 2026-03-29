// tasks_page.dart - Jira-style Tasks Page with SubTasks

import 'package:flutter/material.dart';
import 'dart:async';
import '../config.dart';
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
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await widget.apiService.createTask(
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  priority: priority,
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
