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
