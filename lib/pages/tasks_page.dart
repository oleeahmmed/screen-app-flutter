// tasks_page.dart — Employee: view tasks, mark done, subtasks, file uploads

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/task_status_dropdown.dart';

class TasksPage extends StatefulWidget {
  final ApiService apiService;

  const TasksPage({super.key, required this.apiService});

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
    }
  }

  List<dynamic> get _filteredTasks {
    if (_filter == 'pending') {
      return _tasks.where((t) => !(t['completed'] ?? false)).toList();
    }
    if (_filter == 'completed') {
      return _tasks.where((t) => t['completed'] ?? false).toList();
    }
    return _tasks;
  }

  Future<void> _toggleTask(int taskId) async {
    final result = await widget.apiService.toggleTask(taskId);
    if (!mounted) return;
    if (result['success'] == true) {
      _loadTasks();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']?.toString() ?? 'Could not update task')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _tasks.where((t) => !(t['completed'] ?? false)).length;
    final completed = _tasks.where((t) => t['completed'] ?? false).length;
    final displayTasks = _filteredTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'My tasks',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(child: _statCard('To do', '$pending', const Color(0xFFF59E0B))),
              const SizedBox(width: 12),
              Expanded(child: _statCard('Done', '$completed', const Color(0xFF10B981))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _filterTab('To do', 'pending'),
              const SizedBox(width: 8),
              _filterTab('Done', 'completed'),
              const SizedBox(width: 8),
              _filterTab('All', 'all'),
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
                            ? 'No pending tasks'
                            : 'No tasks in this view',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: displayTasks.length,
                      itemBuilder: (ctx, i) => _TaskCard(
                        task: displayTasks[i],
                        apiService: widget.apiService,
                        onToggle: () => _toggleTask(displayTasks[i]['id'] as int),
                        onRefresh: _loadTasks,
                        colorIndex: i,
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassPanel(
        borderRadius: 14,
        topTint: color.withValues(alpha: 0.4),
        bottomTint: AppTheme.surface2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _filterTab(String label, String value) {
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
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? AppTheme.primaryBright : AppTheme.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
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

class _TaskCard extends StatefulWidget {
  final dynamic task;
  final ApiService apiService;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;
  final int colorIndex;

  const _TaskCard({
    required this.task,
    required this.apiService,
    required this.onToggle,
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
  List<dynamic> _attachments = [];
  bool _loadingAttachments = false;

  Future<void> _loadSubtasks() async {
    setState(() => _loadingSubtasks = true);
    final result = await widget.apiService.getSubTasks(widget.task['id'] as int);
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
    setState(() => _loadingAttachments = true);
    final result = await widget.apiService.getTaskAttachments(widget.task['id'] as int);
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
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    List<int>? bytes = f.bytes?.toList();
    if (bytes == null && f.path != null) {
      bytes = await File(f.path!).readAsBytes();
    }
    if (bytes == null || f.name.isEmpty) return;
    final up = await widget.apiService.uploadTaskAttachment(widget.task['id'] as int, bytes, f.name);
    if (!mounted) return;
    if (up['success'] == true) {
      await _loadTaskAttachments();
      if (!mounted) return;
      widget.onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File uploaded')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(up['error']?.toString() ?? 'Upload failed')),
      );
    }
  }

  Future<void> _toggleSubtask(int subtaskId) async {
    final result = await widget.apiService.toggleSubTask(widget.task['id'] as int, subtaskId);
    if (!mounted) return;
    if (result['success'] == true) {
      await _loadSubtasks();
      widget.onRefresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']?.toString() ?? 'Could not update subtask')),
      );
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

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isCompleted = task['completed'] == true;
    final subtaskCount = task['subtask_count'] ?? 0;
    final completedSubtasks = task['completed_subtask_count'] ?? 0;
    final needsEvidence = task['is_attachment_required'] == true;
    final hasFiles = task['has_attachments'] == true;
    final colors = [AppTheme.primary, const Color(0xFF8B5CF6), const Color(0xFFEC4899), const Color(0xFFF59E0B)];
    final accent = colors[widget.colorIndex % colors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.glassPanel(borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggleExpand,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: widget.onToggle,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: isCompleted ? accent : Colors.white54, width: 2),
                        color: isCompleted ? accent : Colors.transparent,
                      ),
                      child: isCompleted ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
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
                                task['name']?.toString() ?? 'Task',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TaskStatusBadge(task: task),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TaskStatusDropdown(
                          key: ValueKey<String>('ts_${task['id']}_${task['status']}_${task['completed']}'),
                          taskId: task['id'] as int,
                          task: task,
                          apiService: widget.apiService,
                          onUpdated: widget.onRefresh,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: isCompleted
                              ? OutlinedButton.icon(
                                  onPressed: widget.onToggle,
                                  icon: const Icon(Icons.replay_rounded, size: 18),
                                  label: const Text('Restore'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.warning,
                                    side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.55)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                )
                              : FilledButton.icon(
                                  onPressed: widget.onToggle,
                                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                  label: const Text('Mark complete'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.success.withValues(alpha: 0.85),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (subtaskCount > 0)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.checklist_rounded, size: 14, color: AppTheme.textMuted.withValues(alpha: 0.9)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$completedSubtasks / $subtaskCount subtasks',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                  ),
                                ],
                              ),
                            if (needsEvidence)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: hasFiles
                                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  hasFiles ? 'Evidence attached' : 'Evidence required',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: hasFiles ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                  ),
                                ),
                              ),
                            if (task['due_date'] != null)
                              Text(
                                task['due_date'].toString(),
                                style: TextStyle(color: accent, fontSize: 12),
                              ),
                          ],
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
                      if (v == 'refresh') widget.onRefresh();
                      else if (v == 'expand') _toggleExpand();
                    },
                    itemBuilder: (ctx) => [
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
                  IconButton(
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    color: AppTheme.textMuted,
                    onPressed: _toggleExpand,
                    tooltip: _expanded ? 'Collapse' : 'Expand',
                  ),
                ],
              ),
            ),
          ),
          if (subtaskCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: subtaskCount > 0 ? completedSubtasks / subtaskCount : 0,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                  minHeight: 3,
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
                    const Text(
                      'No files yet',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    )
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
                          taskId: widget.task['id'] as int,
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File uploaded')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(up['error']?.toString() ?? 'Upload failed')),
      );
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
                SizedBox(
                  width: double.infinity,
                  child: isDone
                      ? OutlinedButton.icon(
                          onPressed: onToggle,
                          icon: const Icon(Icons.replay_rounded, size: 16),
                          label: const Text('Restore'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.warning,
                            side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.55)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: onToggle,
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                          label: const Text('Mark complete'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.success.withValues(alpha: 0.85),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
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
              if (v == 'upload') _upload(context);
              else if (v == 'files') _showFiles(context);
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
