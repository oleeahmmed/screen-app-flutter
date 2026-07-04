// tasks_page.dart — Employee "My Tasks" (aims-webapps EmployeeTaskList clone)

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/responsive.dart';
import '../utils/task_helpers.dart';
import '../widgets/task_action_buttons.dart';
import '../widgets/task_status_dropdown.dart';
import 'task_detail_page.dart';

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
  List<dynamic> _tasks = [];
  bool _isLoading = true;
  String _filter = 'pending';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) => _loadTasks());
  }

  Future<void> _loadTasks() async {
    final result = await widget.apiService.getTasks();
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _tasks = result['data'] ?? [];
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      final err = result['error']?.toString();
      if (mounted && err != null && err.isNotEmpty) {
        AppToast.error(context, err);
      }
    }
  }

  List<dynamic> get _filteredTasks {
    if (_filter == 'pending') {
      return _tasks.where((t) => !taskIsCompleted(t)).toList();
    }
    if (_filter == 'completed') {
      return _tasks.where((t) => taskIsCompleted(t)).toList();
    }
    return _tasks;
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
      _loadTasks();
    } else {
      AppToast.updateFailed(context, result['error']?.toString());
    }
  }

  int get _pendingCount => _tasks.where((t) => !taskIsCompleted(t)).length;
  int get _completedCount => _tasks.where((t) => taskIsCompleted(t)).length;

  int get _progressPct {
    if (_tasks.isEmpty) return 0;
    return ((_completedCount / _tasks.length) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final displayTasks = _filteredTasks;
    final pad = Responsive.pagePadding(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embeddedInParent)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'My tasks',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: _loadTasks,
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppTheme.textMuted,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
        if (_tasks.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: _OverallProgressCard(
              pct: _progressPct,
              done: _completedCount,
              total: _tasks.length,
            ),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Row(
            children: [
              _filterTab('To do', 'pending', '$_pendingCount'),
              const SizedBox(width: 8),
              _filterTab('Done', 'completed', '$_completedCount'),
              const SizedBox(width: 8),
              _filterTab('All', 'all', '${_tasks.length}'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBright))
              : displayTasks.isEmpty
                  ? Center(
                      child: Text(
                        _filter == 'pending'
                            ? 'No open tasks assigned to you.'
                            : 'No tasks in this view',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 15),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
                      itemCount: displayTasks.length,
                      itemBuilder: (ctx, i) => _TaskCard(
                        task: displayTasks[i],
                        apiService: widget.apiService,
                        onToggle: () => _toggleTask(displayTasks[i]),
                        onRefresh: _loadTasks,
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _filterTab(String label, String value, String count) {
    final isActive = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: AppTheme.glassPanel(
          borderRadius: 20,
          topTint: isActive ? AppTheme.primary.withValues(alpha: 0.45) : AppTheme.surface2,
          bottomTint: isActive ? AppTheme.surface.withValues(alpha: 0.5) : AppTheme.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppTheme.primaryBright : AppTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: isActive ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count,
                style: TextStyle(
                  color: isActive ? AppTheme.primaryBright : AppTheme.textMuted,
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

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

class _OverallProgressCard extends StatelessWidget {
  final int pct;
  final int done;
  final int total;

  const _OverallProgressCard({
    required this.pct,
    required this.done,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: AppTheme.glassPanel(borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'OVERALL PROGRESS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppTheme.textMuted.withValues(alpha: 0.85),
                ),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF60A5FA),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total > 0 ? pct / 100 : 0,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              color: const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$done of $total tasks completed',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatefulWidget {
  final dynamic task;
  final ApiService apiService;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;

  const _TaskCard({
    required this.task,
    required this.apiService,
    required this.onToggle,
    required this.onRefresh,
  });

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _expanded = false;
  List<dynamic> _subtasks = [];
  bool _loadingSubtasks = false;
  List<dynamic> _attachments = [];
  bool _loadingAttachments = false;

  Future<void> _loadSubtasks() async {
    final id = taskIdFrom(widget.task);
    if (id == null) return;
    setState(() => _loadingSubtasks = true);
    final result = await widget.apiService.getSubTasks(id);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _subtasks = result['data'] ?? [];
        _loadingSubtasks = false;
      });
    } else {
      setState(() => _loadingSubtasks = false);
    }
  }

  Future<void> _loadTaskAttachments() async {
    final id = taskIdFrom(widget.task);
    if (id == null) return;
    setState(() => _loadingAttachments = true);
    final result = await widget.apiService.getTaskAttachments(id);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _attachments = result['data'] ?? [];
        _loadingAttachments = false;
      });
    } else {
      setState(() => _loadingAttachments = false);
    }
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _loadSubtasks();
      _loadTaskAttachments();
    }
  }

  Future<void> _pickAndUploadTaskFile() async {
    final id = taskIdFrom(widget.task);
    if (id == null) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    List<int>? bytes = f.bytes?.toList();
    if (bytes == null && f.path != null) {
      bytes = await File(f.path!).readAsBytes();
    }
    if (bytes == null || f.name.isEmpty) return;
    final up = await widget.apiService.uploadTaskAttachment(id, bytes, f.name);
    if (!mounted) return;
    if (up['success'] == true) {
      await _loadTaskAttachments();
      if (!mounted) return;
      widget.onRefresh();
      AppToast.success(context, 'File uploaded');
    } else {
      AppToast.error(context, up['error']?.toString() ?? 'Upload failed');
    }
  }

  Future<void> _toggleSubtask(int subtaskId) async {
    final taskId = taskIdFrom(widget.task);
    if (taskId == null) return;
    final result = await widget.apiService.toggleSubTask(taskId, subtaskId);
    if (!mounted) return;
    if (result['success'] == true) {
      await _loadSubtasks();
      widget.onRefresh();
    } else {
      AppToast.updateFailed(context, result['error']?.toString());
    }
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

  void _openDetail() {
    final task = widget.task;
    final id = taskIdFrom(task);
    if (id == null) return;
    openTaskDetailPage(
      context,
      apiService: widget.apiService,
      taskId: id,
      projectId: taskProjectIdFrom(task) ?? 0,
      projectName: task['project_name']?.toString() ?? '',
      initialTask: Map<String, dynamic>.from(task as Map),
      onClosed: widget.onRefresh,
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isCompleted = taskIsCompleted(task);
    final subtaskCount = (task['subtask_count'] as num?)?.toInt() ?? 0;
    final completedSubtasks = (task['completed_subtask_count'] as num?)?.toInt() ?? 0;
    final needsEvidence = task['is_attachment_required'] == true;
    final hasFiles = task['has_attachments'] == true;
    final priColor = priorityColor(task['priority']?.toString());
    final taskKey = taskDisplayKey(task);
    final progressPct = subtaskCount > 0
        ? ((completedSubtasks / subtaskCount) * 100).round()
        : (isCompleted ? 100 : 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface2.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openDetail,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: priColor,
                        boxShadow: [BoxShadow(color: priColor.withValues(alpha: 0.55), blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  taskDisplayTitle(task),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                              TaskStatusBadge(task: task),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (taskKey.isNotEmpty)
                                Text(
                                  taskKey,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: Color(0xFF60A5FA),
                                  ),
                                ),
                              if ((task['project_name'] ?? '').toString().isNotEmpty)
                                Text(
                                  task['project_name'].toString(),
                                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted.withValues(alpha: 0.9)),
                                ),
                              if (task['due_date'] != null)
                                Text(
                                  'Due ${task['due_date']}',
                                  style: TextStyle(fontSize: 11, color: priColor.withValues(alpha: 0.95)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TaskStatusDropdown(
                            key: ValueKey<String>('ts_${task['id']}_${task['status']}_${task['completed']}'),
                            taskId: taskIdFrom(task)!,
                            task: task,
                            projectId: taskProjectIdFrom(task) ?? 0,
                            apiService: widget.apiService,
                            onUpdated: widget.onRefresh,
                            compact: true,
                          ),
                          const SizedBox(height: 10),
                          TaskCompleteButton(
                            isCompleted: isCompleted,
                            onPressed: widget.onToggle,
                            compact: true,
                          ),
                          if (subtaskCount > 0) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: subtaskCount > 0 ? completedSubtasks / subtaskCount : 0,
                                minHeight: 4,
                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                                color: priColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$completedSubtasks/$subtaskCount subtasks · $progressPct%',
                              style: TextStyle(fontSize: 10, color: AppTheme.textMuted.withValues(alpha: 0.85)),
                            ),
                          ],
                          if (needsEvidence)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                hasFiles ? 'Evidence attached' : 'Evidence required to complete',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: hasFiles ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Task actions',
                      color: AppTheme.surface2,
                      surfaceTintColor: Colors.transparent,
                      icon: Icon(Icons.more_vert_rounded, color: AppTheme.textMuted, size: 22),
                      onSelected: (v) {
                        if (v == 'refresh') {
                          widget.onRefresh();
                        } else if (v == 'open') {
                          _openDetail();
                        } else if (v == 'expand') {
                          _toggleExpand();
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'open',
                          child: Row(
                            children: [
                              Icon(Icons.open_in_new_rounded, color: AppTheme.primaryBright, size: 20),
                              SizedBox(width: 10),
                              Text('Open task', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'expand',
                          child: Row(
                            children: [
                              Icon(
                                _expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                                color: AppTheme.primaryBright,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _expanded ? 'Collapse details' : 'Expand details',
                                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'refresh',
                          child: Row(
                            children: [
                              Icon(Icons.refresh_rounded, color: AppTheme.textMuted, size: 20),
                              SizedBox(width: 10),
                              Text('Refresh', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((task['description'] ?? '').toString().trim().isNotEmpty) ...[
                    Text(
                      task['description'].toString(),
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      const Icon(Icons.attach_file_rounded, size: 18, color: AppTheme.primaryBright),
                      const SizedBox(width: 8),
                      const Text(
                        'Files on this task',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _pickAndUploadTaskFile,
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: const Text('Upload'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryBright,
                          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.45)),
                          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  if (_loadingAttachments)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBright),
                        ),
                      ),
                    )
                  else if (_attachments.isEmpty)
                    const Text('No files yet', style: TextStyle(color: AppTheme.textMuted, fontSize: 12))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _attachments.map<Widget>((a) {
                        final name = a['file_name']?.toString() ?? 'file';
                        final url = a['file_url']?.toString();
                        return ActionChip(
                          avatar: const Icon(Icons.insert_drive_file_outlined, size: 16),
                          label: Text(name, overflow: TextOverflow.ellipsis),
                          onPressed: () => _openUrl(url),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.checklist_rounded, size: 18, color: AppTheme.primaryBright),
                      SizedBox(width: 8),
                      Text(
                        'Subtasks',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_loadingSubtasks)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBright),
                        ),
                      ),
                    )
                  else if (_subtasks.isEmpty)
                    const Text('No subtasks', style: TextStyle(color: AppTheme.textMuted, fontSize: 12))
                  else
                    ..._subtasks.map((st) => _SubtaskRow(
                          taskId: taskIdFrom(widget.task)!,
                          subtask: st,
                          apiService: widget.apiService,
                          onToggle: () => _toggleSubtask(st['id'] as int),
                          onOpenUrl: _openUrl,
                          onAfterUpload: () async {
                            await _loadSubtasks();
                            widget.onRefresh();
                          },
                        )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  final int taskId;
  final dynamic subtask;
  final ApiService apiService;
  final VoidCallback onToggle;
  final Future<void> Function(String? url) onOpenUrl;
  final Future<void> Function() onAfterUpload;

  const _SubtaskRow({
    required this.taskId,
    required this.subtask,
    required this.apiService,
    required this.onToggle,
    required this.onOpenUrl,
    required this.onAfterUpload,
  });

  Future<void> _upload(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    List<int>? bytes = f.bytes?.toList();
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) return;
    final up = await apiService.uploadSubTaskAttachment(taskId, subtask['id'] as int, bytes, f.name);
    if (!context.mounted) return;
    if (up['success'] == true) {
      await onAfterUpload();
      if (!context.mounted) return;
      AppToast.success(context, 'File uploaded');
    } else {
      AppToast.error(context, up['error']?.toString() ?? 'Upload failed');
    }
  }

  Future<void> _showFiles(BuildContext context) async {
    final id = subtask['id'] as int;
    final res = await apiService.getSubTaskAttachments(taskId, id);
    final list = (res['success'] == true) ? (res['data'] as List<dynamic>? ?? []) : <dynamic>[];

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    subtask['summary']?.toString() ?? 'Subtask',
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
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.attach_file, color: AppTheme.primaryBright),
                        title: Text(
                          a['file_name']?.toString() ?? 'file',
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          onOpenUrl(a['file_url']?.toString());
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _upload(context);
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload file'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDone = subtask['completed'] == true || subtask['status'] == 'done';
    final summary = subtask['summary']?.toString() ?? '';
    final attCount = subtask['attachment_count'] as int? ?? 0;
    final needAtt = subtask['is_attachment_required'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: AppTheme.glassPanel(borderRadius: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDone ? const Color(0xFF10B981) : Colors.white38,
                  width: 1.5,
                ),
                color: isDone ? const Color(0xFF10B981) : Colors.transparent,
              ),
              child: isDone ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        summary,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SubtaskStatusBadge(subtask: subtask),
                  ],
                ),
                const SizedBox(height: 6),
                SubtaskStatusDropdown(
                  key: ValueKey<String>(
                    'ss_${subtask['id']}_${subtask['status']}_${subtask['completed']}',
                  ),
                  taskId: taskId,
                  subtaskId: subtask['id'] as int,
                  subtask: subtask,
                  apiService: apiService,
                  onUpdated: onAfterUpload,
                ),
                const SizedBox(height: 8),
                TaskCompleteButton(
                  isCompleted: isDone,
                  onPressed: onToggle,
                  compact: true,
                ),
                if (needAtt)
                  Text(
                    attCount > 0 ? 'Evidence uploaded' : 'Evidence required to complete',
                    style: TextStyle(
                      fontSize: 10,
                      color: attCount > 0 ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Subtask actions',
            color: AppTheme.surface2,
            surfaceTintColor: Colors.transparent,
            child: Badge(
              isLabelVisible: attCount > 0,
              label: Text('$attCount'),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.more_vert_rounded, color: AppTheme.textMuted, size: 22),
              ),
            ),
            onSelected: (v) {
              if (v == 'upload') {
                _upload(context);
              } else if (v == 'files') {
                _showFiles(context);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'upload',
                child: Row(
                  children: [
                    Icon(Icons.upload_file_rounded, color: AppTheme.primaryBright, size: 20),
                    SizedBox(width: 10),
                    Text('Upload file', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'files',
                child: Row(
                  children: [
                    Icon(Icons.folder_open_outlined, color: AppTheme.textMuted, size: 20),
                    SizedBox(width: 10),
                    Text('View files', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
