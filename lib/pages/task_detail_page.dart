import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/app_navigation.dart';
import '../widgets/app_tab_shell.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/app_toast.dart';
import '../utils/platform_capabilities.dart';
import '../utils/task_helpers.dart';
import '../widgets/kanban_assignee_picker.dart';
import '../widgets/task_action_buttons.dart';
import '../widgets/task_description_editor.dart';
import '../widgets/task_status_dropdown.dart';

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
  final user = task['user'];
  if (user is Map) {
    final uid = int.tryParse('${user['id'] ?? ''}');
    return uid != null ? [uid] : [];
  }
  final uid = int.tryParse('${task['user_id'] ?? (user ?? '')}');
  return uid != null ? [uid] : [];
}

List<Map<String, dynamic>> _taskAssigneeList(Map<String, dynamic> task, List<dynamic> employees) {
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
  return ids.map((id) {
    final emp = employees.cast<Map?>().firstWhere(
          (e) => int.tryParse('${e?['id'] ?? e?['user_id']}') == id,
          orElse: () => null,
        );
    return {
      'id': id,
      'name': emp != null ? _displayStr(emp) : name,
      'role': emp?['role'] ?? emp?['department'] ?? task['stage_name'] ?? '',
    };
  }).toList();
}

class _FormSnapshot {
  final String title;
  final String desc;
  final String status;
  final String priority;
  final String taskType;
  final int? stageId;
  final List<int> assigneeIds;
  final String? startDate;
  final String? dueDate;
  final String estHours;
  final String actHours;
  final bool attachmentRequired;

  const _FormSnapshot({
    required this.title,
    required this.desc,
    required this.status,
    required this.priority,
    required this.taskType,
    required this.stageId,
    required this.assigneeIds,
    required this.startDate,
    required this.dueDate,
    required this.estHours,
    required this.actHours,
    required this.attachmentRequired,
  });
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}

/// Opens the task detail page (Work | Activity).
void openTaskDetailPage(
  BuildContext context, {
  required ApiService apiService,
  required int taskId,
  int projectId = 0,
  String projectName = '',
  String customerName = '',
  Map<String, dynamic>? initialTask,
  List<dynamic> employees = const [],
  List<dynamic> stages = const [],
  bool isManager = false,
  VoidCallback? onClosed,
  VoidCallback? onLogout,
}) {
  final page = TaskDetailPage(
    apiService: apiService,
    taskId: taskId,
    projectId: projectId,
    projectName: projectName,
    customerName: customerName,
    initialTask: initialTask,
    employees: employees,
    stages: stages,
    isManager: isManager,
  );

  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => AppTabShell(
        selectedIndex: AppNavigation.instance.selectedTabIndex.clamp(0, AppNavigation.tabCount - 1),
        unreadNotifs: AppNavigation.instance.unreadNotifs,
        onLogout: onLogout,
        child: page,
      ),
    ),
  ).then((_) => onClosed?.call());
}

/// Task detail — clear hero, checklist subtasks, and supporting details.
class TaskDetailPage extends StatefulWidget {
  final ApiService apiService;
  final int taskId;
  final int projectId;
  final String projectName;
  final String customerName;
  final Map<String, dynamic>? initialTask;
  final List<dynamic> employees;
  final List<dynamic> stages;
  final bool isManager;

  const TaskDetailPage({
    super.key,
    required this.apiService,
    required this.taskId,
    this.projectId = 0,
    this.projectName = '',
    this.customerName = '',
    this.initialTask,
    this.employees = const [],
    this.stages = const [],
    this.isManager = false,
  });

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> with SingleTickerProviderStateMixin {
    late TabController _tabCtrl;
  Map<String, dynamic>? _task;
  List<dynamic> _subtasks = [];
  List<dynamic> _attachments = [];
  List<dynamic> _stages = [];
  List<dynamic> _employees = [];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _loadError;
  bool _isAttachmentRequired = false;
  bool _attachmentsDragOver = false;
  List<dynamic> _activity = [];
  bool _activityLoading = false;
  bool _activityLoaded = false;
  int _descEditorGen = 0;
  Timer? _autoSaveTimer;
  Timer? _saveHintTimer;
  String _saveHint = '';
  bool _syncingFromServer = false;

  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _estHoursCtrl;
  late TextEditingController _actHoursCtrl;

  String _status = 'pending';
  String _priority = 'medium';
  String _taskType = 'task';
  int? _stageId;
  List<int> _assigneeIds = [];
  String? _startDate;
  String? _dueDate;
  _FormSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 4 && !_activityLoaded && widget.projectId > 0) {
        _loadActivity();
      }
    });
    _stages = List<dynamic>.from(widget.stages);
    _employees = List<dynamic>.from(widget.employees);
    _titleCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _estHoursCtrl = TextEditingController();
    _actHoursCtrl = TextEditingController();
    if (widget.initialTask != null) {
      _task = Map<String, dynamic>.from(widget.initialTask!);
      _applyTaskToForm(_task!);
      _snapshot = _captureSnapshot();
      _loading = false;
    }
    for (final c in [_titleCtrl, _descCtrl, _estHoursCtrl, _actHoursCtrl]) {
      c.addListener(_onTextChanged);
    }
    _load();
    if (widget.projectId > 0 && (_stages.isEmpty || _employees.isEmpty)) {
      _loadProjectMeta();
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _saveHintTimer?.cancel();
    _tabCtrl.dispose();
    for (final c in [_titleCtrl, _descCtrl, _estHoursCtrl, _actHoursCtrl]) {
      c.removeListener(_onTextChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (_syncingFromServer || _loading) return;
    _markDirty();
    _scheduleTextAutoSave();
  }

  void _scheduleTextAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 450), _flushTextAutoSave);
  }

  Future<void> _flushTextAutoSave() async {
    if (_task == null || _syncingFromServer) return;
    final s = _snapshot;
    if (s == null) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final body = <String, dynamic>{};
    if (title != s.title) body['name'] = title;
    if (_descCtrl.text != s.desc) body['description'] = _descCtrl.text;
    final est = _estHoursCtrl.text.trim();
    final act = _actHoursCtrl.text.trim();
    if (est != s.estHours) body['estimated_hours'] = est.isEmpty ? null : est;
    if (act != s.actHours) body['actual_hours'] = act.isEmpty ? null : act;
    if (body.isEmpty) return;
    await _patchPartial(body);
  }

  Future<void> _patchPartial(Map<String, dynamic> body) async {
    if (_task == null || body.isEmpty || _syncingFromServer) return;
    if (body.containsKey('assignee_ids')) {
      final ids = body['assignee_ids'];
      if (ids is List && ids.isEmpty) {
        if (!mounted) return;
        AppToast.warning(context, 'At least one assignee is required');
        return;
      }
    }
    setState(() {
      _saving = true;
      _saveHint = 'Saving…';
    });
    final r = await widget.apiService.updateTask(
      widget.taskId,
      body,
      projectId: widget.projectId,
      task: _task,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      if (r['data'] is Map) {
        final incoming = Map<String, dynamic>.from(r['data'] as Map);
        if (incoming['id'] != null ||
            incoming['name'] != null ||
            incoming['title'] != null) {
          final prev = _task;
          _task = incoming;
          if (prev != null) {
            _task!['project_id'] ??= prev['project_id'] ?? prev['project'];
            _task!['project'] ??= prev['project'];
            _task!['project_name'] ??= prev['project_name'];
          }
          _applyTaskToForm(_task!);
        }
      }
      _snapshot = _captureSnapshot();
      setState(() {
        _saving = false;
        _dirty = false;
        _saveHint = 'Saved';
      });
      _saveHintTimer?.cancel();
      _saveHintTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _saveHint = '');
      });
    } else {
      setState(() {
        _saving = false;
        _saveHint = '';
      });
      AppToast.saveFailed(context, r['error']?.toString());
    }
  }

  void _markDirty() {
    if (!_loading && _snapshot != null && !_dirty) {
      setState(() => _dirty = true);
    }
  }

  void _setField(VoidCallback fn, [Map<String, dynamic>? patch]) {
    fn();
    _markDirty();
    setState(() {});
    if (patch != null && !_syncingFromServer) {
      _patchPartial(patch);
    }
  }

  Future<void> _loadProjectMeta() async {
    final r = await widget.apiService.getProjectDetail(widget.projectId);
    if (!mounted || r['success'] != true || r['data'] is! Map) return;
    final data = r['data'] as Map;
    setState(() {
      if (_stages.isEmpty && data['stages'] is List) {
        _stages = List<dynamic>.from(data['stages'] as List);
      }
      if (_employees.isEmpty) {
        final emp = (data['employees'] as List?) ?? [];
        if (emp.isNotEmpty) {
          _employees = List<dynamic>.from(emp);
        } else {
          final members = (data['project_members'] as List?) ?? [];
          _employees = members
              .map((m) => {
                    'id': m['user_id'],
                    'user_id': m['user_id'],
                    'full_name': m['username'],
                    'username': m['username'],
                  })
              .toList();
        }
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _task == null;
        _loadError = null;
      });
    }
    final results = await Future.wait([
      widget.apiService.getTask(widget.taskId, projectId: widget.projectId),
      widget.apiService.getSubTasks(widget.taskId),
      widget.apiService.getTaskAttachments(widget.taskId),
    ]);
    if (!mounted) return;
    if (results[0]['success'] == true && results[0]['data'] != null) {
      _task = Map<String, dynamic>.from(results[0]['data'] as Map);
      _applyTaskToForm(_task!);
      _snapshot = _captureSnapshot();
      _dirty = false;
      _loadError = null;
    } else if (_task == null) {
      _loadError = results[0]['error']?.toString() ?? 'Task not found';
    } else {
      _loadError = results[0]['error']?.toString();
    }
    if (results[1]['success'] == true) {
      _subtasks = results[1]['data'] ?? [];
    }
    if (results[2]['success'] == true) {
      final raw = results[2]['data'];
      _attachments = raw is List ? List<dynamic>.from(raw) : [];
    }
    setState(() => _loading = false);
  }

  void _applyTaskToForm(Map<String, dynamic> t) {
    _syncingFromServer = true;
    _autoSaveTimer?.cancel();
    _titleCtrl.text = t['name']?.toString() ?? t['title']?.toString() ?? '';
    _descCtrl.text = t['description']?.toString() ?? t['desc']?.toString() ?? '';
    _descEditorGen++;
    _estHoursCtrl.text = t['estimated_hours']?.toString() ?? '';
    _actHoursCtrl.text = t['actual_hours']?.toString() ?? '';
    _status = taskStatusValueFromMap(t);
    _priority = (t['priority'] ?? 'medium').toString();
    if (!['low', 'medium', 'high'].contains(_priority)) _priority = 'medium';
    _taskType = (t['task_type'] ?? 'task').toString();
    _stageId = int.tryParse('${t['stage_id'] ?? t['stage'] ?? ''}');
    _assigneeIds = List<int>.from(_taskAssigneeIds(t));
    _startDate = t['start_date']?.toString() ?? _dateOnly(t['date']);
    _dueDate = t['due_date']?.toString();
    _isAttachmentRequired = t['is_attachment_required'] == true;
    _syncingFromServer = false;
  }

  int _progressPct(Map<String, dynamic>? t) {
    if (_subtasks.isNotEmpty) {
      final done = _subtasks.where((s) {
        if (s is! Map) return false;
        return s['completed'] == true ||
            s['status']?.toString() == 'completed' ||
            s['status']?.toString() == 'done';
      }).length;
      return ((done / _subtasks.length) * 100).round();
    }
    if (t != null && (t['status']?.toString() == 'completed' || t['completed'] == true)) {
      return 100;
    }
    final raw = t?['subtask_progress'];
    if (raw != null) return int.tryParse('$raw') ?? 0;
    return 0;
  }

  String _progressLabel(Map<String, dynamic>? t) {
    if (_subtasks.isNotEmpty) {
      final done = _subtasks.where((s) {
        if (s is! Map) return false;
        return s['completed'] == true ||
            s['status']?.toString() == 'completed' ||
            s['status']?.toString() == 'done';
      }).length;
      return '$done/${_subtasks.length} done (${_progressPct(t)}%)';
    }
    if (t != null && (t['status']?.toString() == 'completed' || t['completed'] == true)) {
      return 'Task complete';
    }
    return 'No subtasks yet';
  }

  _FormSnapshot _captureSnapshot() => _FormSnapshot(
        title: _titleCtrl.text,
        desc: _descCtrl.text,
        status: _status,
        priority: _priority,
        taskType: _taskType,
        stageId: _stageId,
        assigneeIds: List<int>.from(_assigneeIds),
        startDate: _startDate,
        dueDate: _dueDate,
        estHours: _estHoursCtrl.text,
        actHours: _actHoursCtrl.text,
        attachmentRequired: _isAttachmentRequired,
      );

  void _discard() {
    _autoSaveTimer?.cancel();
    final s = _snapshot;
    if (s == null) return;
    _titleCtrl.text = s.title;
    _descCtrl.text = s.desc;
    _descEditorGen++;
    _estHoursCtrl.text = s.estHours;
    _actHoursCtrl.text = s.actHours;
    _status = s.status;
    _priority = s.priority;
    _taskType = s.taskType;
    _stageId = s.stageId;
    _assigneeIds = List<int>.from(s.assigneeIds);
    _startDate = s.startDate;
    _dueDate = s.dueDate;
    _isAttachmentRequired = s.attachmentRequired;
    setState(() {
      _dirty = false;
      _saveHint = '';
    });
  }

  String? _dateOnly(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : null;
  }

  String _fmtDateDisplay(String? iso) {
    if (iso == null || iso.length < 10) return 'Not set';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    if (iso.length <= 10 || (dt.hour == 0 && dt.minute == 0 && !iso.contains('T'))) {
      return DateFormat('d MMM yyyy').format(dt);
    }
    return DateFormat('d MMM yyyy').format(dt);
  }

  Future<void> _saveAll() async {
    if (_task == null) return;
    _autoSaveTimer?.cancel();
    await _flushTextAutoSave();
    if (_assigneeIds.isEmpty) {
      AppToast.warning(context, 'At least one assignee is required');
      return;
    }
    final s = _snapshot;
    if (s == null) return;
    final body = <String, dynamic>{};
    final title = _titleCtrl.text.trim();
    if (title != s.title) body['name'] = title;
    if (_descCtrl.text != s.desc) body['description'] = _descCtrl.text;
    if (_status != s.status) body['status'] = _status;
    if (_priority != s.priority) body['priority'] = _priority;
    if (_taskType != s.taskType) body['task_type'] = _taskType;
    if (_stageId != s.stageId) body['stage_id'] = _stageId;
    if (!_listEq(_assigneeIds, s.assigneeIds)) body['assignee_ids'] = _assigneeIds;
    if (_startDate != s.startDate) body['start_date'] = _startDate;
    if (_dueDate != s.dueDate) body['due_date'] = _dueDate;
    final est = _estHoursCtrl.text.trim();
    final act = _actHoursCtrl.text.trim();
    if (est != s.estHours) body['estimated_hours'] = est.isEmpty ? null : est;
    if (act != s.actHours) body['actual_hours'] = act.isEmpty ? null : act;
    if (_isAttachmentRequired != s.attachmentRequired) {
      body['is_attachment_required'] = _isAttachmentRequired;
    }
    if (body.isEmpty) {
      if (!mounted) return;
      AppToast.saved(context, message: 'All changes saved');
      return;
    }
    await _patchPartial(body);
    if (!mounted) return;
    if (_saveHint == 'Saved') {
      AppToast.saved(context, message: 'Changes saved');
    }
  }

  bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _pickAssignees() async {
    final ids = await showKanbanAssigneePicker(
      context: context,
      employees: _employees,
      selectedIds: _assigneeIds,
    );
    if (ids == null || ids.isEmpty) return;
    _setField(() => _assigneeIds = ids, {'assignee_ids': ids});
  }

  void _removeAssignee(int userId) {
    if (_assigneeIds.length <= 1) {
      AppToast.warning(context, 'At least one assignee is required');
      return;
    }
    final next = List<int>.from(_assigneeIds)..remove(userId);
    _setField(() => _assigneeIds = next, {'assignee_ids': next});
  }

  Future<void> _pickDate(String field) async {
    final current = field == 'start_date' ? _startDate : _dueDate;
    DateTime initial = DateTime.now();
    if (current != null && current.length >= 10) {
      initial = DateTime.tryParse(current) ?? DateTime.tryParse(current.substring(0, 10)) ?? initial;
    }
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (c, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (c, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (!mounted) return;
    final dt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime?.hour ?? 0,
      pickedTime?.minute ?? 0,
    );
    final iso = dt.toIso8601String();
    _setField(() {
      if (field == 'start_date') {
        _startDate = iso;
      } else {
        _dueDate = iso;
      }
    }, {field: iso});
  }

  void _clearDate(String field) {
    _setField(() {
      if (field == 'start_date') {
        _startDate = null;
      } else {
        _dueDate = null;
      }
    }, {field: null});
  }

  Future<void> _uploadBytes(List<int> bytes, String name) async {
    if (bytes.isEmpty || name.isEmpty) return;
    final up = await widget.apiService.uploadTaskAttachment(widget.taskId, bytes, name);
    if (!mounted) return;
    if (up['success'] == true) {
      await _load();
      if (!mounted) return;
      AppToast.success(context, 'Uploaded $name');
    } else {
      AppToast.error(context, up['error']?.toString() ?? 'Upload failed');
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result == null || result.files.isEmpty) return;
    for (final f in result.files) {
      List<int>? bytes = f.bytes?.toList();
      if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
      if (bytes != null && f.name.isNotEmpty) {
        await _uploadBytes(bytes, f.name);
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim().replaceAll('"', '');
    if (text != null && text.isNotEmpty) {
      final f = File(text);
      if (await f.exists()) {
        await _uploadBytes(await f.readAsBytes(), f.uri.pathSegments.last);
        return;
      }
    }
    if (!mounted) return;
    AppToast.info(context, 'Copy a file in Explorer, then Paste — or drag files here');
  }

  Future<void> _loadActivity() async {
    if (widget.projectId <= 0) return;
    setState(() => _activityLoading = true);
    final r = await widget.apiService.getTaskActivity(widget.projectId, widget.taskId);
    if (!mounted) return;
    setState(() {
      _activityLoading = false;
      _activityLoaded = true;
      if (r['success'] == true) {
        _activity = r['data'] is List ? List<dynamic>.from(r['data'] as List) : [];
      }
    });
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _toggleSubtask(dynamic st) async {
    final id = int.tryParse('${st['id']}');
    if (id == null) return;
    final idx = _subtasks.indexWhere((s) => int.tryParse('${s['id']}') == id);
    if (idx < 0) return;

    final raw = _subtasks[idx];
    final current = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{'id': id};
    final wasDone = current['completed'] == true ||
        current['status']?.toString() == 'completed' ||
        current['status']?.toString() == 'done';

    // Instant mark / unmark — then sync with server.
    setState(() {
      current['completed'] = !wasDone;
      current['status'] = wasDone ? 'to_do' : 'done';
      _subtasks[idx] = current;
    });

    final r = await widget.apiService.toggleSubTask(
      widget.taskId,
      id,
      projectId: widget.projectId,
      markDone: !wasDone,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      await _load(silent: true);
    } else {
      setState(() {
        current['completed'] = wasDone;
        current['status'] = wasDone ? 'done' : 'to_do';
        _subtasks[idx] = current;
      });
      AppToast.updateFailed(context, r['error']?.toString());
    }
  }

  Future<void> _toggleComplete() async {
    if (_task == null) return;
    final done = taskIsCompleted(_task);
    final r = await widget.apiService.setTaskCompleted(
      widget.taskId,
      completed: !done,
      projectId: widget.projectId,
      task: _task,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      await _load();
      if (!mounted) return;
      AppToast.updated(context, message: done ? 'Task reopened' : 'Task completed');
    } else {
      AppToast.updateFailed(context, r['error']?.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, control: true): _SaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): _SaveIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _CloseIntent(),
      },
      child: Actions(
        actions: {
          _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) {
            if (!_saving) _saveAll();
            return null;
          }),
          _CloseIntent: CallbackAction<_CloseIntent>(onInvoke: (_) {
            Navigator.pop(context);
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.keyV &&
                (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) &&
                !_focusInTextField()) {
              _pasteFromClipboard();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Scaffold(
      backgroundColor: Colors.transparent,
      body: AppTheme.loginDashboardBackground(
        context: context,
        child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
            else if (t == null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.white.withValues(alpha: 0.35)),
                        const SizedBox(height: 16),
                        Text(
                          _loadError ?? 'Task not found',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              if (_loadError != null && _loadError!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: AppTheme.warning.withValues(alpha: 0.35),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Could not refresh: $_loadError',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              _buildTopBar(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _tabPane(child: _descriptionEditor()),
                    _tabPane(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildProgressStrip(_task!)),
                              const SizedBox(width: 10),
                              _subtaskAddButton(),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _subtasksPanel(),
                        ],
                      ),
                    ),
                    _tabPane(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: _attachmentActions(),
                          ),
                          const SizedBox(height: 8),
                          _attachmentsPanel(),
                        ],
                      ),
                    ),
                    _tabPane(child: _buildPropertiesSidebar(t)),
                    _buildActivityTab(),
                  ],
                ),
              ),
              _buildFooter(),
            ],
          ],
        ),
      ),
      ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final t = _task!;

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, compact ? 6 : 8, compact ? 12 : 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Big editable title — primary focus for the user.
          Container(
            decoration: AppTheme.loginInsetDecoration(borderRadius: 16),
            padding: EdgeInsets.fromLTRB(compact ? 12 : 14, compact ? 12 : 14, compact ? 12 : 14, compact ? 12 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Title',
                  style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _titleCtrl,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: compact ? 20 : 22,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    letterSpacing: -0.35,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'What needs to be done?',
                    hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.4)),
                    contentPadding: EdgeInsets.zero,
                  ),
                  maxLines: 4,
                  minLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Title → Discard + Mark complete → (tabs below).
          TaskDetailHeaderActions(
            dirty: _dirty,
            saving: _saving,
            isCompleted: taskIsCompleted(t),
            onDiscard: _dirty ? _discard : null,
            onToggleComplete: _toggleComplete,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStrip(Map<String, dynamic> t) {
    final pct = _progressPct(t);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Progress',
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              _progressLabel(t),
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            color: AppTheme.accent,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final subCount = _subtasks.length;
    final fileCount = _attachments.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 10 : 16, 8, compact ? 10 : 16, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: AppTheme.primary.withValues(alpha: 0.22),
            border: Border.all(color: AppTheme.primaryBright.withValues(alpha: 0.28)),
          ),
          labelColor: AppTheme.textPrimary,
          unselectedLabelColor: AppTheme.textMuted,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          tabs: [
            const Tab(height: 34, text: 'Description'),
            Tab(height: 34, text: subCount > 0 ? 'Subtasks ($subCount)' : 'Subtasks'),
            Tab(height: 34, text: fileCount > 0 ? 'Files ($fileCount)' : 'Files'),
            const Tab(height: 34, text: 'More'),
            const Tab(height: 34, text: 'Activity'),
          ],
        ),
      ),
    );
  }

  Widget _tabPane({required Widget child}) {
    final pad = MediaQuery.sizeOf(context).width < 700 ? 12.0 : 16.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, pad + 8),
      child: Container(
        width: double.infinity,
        decoration: _cardDeco(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: child,
      ),
    );
  }

  Widget _descriptionEditor() {
    final compact = Responsive.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Description',
          style: TextStyle(
            color: AppTheme.textMuted.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TaskDescriptionEditor(
          key: ValueKey<String>('desc_editor_${widget.taskId}_$_descEditorGen'),
          initialValue: _descCtrl.text,
          minHeight: compact ? 160 : 220,
          onChanged: (html) {
            if (_syncingFromServer) return;
            if (_descCtrl.text == html) return;
            _descCtrl.value = TextEditingValue(text: html);
          },
        ),
      ],
    );
  }

  Widget _attachmentActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _uploadFile,
          icon: const Icon(Icons.upload_rounded, size: 18, color: AppTheme.primaryBright),
          tooltip: 'Upload',
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: _pasteFromClipboard,
          icon: Icon(Icons.content_paste_rounded, size: 17, color: AppTheme.textMuted.withValues(alpha: 0.85)),
          tooltip: 'Paste',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Future<void> _deleteAttachment(dynamic a) async {
    final id = int.tryParse('${a['id']}');
    if (id == null) return;
    final name = a['file_name']?.toString() ?? 'file';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text('Delete attachment?', style: TextStyle(color: Colors.white)),
        content: Text('Remove "$name"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await widget.apiService.deleteTaskAttachment(widget.taskId, id);
    if (!mounted) return;
    if (r['success'] == true) {
      await _load();
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Could not delete');
    }
  }

  bool _focusInTextField() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    return focus.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Widget _attachmentsPanel() {
    final panel = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.all(_attachments.isEmpty ? 18 : 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.16),
        border: Border.all(
          color: _attachmentsDragOver ? AppTheme.primary : Colors.white.withValues(alpha: 0.06),
          width: _attachmentsDragOver ? 1.5 : 1,
        ),
      ),
      child: _attachments.isEmpty
          ? Center(
              child: Text(
                _attachmentsDragOver
                    ? 'Drop files here…'
                    : (PlatformCapabilities.fileDragDrop
                        ? 'Drop, upload, or paste a file'
                        : 'Upload or paste a file'),
                style: TextStyle(
                  color: _attachmentsDragOver ? AppTheme.primary : Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            )
          : Column(
              children: _attachments.map((a) {
                final name = a['file_name']?.toString() ?? 'file';
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppTheme.featureVault.withValues(alpha: 0.15),
                    ),
                    child: const Icon(Icons.insert_drive_file_rounded, color: AppTheme.featureVault, size: 18),
                  ),
                  title: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white38),
                        onPressed: () => _openUrl(a['file_url']?.toString()),
                        tooltip: 'Open',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                        onPressed: () => _deleteAttachment(a),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );

    if (!PlatformCapabilities.fileDragDrop) return panel;

    return DropTarget(
      onDragEntered: (_) => setState(() => _attachmentsDragOver = true),
      onDragExited: (_) => setState(() => _attachmentsDragOver = false),
      onDragDone: (details) async {
        setState(() => _attachmentsDragOver = false);
        for (final f in details.files) {
          final bytes = await f.readAsBytes();
          await _uploadBytes(bytes, f.name);
        }
      },
      child: panel,
    );
  }

  Widget _subtaskAddButton() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF38BDF8), Color(0xFF3B82F6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: () => _showSubtaskDialog(),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add subtask', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _subtasksPanel() {
    if (_subtasks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.04),
              AppTheme.primary.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.12),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.playlist_add_check_rounded, size: 26, color: AppTheme.accent),
            ),
            const SizedBox(height: 12),
            const Text(
              'No subtasks yet',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Split this task into small clear steps',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            _subtaskAddButton(),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < _subtasks.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _subtaskRow(_subtasks[i]),
        ],
      ],
    );
  }

  Widget _subtaskRow(dynamic st) {
    final done = st['completed'] == true || st['status']?.toString() == 'completed' || st['status']?.toString() == 'done';
    final due = st['due_date']?.toString() ?? '';
    final dueShort = due.length >= 10 ? due.substring(0, 10) : '';
    final assignee = _displayStr(st['assignee_name']);
    final priority = st['priority']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: done
            ? Colors.white.withValues(alpha: 0.025)
            : Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: done
              ? AppTheme.success.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dedicated tap target — mark / unmark instantly.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _toggleSubtask(st),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? AppTheme.success.withValues(alpha: 0.9) : Colors.transparent,
                      border: Border.all(
                        color: done ? AppTheme.success : Colors.white.withValues(alpha: 0.35),
                        width: 1.8,
                      ),
                    ),
                    child: done
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showSubtaskDialog(st: st),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          st['summary']?.toString() ?? '',
                          style: TextStyle(
                            color: done ? AppTheme.textMuted : AppTheme.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            decoration: done ? TextDecoration.lineThrough : null,
                            decorationColor: AppTheme.textMuted,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            SubtaskStatusBadge(subtask: st),
                            if (priority.isNotEmpty) _softPill(priority),
                            if (assignee.isNotEmpty) _softPill(assignee),
                            if (dueShort.isNotEmpty) _softPill(dueShort, icon: Icons.event_rounded),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 17, color: Colors.white.withValues(alpha: 0.4)),
              onPressed: () => _showSubtaskDialog(st: st),
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _softPill(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withValues(alpha: 0.05),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: AppTheme.textMuted),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.95), fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertiesSidebar(Map<String, dynamic> t) {
    final people = _assigneeIds.map((id) {
      final emp = _employees.cast<Map?>().firstWhere(
            (e) => int.tryParse('${e?['id'] ?? e?['user_id']}') == id,
            orElse: () => null,
          );
      final fromList = _taskAssigneeList(t, _employees).where((p) => int.tryParse('${p['id']}') == id);
      final p = fromList.isNotEmpty ? fromList.first : null;
      return {
        'id': id,
        'name': p?['name'] ?? (emp != null ? _displayStr(emp) : 'User'),
        'role': p?['role'] ?? emp?['role'] ?? emp?['department'] ?? t['stage_name']?.toString() ?? '',
      };
    }).toList();

    final stageOptions = _stages
        .map((s) => ('${s['id']}', s['name']?.toString() ?? 'Stage', const Color(0xFF3B82F6)))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _propLabel('People'),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'No one assigned yet',
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.75), fontSize: 12),
            ),
          )
        else
          ...people.map((p) => _assigneeCard(p)),
        if (widget.isManager || _employees.isNotEmpty)
          TextButton.icon(
            onPressed: _pickAssignees,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: AppTheme.accent),
            label: Text(
              people.isEmpty ? 'Assign someone' : 'Change assignees',
              style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.centerLeft,
            ),
          ),
        const SizedBox(height: 12),
        _propDropdown('Priority', _priority, _priorityOptions, (v) => _setField(() => _priority = v, {'priority': v})),
        const SizedBox(height: 12),
        if (stageOptions.isNotEmpty) ...[
          _propDropdown(
            'Stage',
            '${_stageId ?? ''}',
            stageOptions,
            (v) {
              final sid = int.tryParse(v);
              if (sid != null) _setField(() => _stageId = sid, {'stage_id': sid});
            },
          ),
          const SizedBox(height: 12),
        ],
        _propDropdown('Type', _taskType, _typeOptions, (v) => _setField(() => _taskType = v, {'task_type': v})),
        const SizedBox(height: 14),
        _propLabel('Schedule'),
        _dateField('Start', _startDate, 'start_date'),
        const SizedBox(height: 8),
        _dateField('Due', _dueDate, 'due_date'),
        const SizedBox(height: 14),
        _propLabel('Time'),
        Row(
          children: [
            Expanded(child: _hoursField('Estimate', _estHoursCtrl, 'hours')),
            const SizedBox(width: 8),
            Expanded(child: _hoursField('Actual', _actHoursCtrl, 'hours')),
          ],
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _isAttachmentRequired,
          onChanged: (v) => _setField(
            () => _isAttachmentRequired = v ?? false,
            {'is_attachment_required': v ?? false},
          ),
          activeColor: AppTheme.accent,
          checkColor: Colors.white,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'Require attachment to complete',
            style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.88), fontSize: 12),
          ),
          subtitle: Text(
            _attachments.isEmpty ? 'No files yet' : '${_attachments.length} file(s)',
            style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _assigneeCard(Map<String, dynamic> p) {
    final id = int.tryParse('${p['id']}');
    final name = p['name']?.toString() ?? 'User';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.35),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (id != null && (widget.isManager || _employees.isNotEmpty))
            IconButton(
              onPressed: () => _removeAssignee(id),
              icon: Icon(Icons.close_rounded, size: 16, color: Colors.white.withValues(alpha: 0.45)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
        ],
      ),
    );
  }

  Widget _propLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.textMuted.withValues(alpha: 0.9),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static const _priorityOptions = [
    ('low', 'Low', AppTheme.success),
    ('medium', 'Medium', AppTheme.warning),
    ('high', 'High', AppTheme.danger),
  ];

  static const _typeOptions = [
    ('task', 'Task', Color(0xFF71717A)),
    ('bug', 'Bug', Color(0xFFEF4444)),
    ('feature', 'Feature', Color(0xFF8B5CF6)),
    ('improvement', 'Improvement', Color(0xFF10B981)),
  ];

  Widget _propDropdown(
    String label,
    String value,
    List<(String, String, Color)> options,
    ValueChanged<String> onChanged,
  ) {
    final valid = options.any((o) => o.$1 == value);
    final current = valid ? value : (options.isNotEmpty ? options.first.$1 : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 10)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: _fieldDeco(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: current,
              isExpanded: true,
              dropdownColor: AppTheme.surface2,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              items: options
                  .map(
                    (o) => DropdownMenuItem(
                      value: o.$1,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: o.$3, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(o.$2),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateField(String label, String? iso, String field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 10)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _pickDate(field),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: _fieldDeco(),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Colors.white38),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    iso == null ? 'Not set' : _fmtDateDisplay(iso),
                    style: TextStyle(
                      color: iso == null ? Colors.white38 : Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (iso != null)
                  GestureDetector(
                    onTap: () => _clearDate(field),
                    child: const Icon(Icons.close, size: 14, color: Colors.white38),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _hoursField(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 10)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
            prefixIcon: const Icon(Icons.schedule, size: 14, color: Colors.white38),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityTab() {
    final pad = Responsive.pagePadding(context);
    if (widget.projectId <= 0) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Text(
            'Activity log requires project context',
            style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_activityLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_activity.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Text(
            _activityLoaded ? 'No activity yet' : 'Open this tab to load updates',
            style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, pad + 8),
      itemCount: _activity.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final a = _activity[i] as Map? ?? {};
        final user = a['user_name']?.toString() ?? 'Someone';
        final summary = a['summary']?.toString() ?? a['description']?.toString() ?? a['action']?.toString() ?? 'Activity';
        final ts = a['timestamp']?.toString() ?? '';
        String when = ts;
        final dt = DateTime.tryParse(ts);
        if (dt != null) when = DateFormat('d MMM · HH:mm').format(dt.toLocal());
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                child: Text(
                  user.isNotEmpty ? user[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary,
                      style: TextStyle(
                        color: AppTheme.textPrimary.withValues(alpha: 0.95),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$user · $when',
                      style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0B1F3A).withValues(alpha: 0.98),
            const Color(0xFF071526),
          ],
        ),
        border: Border(
          top: BorderSide(color: AppTheme.accent.withValues(alpha: 0.28), width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 14 : 18, 12, compact ? 14 : 18, compact ? 10 : 14),
          child: TaskDetailFooterActions(
            dirty: _dirty,
            saving: _saving,
            saveHint: _saveHint,
            onSave: _saveAll,
          ),
        ),
      ),
    );
  }

  void _showSubtaskDialog({dynamic st}) {
    final page = _SubtaskEditDialog(
      apiService: widget.apiService,
      taskId: widget.taskId,
      projectId: widget.projectId,
      employees: _employees,
      subtask: st,
      onSaved: _load,
    );
    final narrow = MediaQuery.sizeOf(context).width < 720;
    if (narrow) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: AppTheme.modalBarrierColor,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: page,
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => page,
    );
  }

  BoxDecoration _cardDeco() => AppTheme.loginInsetDecoration(borderRadius: 14);

  BoxDecoration _fieldDeco() => AppTheme.loginInsetDecoration(borderRadius: 10);
}

class _SubtaskEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int taskId;
  final int projectId;
  final List<dynamic> employees;
  final dynamic subtask;
  final Future<void> Function() onSaved;

  const _SubtaskEditDialog({
    required this.apiService,
    required this.taskId,
    this.projectId = 0,
    required this.employees,
    required this.onSaved,
    this.subtask,
  });

  @override
  State<_SubtaskEditDialog> createState() => _SubtaskEditDialogState();
}

class _SubtaskEditDialogState extends State<_SubtaskEditDialog> {
  
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _descCtrl;
  late String _priority;
  late String _status;
  int? _assigneeId;
  String? _dueDate;
  List<dynamic> _attachments = [];
  bool _loadingAttachments = false;
  bool _saving = false;

  bool get _isEdit => widget.subtask != null;

  @override
  void initState() {
    super.initState();
    final st = widget.subtask;
    _summaryCtrl = TextEditingController(text: st?['summary']?.toString() ?? '');
    _descCtrl = TextEditingController(text: st?['description']?.toString() ?? '');
    _priority = (st?['priority'] ?? 'medium').toString();
    _status = (st?['status'] ?? 'to_do').toString();
    if (_status == 'completed') _status = 'done';
    _assigneeId = int.tryParse('${st?['assignee_id'] ?? st?['user_id'] ?? ''}');
    _dueDate = st?['due_date']?.toString();
    if (_dueDate != null && _dueDate!.length >= 10) _dueDate = _dueDate!.substring(0, 10);
    if (_isEdit) _loadAttachments();
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAttachments() async {
    final sid = int.tryParse('${widget.subtask['id']}');
    if (sid == null) return;
    setState(() => _loadingAttachments = true);
    final r = await widget.apiService.getSubTaskAttachments(widget.taskId, sid);
    if (!mounted) return;
    setState(() {
      _loadingAttachments = false;
      if (r['success'] == true) {
        _attachments = r['data'] is List ? List<dynamic>.from(r['data'] as List) : [];
      }
    });
  }

  Future<void> _uploadAttachment() async {
    if (!_isEdit) return;
    final sid = widget.subtask['id'] as int;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    List<int>? bytes = f.bytes?.toList();
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null || f.name.isEmpty) return;
    final r = await widget.apiService.uploadSubTaskAttachment(widget.taskId, sid, bytes, f.name);
    if (!mounted) return;
    if (r['success'] == true) {
      await _loadAttachments();
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Upload failed');
    }
  }

  Future<void> _deleteAttachment(dynamic a) async {
    if (!_isEdit) return;
    final sid = widget.subtask['id'] as int;
    final aid = int.tryParse('${a['id']}');
    if (aid == null) return;
    final r = await widget.apiService.deleteSubTaskAttachment(widget.taskId, sid, aid);
    if (!mounted) return;
    if (r['success'] == true) {
      await _loadAttachments();
    }
  }

  Future<void> _save() async {
    if (_summaryCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'summary': _summaryCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'priority': _priority,
      'status': _status,
    };
    if (_assigneeId != null) body['assignee_id'] = _assigneeId;
    body['due_date'] = _dueDate;
    if (_isEdit) {
      await widget.apiService.updateSubTask(
        widget.taskId,
        widget.subtask['id'],
        body,
        projectId: widget.projectId,
      );
    } else {
      await widget.apiService.createSubTask(
        widget.taskId,
        summary: _summaryCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        priority: _priority,
        status: _status,
        assigneeId: _assigneeId,
        dueDate: _dueDate,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    await widget.onSaved();
  }

  InputDecoration _inputDeco(String? hint) => AppTheme.taskInputDecoration(hint);

  Widget _field(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textMuted.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow) ...[
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
        Text(
          _isEdit ? 'Edit subtask' : 'Add subtask',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Keep it short — one clear step',
          style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12),
        ),
        const SizedBox(height: 16),
        _field(
          'What to do',
          TextField(
            controller: _summaryCtrl,
            autofocus: !_isEdit,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDeco('e.g. Design login screen'),
          ),
        ),
        const SizedBox(height: 12),
        _field(
          'Notes (optional)',
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            minLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _inputDeco('Extra detail…'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _field(
                'Priority',
                DropdownButtonFormField<String>(
                  initialValue: ['low', 'medium', 'high'].contains(_priority) ? _priority : 'medium',
                  dropdownColor: AppTheme.surface2,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDeco(null),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) => setState(() => _priority = v ?? 'medium'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                'Status',
                DropdownButtonFormField<String>(
                  initialValue: ['to_do', 'in_progress', 'done'].contains(_status) ? _status : 'to_do',
                  dropdownColor: AppTheme.surface2,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDeco(null),
                  items: const [
                    DropdownMenuItem(value: 'to_do', child: Text('To do')),
                    DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
                    DropdownMenuItem(value: 'done', child: Text('Done')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'to_do'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _field(
                'Assignee',
                DropdownButtonFormField<int?>(
                  initialValue: _assigneeId,
                  dropdownColor: AppTheme.surface2,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDeco(null),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Unassigned')),
                    ...widget.employees.map((e) {
                      final id = int.tryParse('${e['id'] ?? e['user_id']}');
                      return DropdownMenuItem<int?>(value: id, child: Text(_displayStr(e)));
                    }),
                  ],
                  onChanged: (v) => setState(() => _assigneeId = v),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                'Due',
                InkWell(
                  onTap: () async {
                    final initial = _dueDate != null ? DateTime.tryParse(_dueDate!) ?? DateTime.now() : DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() {
                        _dueDate =
                            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: _inputDeco(null),
                    child: Text(
                      _dueDate ?? 'Not set',
                      style: TextStyle(color: _dueDate == null ? Colors.white38 : Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_isEdit) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Files',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _uploadAttachment,
                icon: const Icon(Icons.upload_rounded, size: 14, color: AppTheme.primaryBright),
                label: const Text('Upload', style: TextStyle(color: AppTheme.primaryBright, fontSize: 12)),
              ),
            ],
          ),
          if (_loadingAttachments)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))),
            )
          else if (_attachments.isEmpty)
            Text('No files', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12))
          else
            ..._attachments.map((a) {
              final name = a['file_name']?.toString() ?? 'file';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file_rounded, size: 16, color: AppTheme.featureVault),
                title: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                  onPressed: () => _deleteAttachment(a),
                ),
              );
            }),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.black.withValues(alpha: 0.22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF38BDF8), Color(0xFF3B82F6)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _isEdit ? 'Save' : 'Add subtask',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isEdit) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await widget.apiService.deleteSubTask(widget.taskId, widget.subtask['id']);
                          await widget.onSaved();
                        },
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFF87171)),
                  label: const Text(
                    'Delete subtask',
                    style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final panel = Container(
      constraints: BoxConstraints(maxWidth: narrow ? double.infinity : 460),
      decoration: AppTheme.loginInsetDecoration(borderRadius: narrow ? 20 : 16),
      padding: EdgeInsets.fromLTRB(16, narrow ? 10 : 18, 16, 16),
      child: SingleChildScrollView(child: form),
    );

    if (narrow) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: panel,
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: AppTheme.dialogInsets(context),
      child: panel,
    );
  }
}
