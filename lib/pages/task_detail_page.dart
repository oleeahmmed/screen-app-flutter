import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_quick_menu.dart';
import '../widgets/kanban_assignee_picker.dart';
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
  final uid = int.tryParse('${task['user_id'] ?? task['user'] ?? ''}');
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

/// Opens the web-style task detail page (DETAILS | ACTIVITY + PROPERTIES sidebar).
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
}) {
  Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: false,
      builder: (_) => TaskDetailPage(
        apiService: apiService,
        taskId: taskId,
        projectId: projectId,
        projectName: projectName,
        customerName: customerName,
        initialTask: initialTask,
        employees: employees,
        stages: stages,
        isManager: isManager,
      ),
    ),
  ).then((_) => onClosed?.call());
}

/// Production web task detail modal — full page with DETAILS | ACTIVITY tabs.
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
  final List<String> _descUndo = [];
  final List<String> _descRedo = [];
  bool _descPreview = false;
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
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1 && !_activityLoaded && widget.projectId > 0) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('At least one assignee is required')),
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _saveHint = 'Saving…';
    });
    final r = await widget.apiService.updateTask(widget.taskId, body);
    if (!mounted) return;
    if (r['success'] == true) {
      if (r['data'] is Map) {
        _task = Map<String, dynamic>.from(r['data'] as Map);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not save')),
      );
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

  Future<void> _load() async {
    setState(() {
      _loading = _task == null;
      _loadError = null;
    });
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
    return DateFormat('d MMM yyyy, HH:mm').format(dt);
  }

  Future<void> _saveAll() async {
    if (_task == null) return;
    _autoSaveTimer?.cancel();
    await _flushTextAutoSave();
    if (_assigneeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one assignee is required')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All changes saved')),
      );
      return;
    }
    await _patchPartial(body);
    if (!mounted) return;
    if (_saveHint == 'Saved') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changes saved')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one assignee is required')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded $name')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(up['error']?.toString() ?? 'Upload failed')),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copy a file in Explorer, then Paste — or drag files here')),
    );
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

  void _pushDescHistory() {
    _descUndo.add(_descCtrl.text);
    if (_descUndo.length > 40) _descUndo.removeAt(0);
    _descRedo.clear();
  }

  void _descUndoAction() {
    if (_descUndo.isEmpty) return;
    _descRedo.add(_descCtrl.text);
    _descCtrl.text = _descUndo.removeLast();
    _markDirty();
  }

  void _descRedoAction() {
    if (_descRedo.isEmpty) return;
    _descUndo.add(_descCtrl.text);
    _descCtrl.text = _descRedo.removeLast();
    _markDirty();
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _toggleSubtask(dynamic st) async {
    final r = await widget.apiService.toggleSubTask(widget.taskId, st['id'] as int);
    if (!mounted) return;
    if (r['success'] == true) {
      await _load();
    }
  }

  void _wrapSelection(String left, String right) {
    _pushDescHistory();
    final sel = _descCtrl.selection;
    if (!sel.isValid) return;
    final text = _descCtrl.text;
    final selected = sel.textInside(text);
    final newText = text.replaceRange(sel.start, sel.end, '$left$selected$right');
    _descCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + left.length + selected.length + right.length),
    );
  }

  void _shareTask() {
    final link = '${AppConfig.apiBaseUrl.replaceAll('/api', '')}/monitor/project/${widget.projectId}/?task=${widget.taskId}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task link copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;
    final taskKey = t?['task_key']?.toString() ?? 'T-${widget.taskId}';

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
      backgroundColor: AppTheme.bgDeep,
      body: Container(
        decoration: AppTheme.screenGradient(),
        child: SafeArea(
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
              _buildTopBar(taskKey),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildDetailsTab(t),
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

  Widget _buildTopBar(String taskKey) {
    final compact = Responsive.isMobile(context);
    final crumbs = [
      if (widget.customerName.isNotEmpty) 'Customers',
      if (widget.customerName.isNotEmpty) widget.customerName,
      if (widget.projectName.isNotEmpty) widget.projectName,
      _titleCtrl.text.trim().isEmpty ? taskKey : _titleCtrl.text.trim(),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 16, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppBackButton(color: AppTheme.textMuted),
              Expanded(
                child: Text(
                  crumbs.join(' › '),
                  style: AppTheme.caption.copyWith(fontSize: compact ? 10 : 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const AppQuickMenuButton(iconColor: AppTheme.textMuted, iconSize: 20),
              IconButton(
                onPressed: _shareTask,
                icon: const Icon(Icons.share_outlined, color: Colors.white54, size: 20),
                tooltip: 'Share',
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.45)),
                ),
                child: Text(taskKey, style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 15 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final compact = Responsive.isMobile(context);
    final tabBar = TabBar(
      controller: _tabCtrl,
      indicatorColor: AppTheme.primary,
      indicatorWeight: 2.5,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white38,
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
      tabs: const [
        Tab(text: 'DETAILS'),
        Tab(text: 'ACTIVITY'),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tabBar,
          if (_saveHint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _saveHint,
                  style: TextStyle(
                    color: _saveHint == 'Saved' ? const Color(0xFF10B981) : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: tabBar),
        if (_saveHint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              _saveHint,
              style: TextStyle(
                color: _saveHint == 'Saved' ? const Color(0xFF10B981) : Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDetailsTab(Map<String, dynamic> t) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= Responsive.tabletMax;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: _buildLeftColumn()),
              Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
              Flexible(flex: 2, child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
                child: _buildPropertiesSidebar(t),
              )),
            ],
          );
        }
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: Responsive.pagePadding(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLeftColumn(scrollable: false),
              _buildPropertiesSidebar(t, collapsible: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeftColumn({bool scrollable = true}) {
    final pad = Responsive.pagePadding(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('DESCRIPTION', Icons.notes_rounded),
        const SizedBox(height: 8),
        _descriptionEditor(),
        const SizedBox(height: 22),
        _sectionHeader('ATTACHMENTS', Icons.attach_file_rounded, trailing: _attachmentActions()),
        const SizedBox(height: 8),
        _attachmentsPanel(),
        const SizedBox(height: 22),
        _sectionHeader('SUBTASKS', Icons.checklist_rounded, trailing: _subtaskAddButton()),
        const SizedBox(height: 8),
        _subtasksPanel(),
      ],
    );

    if (!scrollable) {
      return Padding(padding: EdgeInsets.all(pad), child: content);
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: content,
    );
  }

  Widget _sectionHeader(String title, IconData icon, {Widget? trailing}) {
    final compact = Responsive.isMobile(context);
    if (compact && trailing != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white38),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: trailing),
        ],
      );
    }
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  Widget _descriptionEditor() {
    return Container(
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (!_descPreview) ...[
                    _toolBtn(Icons.format_bold, () => _wrapSelection('**', '**')),
                    _toolBtn(Icons.format_italic, () => _wrapSelection('_', '_')),
                    _toolBtn(Icons.format_list_bulleted, () => _wrapSelection('\n- ', '')),
                    _toolBtn(Icons.format_list_numbered, () => _wrapSelection('\n1. ', '')),
                    _toolBtn(Icons.link, () => _wrapSelection('[', '](url)')),
                    _toolBtn(Icons.code, () => _wrapSelection('`', '`')),
                    _toolBtn(Icons.format_quote, () => _wrapSelection('\n> ', '')),
                    _toolBtn(Icons.undo, _descUndoAction),
                    _toolBtn(Icons.redo, _descRedoAction),
                  ],
                  const SizedBox(width: 8),
                  _descModeBtn('Edit', !_descPreview, () => setState(() => _descPreview = false)),
                  const SizedBox(width: 4),
                  _descModeBtn('Preview', _descPreview, () => setState(() => _descPreview = true)),
                ],
              ),
            ),
          ),
          if (_descPreview)
            Container(
              constraints: const BoxConstraints(minHeight: 160),
              padding: const EdgeInsets.all(14),
              child: _descCtrl.text.trim().isEmpty
                  ? Text(
                      'Nothing to preview',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
                    )
                  : MarkdownBody(
                      data: _descCtrl.text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.5),
                        h1: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        h2: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        h3: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        code: TextStyle(
                          color: const Color(0xFFA78BFA),
                          backgroundColor: Colors.black.withValues(alpha: 0.35),
                          fontFamily: 'monospace',
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
                        ),
                        blockquote: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                        a: const TextStyle(color: AppTheme.primary, decoration: TextDecoration.underline),
                        listBullet: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      onTapLink: (text, href, title) {
                        if (href != null) _openUrl(href);
                      },
                    ),
            )
          else
            TextField(
              controller: _descCtrl,
              maxLines: 10,
              minLines: 6,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, height: 1.5),
              decoration: InputDecoration(
                hintText: 'Add a description… (Markdown supported)',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _descModeBtn(String label, bool active, VoidCallback onTap) {
    return Material(
      color: active ? AppTheme.primary.withValues(alpha: 0.25) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppTheme.primary : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: Colors.white38),
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    );
  }

  Widget _attachmentActions() {
    final compact = Responsive.isMobile(context);
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _uploadFile,
            icon: const Icon(Icons.upload, size: 18, color: AppTheme.primary),
            tooltip: 'Upload',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: _pasteFromClipboard,
            icon: Icon(Icons.content_paste, size: 18, color: Colors.white.withValues(alpha: 0.5)),
            tooltip: 'Paste',
            visualDensity: VisualDensity.compact,
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: _uploadFile,
          icon: const Icon(Icons.upload, size: 14, color: AppTheme.primary),
          label: const Text('Upload', style: TextStyle(color: AppTheme.primary, fontSize: 12)),
        ),
        TextButton.icon(
          onPressed: _pasteFromClipboard,
          icon: Icon(Icons.content_paste, size: 14, color: Colors.white.withValues(alpha: 0.5)),
          label: Text('Paste', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Could not delete')),
      );
    }
  }

  bool _focusInTextField() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    return focus.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Widget _attachmentsPanel() {
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(20),
        decoration: _cardDeco().copyWith(
          border: Border.all(
            color: _attachmentsDragOver ? AppTheme.primary : Colors.white.withValues(alpha: 0.08),
            width: _attachmentsDragOver ? 2 : 1,
          ),
        ),
        child: _attachments.isEmpty
            ? Center(
                child: Text(
                  _attachmentsDragOver
                      ? 'Drop files here…'
                      : (Responsive.isMobile(context)
                          ? 'No attachments — tap Upload'
                          : 'No attachments yet — upload, drop, or paste (Ctrl+V)'),
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
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file, color: Color(0xFFA78BFA), size: 20),
                    title: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.open_in_new, size: 16, color: Colors.white38),
                          onPressed: () => _openUrl(a['file_url']?.toString()),
                          tooltip: 'Open',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                          onPressed: () => _deleteAttachment(a),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }

  Widget _subtaskAddButton() {
    return FilledButton.icon(
      onPressed: () => _showSubtaskDialog(),
      icon: const Icon(Icons.add, size: 14),
      label: const Text('Add', style: TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _subtasksPanel() {
    if (_subtasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: _cardDeco(),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Icon(Icons.add, color: Colors.white.withValues(alpha: 0.35)),
            ),
            const SizedBox(height: 12),
            Text(
              'No subtasks yet. Break this task into smaller steps.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (Responsive.isMobile(context)) {
      return Column(
        children: _subtasks.map((st) => _subtaskMobileCard(st)).toList(),
      );
    }
    return Container(
      decoration: _cardDeco(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.03)),
          dataRowMinHeight: 44,
          columns: const [
            DataColumn(label: SizedBox(width: 28)),
            DataColumn(label: Text('Summary', style: TextStyle(color: Colors.white54, fontSize: 10))),
            DataColumn(label: Text('Priority', style: TextStyle(color: Colors.white54, fontSize: 10))),
            DataColumn(label: Text('Status', style: TextStyle(color: Colors.white54, fontSize: 10))),
            DataColumn(label: Text('Assignee', style: TextStyle(color: Colors.white54, fontSize: 10))),
            DataColumn(label: Text('Due', style: TextStyle(color: Colors.white54, fontSize: 10))),
            DataColumn(label: SizedBox(width: 64)),
          ],
          rows: _subtasks.map((st) {
            final done = st['completed'] == true || st['status']?.toString() == 'completed';
            final due = st['due_date']?.toString() ?? '';
            return DataRow(
              onSelectChanged: (_) => _showSubtaskDialog(st: st),
              cells: [
              DataCell(Checkbox(value: done, activeColor: AppTheme.primary, onChanged: (_) => _toggleSubtask(st))),
              DataCell(Text(st['summary']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 12))),
              DataCell(Text(st['priority']?.toString() ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11))),
              DataCell(SubtaskStatusBadge(subtask: st)),
              DataCell(Text(_displayStr(st['assignee_name']), style: const TextStyle(color: Colors.white54, fontSize: 11))),
              DataCell(Text(due.length >= 10 ? due.substring(0, 10) : '—', style: const TextStyle(color: Colors.white54, fontSize: 11))),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white38),
                    onPressed: () => _showSubtaskDialog(st: st),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                    onPressed: () => widget.apiService.deleteSubTask(widget.taskId, st['id']).then((_) => _load()),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  ),
                ],
              )),
            ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _subtaskMobileCard(dynamic st) {
    final done = st['completed'] == true || st['status']?.toString() == 'completed';
    final due = st['due_date']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _cardDeco(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showSubtaskDialog(st: st),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: done,
                  activeColor: AppTheme.primary,
                  onChanged: (_) => _toggleSubtask(st),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        st['summary']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SubtaskStatusBadge(subtask: st),
                          Text(
                            st['priority']?.toString() ?? '',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                          ),
                          if (due.length >= 10)
                            Text(
                              due.substring(0, 10),
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                            ),
                        ],
                      ),
                      if (_displayStr(st['assignee_name']).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _displayStr(st['assignee_name']),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 18, color: Colors.white38),
                  onPressed: () => _showSubtaskDialog(st: st),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPropertiesSidebar(Map<String, dynamic> t, {bool collapsible = false}) {
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

    final stackOnNarrow = Responsive.isMobile(context);
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _propLabel('Assignee'),
        ...people.map((p) => _assigneeCard(p)),
        if (widget.isManager || _employees.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _pickAssignees,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add / Change', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        const SizedBox(height: 16),
        if (stackOnNarrow) ...[
          _propDropdown('Status', _status, _statusOptions, (v) => _setField(() => _status = v, {'status': v})),
          const SizedBox(height: 12),
          _propDropdown('Priority', _priority, _priorityOptions, (v) => _setField(() => _priority = v, {'priority': v})),
          const SizedBox(height: 12),
          _propDropdown('Type', _taskType, _typeOptions, (v) => _setField(() => _taskType = v, {'task_type': v})),
          const SizedBox(height: 12),
          _propDropdown(
            'Stage',
            '${_stageId ?? ''}',
            _stages.map((s) => ('${s['id']}', s['name']?.toString() ?? 'Stage', const Color(0xFF3B82F6))).toList(),
            (v) {
              final sid = int.tryParse(v);
              if (sid != null) _setField(() => _stageId = sid, {'stage_id': sid});
            },
          ),
        ] else ...[
          Row(
            children: [
              Expanded(child: _propDropdown('Status', _status, _statusOptions, (v) => _setField(() => _status = v, {'status': v}))),
              const SizedBox(width: 8),
              Expanded(child: _propDropdown('Priority', _priority, _priorityOptions, (v) => _setField(() => _priority = v, {'priority': v}))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _propDropdown('Type', _taskType, _typeOptions, (v) => _setField(() => _taskType = v, {'task_type': v}))),
              const SizedBox(width: 8),
              Expanded(
                child: _propDropdown(
                  'Stage',
                  '${_stageId ?? ''}',
                  _stages.map((s) => ('${s['id']}', s['name']?.toString() ?? 'Stage', const Color(0xFF3B82F6))).toList(),
                  (v) {
                    final sid = int.tryParse(v);
                    if (sid != null) _setField(() => _stageId = sid, {'stage_id': sid});
                  },
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _propLabel('Progress'),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progressPct(t) / 100,
            minHeight: 6,
            backgroundColor: Colors.black.withValues(alpha: 0.4),
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _progressLabel(t),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _isAttachmentRequired,
          onChanged: (v) => _setField(
            () => _isAttachmentRequired = v ?? false,
            {'is_attachment_required': v ?? false},
          ),
          activeColor: AppTheme.primary,
          checkColor: Colors.white,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'Attachment required',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
          ),
          subtitle: Text(
            _attachments.isEmpty ? 'No files attached yet' : '${_attachments.length} file(s)',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
          ),
        ),
        const SizedBox(height: 16),
        _propLabel('Dates'),
        _dateField('Start Date', _startDate, 'start_date'),
        const SizedBox(height: 8),
        _dateField('Due Date', _dueDate, 'due_date'),
        const SizedBox(height: 16),
        if (stackOnNarrow) ...[
          _hoursField('Est. Hours', _estHoursCtrl, 'e.g. 4'),
          const SizedBox(height: 12),
          _hoursField('Act. Hours', _actHoursCtrl, 'e.g. 3.5'),
        ] else
          Row(
            children: [
              Expanded(child: _hoursField('Est. Hours', _estHoursCtrl, 'e.g. 4')),
              const SizedBox(width: 8),
              Expanded(child: _hoursField('Act. Hours', _actHoursCtrl, 'e.g. 3.5')),
            ],
          ),
      ],
    );

    if (collapsible) {
      return Padding(
        padding: EdgeInsets.fromLTRB(Responsive.pagePadding(context), 0, Responsive.pagePadding(context), 8),
        child: DecoratedBox(
          decoration: _cardDeco(),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              iconColor: Colors.white54,
              collapsedIconColor: Colors.white38,
              title: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 16, color: Colors.white.withValues(alpha: 0.45)),
                  const SizedBox(width: 8),
                  Text(
                    'PROPERTIES',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: fields,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: AppTheme.surface.withValues(alpha: 0.5),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.settings_outlined, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                const SizedBox(width: 6),
                Text(
                  'PROPERTIES',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            fields,
          ],
        ),
      ),
    );
  }

  Widget _assigneeCard(Map<String, dynamic> p) {
    final id = int.tryParse('${p['id']}');
    final name = p['name']?.toString() ?? 'User';
    final role = p['role']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF334155),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                if (role.isNotEmpty)
                  Text(role, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
              ],
            ),
          ),
          if (id != null && (widget.isManager || _employees.isNotEmpty))
            IconButton(
              onPressed: () => _removeAssignee(id),
              icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
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
        text.toUpperCase(),
        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  static const _statusOptions = [
    ('pending', 'Pending', Color(0xFF71717A)),
    ('in_progress', 'In progress', Color(0xFF3B82F6)),
    ('completed', 'Done', Color(0xFF10B981)),
  ];

  static const _priorityOptions = [
    ('low', 'Low', Color(0xFF71717A)),
    ('medium', 'Medium', Color(0xFF3B82F6)),
    ('high', 'High', Color(0xFFEF4444)),
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
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: current,
              isExpanded: true,
              dropdownColor: const Color(0xFF1e293b),
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
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _pickDate(field),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
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
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
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
    if (widget.projectId <= 0) {
      return Center(
        child: Text(
          'Activity log requires project context',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
        ),
      );
    }
    if (_activityLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_activity.isEmpty) {
      return Center(
        child: Text(
          _activityLoaded ? 'No activity yet' : 'Switch to this tab to load activity',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _activity.length,
      separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
      itemBuilder: (context, i) {
        final a = _activity[i] as Map? ?? {};
        final user = a['user_name']?.toString() ?? 'Someone';
        final summary = a['summary']?.toString() ?? a['description']?.toString() ?? a['action']?.toString() ?? 'Activity';
        final ts = a['timestamp']?.toString() ?? '';
        String when = ts;
        final dt = DateTime.tryParse(ts);
        if (dt != null) when = DateFormat('d MMM yyyy, HH:mm').format(dt.toLocal());
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF334155),
            child: Text(user.isNotEmpty ? user[0].toUpperCase() : '?', style: const TextStyle(fontSize: 11, color: Colors.white)),
          ),
          title: Text(summary, style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text('$user · $when', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
        );
      },
    );
  }

  Widget _buildFooter() {
    final compact = Responsive.isMobile(context);
    final hint = _saveHint.isNotEmpty
        ? _saveHint
        : (compact ? 'Auto-saves' : 'Auto-saves · Ctrl+S · Esc');

    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 12, compact ? 12 : 20, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _saveHint == 'Saved'
                            ? const Color(0xFF10B981)
                            : Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _dirty ? _discard : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Discard'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _saveAll,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check, size: 16),
                        label: const Text('Save'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                OutlinedButton(
                  onPressed: _dirty ? _discard : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Discard'),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    hint,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _saveHint == 'Saved'
                          ? const Color(0xFF10B981)
                          : Colors.white.withValues(alpha: 0.25),
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                  ),
                FilledButton.icon(
                  onPressed: _saving ? null : _saveAll,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Save Changes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
    );
  }

  void _showSubtaskDialog({dynamic st}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _SubtaskEditDialog(
        apiService: widget.apiService,
        taskId: widget.taskId,
        employees: _employees,
        subtask: st,
        onSaved: _load,
      ),
    );
  }

  BoxDecoration _cardDeco() {
    return BoxDecoration(
      color: AppTheme.surface2.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    );
  }
}

class _SubtaskEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int taskId;
  final List<dynamic> employees;
  final dynamic subtask;
  final Future<void> Function() onSaved;

  const _SubtaskEditDialog({
    required this.apiService,
    required this.taskId,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Upload failed')),
      );
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
      await widget.apiService.updateSubTask(widget.taskId, widget.subtask['id'], body);
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

  InputDecoration _inputDeco(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _field(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface2,
      insetPadding: AppTheme.dialogInsets(context),
      title: Text(_isEdit ? 'Edit subtask' : 'Add subtask', style: const TextStyle(color: Color(0xFFF8FAFC))),
      content: SizedBox(
        width: AppTheme.dialogMaxWidth(context, max: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field('Summary *', TextField(
                controller: _summaryCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco('What needs to be done…'),
              )),
              const SizedBox(height: 12),
              _field('Description', TextField(
                controller: _descCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco('Optional details…'),
              )),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field('Priority', DropdownButtonFormField<String>(
                      initialValue: ['low', 'medium', 'high'].contains(_priority) ? _priority : 'medium',
                      dropdownColor: const Color(0xFF1e293b),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDeco(null),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                      ],
                      onChanged: (v) => setState(() => _priority = v ?? 'medium'),
                    )),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field('Status', DropdownButtonFormField<String>(
                      initialValue: ['to_do', 'in_progress', 'done'].contains(_status) ? _status : 'to_do',
                      dropdownColor: const Color(0xFF1e293b),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDeco(null),
                      items: const [
                        DropdownMenuItem(value: 'to_do', child: Text('To Do')),
                        DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                        DropdownMenuItem(value: 'done', child: Text('Done')),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? 'to_do'),
                    )),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field('Assignee', DropdownButtonFormField<int?>(
                      initialValue: _assigneeId,
                      dropdownColor: const Color(0xFF1e293b),
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
                    )),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field('Due date', InkWell(
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
                    )),
                  ),
                ],
              ),
              if (_isEdit) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'ATTACHMENTS',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _uploadAttachment,
                      icon: const Icon(Icons.upload, size: 14, color: AppTheme.primary),
                      label: const Text('Upload', style: TextStyle(color: AppTheme.primary, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_loadingAttachments)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                  ))
                else if (_attachments.isEmpty)
                  Text(
                    'No attachments',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
                  )
                else
                  ..._attachments.map((a) {
                    final name = a['file_name']?.toString() ?? 'file';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file, size: 16, color: Color(0xFFA78BFA)),
                      title: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        onPressed: () => _deleteAttachment(a),
                      ),
                    );
                  }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_isEdit)
          TextButton(
            onPressed: _saving
                ? null
                : () async {
                    Navigator.pop(context);
                    await widget.apiService.deleteSubTask(widget.taskId, widget.subtask['id']);
                    await widget.onSaved();
                  },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
