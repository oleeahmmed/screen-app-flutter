// api_service.dart - API Service

import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'attendance_cache.dart';
import 'user_data_service.dart';

class ApiService {
  String? _token;

  // Initialize token from storage
  Future<void> initToken() async {
    _token = await UserDataService.getAuthToken();
    if (_token != null && _token!.isNotEmpty) {
      print('🔑 Token loaded from storage');
    }
  }

  void setToken(String token) {
    _token = token;
  }

  String? get token => _token;

  Future<void> ensureAuth() async {
    if (_token == null || _token!.isEmpty) {
      await initToken();
    }
  }

  Map<String, String> _jsonPostHeaders() {
    return {
      ..._authHeaderOnly(),
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
    };
  }

  bool _looksLikeHtml(String body) {
    final t = body.trimLeft().toLowerCase();
    return t.startsWith('<!doctype') ||
        t.startsWith('<html') ||
        t.startsWith('<head') ||
        (t.startsWith('<') && t.contains('<html'));
  }

  dynamic _safeJsonDecode(String body) {
    var s = body;
    if (s.startsWith('\uFEFF')) s = s.substring(1);
    s = s.trim();
    if (s.isEmpty) return <String, dynamic>{};
    return jsonDecode(s);
  }

  String _responsePreview(String body, {int max = 160}) {
    final t = body.trim();
    if (t.isEmpty) return '(empty body)';
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  /// POST check-in / check-out with JSON body, empty body fallback, and attendance verify.
  Future<Map<String, dynamic>> _postAttendanceAction({
    required Uri uri,
    required String label,
    required bool Function(Map<String, dynamic>? current) verifySuccess,
  }) async {
    await ensureAuth();

    Future<http.Response> sendJson() => http
        .post(uri, headers: _jsonPostHeaders(), body: '{}')
        .timeout(const Duration(seconds: 15));
    Future<http.Response> sendEmpty() => http
        .post(uri, headers: _authHeaderOnly())
        .timeout(const Duration(seconds: 15));

    http.Response? lastResponse;
    for (final send in [sendJson, sendEmpty]) {
      try {
        var response = await send();
        if (response.statusCode == 401 && await refreshAccessToken()) {
          response = await send();
        }
        lastResponse = response;
        final rawBody = response.body;

        if (_looksLikeHtml(rawBody)) {
          continue;
        }

        dynamic raw;
        try {
          raw = _safeJsonDecode(rawBody);
        } catch (_) {
          if (response.statusCode == 200 || response.statusCode == 201) {
            final verified = await _verifyAttendanceAfterAction(verifySuccess);
            if (verified['success'] == true) return verified;
          }
          continue;
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          if (raw is Map) {
            final msg = raw['message']?.toString().toLowerCase() ?? '';
            if (msg.contains('already checked in')) {
              return {'success': true, 'data': raw};
            }
          }
          return {'success': true, 'data': raw};
        }

        if (raw is Map) {
          final err = raw['message'] ?? raw['error'] ?? raw['detail'];
          if (err != null) {
            final verified = await _verifyAttendanceAfterAction(verifySuccess);
            if (verified['success'] == true) {
              final current = await getCurrentAttendance();
              if (current['success'] == true) return current;
            }
            return {'success': false, 'error': err.toString()};
          }
        }

        if (response.statusCode == 401) {
          return {'success': false, 'error': 'Session expired — please log in again'};
        }
        if (response.statusCode == 403) {
          return {'success': false, 'error': 'Access denied — subscription may have expired'};
        }
      } catch (_) {
        continue;
      }
    }

    final verified = await _verifyAttendanceAfterAction(verifySuccess);
    if (verified['success'] == true) return verified;

    if (lastResponse != null) {
      final code = lastResponse!.statusCode;
      final preview = _responsePreview(lastResponse!.body);
      if (_looksLikeHtml(lastResponse!.body)) {
        return {
          'success': false,
          'error': '$label failed — server returned a web page (HTTP $code). Log in again.',
        };
      }
      return {
        'success': false,
        'error': '$label failed (HTTP $code): $preview',
      };
    }

    return {'success': false, 'error': '$label failed — network error. Check connection and try again.'};
  }

  Future<Map<String, dynamic>> _verifyAttendanceAfterAction(
    bool Function(Map<String, dynamic>? current) verifySuccess,
  ) async {
    final result = await getCurrentAttendance();
    if (result['success'] != true) {
      return {'success': false, 'error': 'Could not verify attendance status'};
    }
    final data = result['data'] as Map<String, dynamic>? ?? {};
    final current = _attendanceMapFrom(data['current_attendance']);
    if (verifySuccess(current)) {
      return {'success': true, 'data': {'verified': true, 'current_attendance': current}};
    }
    return {'success': false, 'error': 'Attendance state did not update'};
  }

  dynamic _decodeJsonBody(String body, {required String context}) {
    if (body.trim().isEmpty) {
      throw FormatException('$context: empty response');
    }
    if (_looksLikeHtml(body)) {
      throw FormatException(
        '$context: server returned HTML (wrong URL or not logged in). '
        'Deploy latest API or check token.',
      );
    }
    return jsonDecode(body);
  }

  List<dynamic> _extractJsonList(
    dynamic decoded, {
    List<String> keys = const ['results', 'tasks', 'projects', 'data', 'notifications'],
  }) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in keys) {
        final v = decoded[key];
        if (v is List) return v;
      }
    }
    return [];
  }

  Map<String, String> _authHeaderOnly() {
    return {
      if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
    };
  }

  Future<http.Response> _authorizedGet(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
    bool retryOn401 = true,
  }) async {
    Future<http.Response> send() =>
        http.get(uri, headers: _getHeaders()).timeout(timeout);
    var response = await send();
    if (response.statusCode == 401 && retryOn401 && await refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  Future<http.Response> _authorizedPost(
    Uri uri, {
    Object? body,
    Duration timeout = const Duration(seconds: 15),
    bool retryOn401 = true,
  }) async {
    Future<http.Response> send() => http
        .post(uri, headers: _getHeaders(), body: body)
        .timeout(timeout);
    var response = await send();
    if (response.statusCode == 401 && retryOn401 && await refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  Future<http.Response> _authorizedPatch(
    Uri uri, {
    Object? body,
    Duration timeout = const Duration(seconds: 15),
    bool retryOn401 = true,
  }) async {
    Future<http.Response> send() => http
        .patch(uri, headers: _getHeaders(), body: body)
        .timeout(timeout);
    var response = await send();
    if (response.statusCode == 401 && retryOn401 && await refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  Future<http.Response> _authorizedDelete(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
    bool retryOn401 = true,
  }) async {
    Future<http.Response> send() =>
        http.delete(uri, headers: _getHeaders()).timeout(timeout);
    var response = await send();
    if (response.statusCode == 401 && retryOn401 && await refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  /// DRF JSON: `{ "error": "..." }` or field errors `{"summary":["..."]}`.
  String _parseApiErrorBody(String body, int code) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) {
        final e = d['error'] ?? d['detail'];
        if (e != null) return e is String ? e : e.toString();
        final buf = StringBuffer();
        d.forEach((k, v) {
          if (v is List) {
            buf.write('$k: ${v.join(", ")} ');
          } else if (v != null) {
            buf.write('$k: $v ');
          }
        });
        if (buf.isNotEmpty) return buf.toString().trim();
      }
    } catch (_) {}
    return 'Request failed ($code)';
  }

  String _apiDisplayString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    if (v is Map) {
      for (final key in ['full_name', 'name', 'username', 'email', 'label', 'title']) {
        final x = v[key];
        if (x != null && x.toString().trim().isNotEmpty) return x.toString();
      }
      final id = v['id'];
      if (id != null) return id.toString();
      return '';
    }
    if (v is List && v.isNotEmpty) return _apiDisplayString(v.first);
    return v.toString();
  }

  Map<String, dynamic> _normalizeProjectMap(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m);
    out['project_manager'] = _apiDisplayString(
      m['project_manager'] ?? m['project_manager_name'],
    );
    out['project_manager_name'] ??= out['project_manager'];
    out['customer_name'] = _apiDisplayString(m['customer_name'] ?? m['customer']);
    if (m['customer'] is Map && out['customer_id'] == null) {
      out['customer_id'] = (m['customer'] as Map)['id'];
    }
    final prog = m['completion_percentage'] ?? m['progress'] ?? m['completion'];
    if (prog != null) {
      final pct = prog is num ? prog.toDouble() : (double.tryParse('$prog') ?? 0.0);
      out['completion_percentage'] = pct;
      out['progress'] = pct;
      out['completion'] = pct;
    }
    if (out['description'] != null && out['description'] is! String) {
      out['description'] = _apiDisplayString(out['description']);
    }
    return out;
  }

  List<dynamic> _normalizeProjectItems(List<dynamic> list) {
    return list.map((p) {
      if (p is Map<String, dynamic>) return _normalizeProjectMap(p);
      if (p is Map) return _normalizeProjectMap(Map<String, dynamic>.from(p));
      return p;
    }).toList();
  }

  List<dynamic> _normalizeTaskList(dynamic raw) {
    final list = _extractJsonList(raw, keys: const ['tasks', 'results', 'data']);
    return list.map((t) {
      if (t is! Map) return t;
      final m = Map<String, dynamic>.from(t);
      m['name'] ??= m['title'];
      m['description'] ??= m['desc'];
      m['title'] ??= m['name'];
      m['desc'] ??= m['description'];
      if (m['description'] != null && m['description'] is! String) {
        m['description'] = _apiDisplayString(m['description']);
      }
      if (m['assignee'] != null && m['assignee'] is! String) {
        m['assignee'] = _apiDisplayString(m['assignee']);
      }
      if (m['user_name'] == null || (m['user_name'] is! String)) {
        m['user_name'] = _apiDisplayString(m['user_name'] ?? m['user']);
      }
      if (m['project_name'] != null && m['project_name'] is! String) {
        m['project_name'] = _apiDisplayString(m['project_name']);
      }
      if (m['completed'] == null && m['status'] != null) {
        m['completed'] = m['status'].toString() == 'completed';
      }
      if (m['project_id'] == null && m['project'] != null) {
        m['project_id'] = int.tryParse('${m['project']}');
      }
      if (m['assignee_ids'] is! List && m['user_id'] != null) {
        final uid = int.tryParse('${m['user_id']}');
        if (uid != null) m['assignee_ids'] = [uid];
      }
      return m;
    }).toList();
  }

  Map<String, dynamic> _normalizeTaskMap(Map<String, dynamic> m) {
    m['name'] ??= m['title'];
    m['description'] ??= m['desc'];
    m['title'] ??= m['name'];
    m['desc'] ??= m['description'];
    return m;
  }

  Map<String, dynamic> _normalizeProjectDetailMap(Map<String, dynamic> m) {
    final out = _normalizeProjectMap(m);
    if (out['stages'] is List) {
      out['stages'] = (out['stages'] as List).map((s) {
        if (s is! Map) return s;
        final stage = Map<String, dynamic>.from(s);
        if (stage['tasks'] is List) {
          stage['tasks'] = _normalizeTaskList(stage['tasks']);
        }
        return stage;
      }).toList();
    }
    if (out['unassigned_tasks'] is List) {
      out['unassigned_tasks'] = _normalizeTaskList(out['unassigned_tasks']);
    }
    return out;
  }

  Future<List<dynamic>?> _tryFetchProjectList(String url, String label) async {
    try {
      final response = await _authorizedGet(Uri.parse(url));
      if (response.statusCode != 200) return null;
      final decoded = _decodeJsonBody(response.body, context: label);
      final list = _extractJsonList(
        decoded,
        keys: const ['results', 'projects', 'data'],
      );
      if (list.isNotEmpty || decoded is List) {
        return _normalizeProjectItems(list.isNotEmpty ? list : decoded as List);
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<List<dynamic>?> _fetchProjectsFallback() async {
    final employeeId = await UserDataService.getEmployeeId();
    final userId = await UserDataService.getUserId();
    if (employeeId.isNotEmpty) {
      final list = await _tryFetchProjectList(
        AppConfig.employeeProjectsUrl(employeeId),
        'GET /api/employees/{employee_id}/projects/',
      );
      if (list != null && list.isNotEmpty) return list;
    }
    if (userId.isNotEmpty) {
      return _tryFetchProjectList(
        AppConfig.userProjectsUrl(userId),
        'GET /api/users/{user_id}/projects/',
      );
    }
    return null;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      print('🔐 Logging in with: $email');
      final body = jsonEncode({'username': email, 'password': password});
      final headers = {'Content-Type': 'application/json'};
      var response = await http
          .post(Uri.parse(AppConfig.authLoginUrl), headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) {
        response = await http
            .post(Uri.parse(AppConfig.authTokenUrl), headers: headers, body: body)
            .timeout(const Duration(seconds: 10));
      }

      print('📊 Login response: ${response.statusCode}');
      print('📝 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access'];
        
        // Check access_granted
        if (data['access_granted'] == false) {
          return {
            'success': false,
            'error': data['message'] ?? 'Access denied'
          };
        }
        
        return {'success': true, 'data': data};
      } else if (response.statusCode == 401) {
        return {'success': false, 'error': 'Invalid email or password'};
      }
      return {'success': false, 'error': 'Login failed: ${response.statusCode}'};
    } catch (e) {
      print('❌ Login error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/auth/forgot-password/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final err = body['error'] ?? body['detail'] ?? body['message'];
        if (err != null) {
          return {'success': false, 'error': err is String ? err : err.toString()};
        }
      } catch (_) {}
      return {'success': false, 'error': 'Could not send reset link (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static bool attendanceIsOpen(Map<String, dynamic>? att) {
    if (att == null) return false;
    final checkOut = att['check_out'];
    if (checkOut == null) return true;
    if (checkOut is String && checkOut.trim().isEmpty) return true;
    return false;
  }

  Map<String, dynamic> _normalizeAttendancePayload(Map raw) {
    final data = Map<String, dynamic>.from(raw);
    for (final key in [
      'current_attendance',
      'today_work_duration',
      'today_break_duration',
      'today_gross_work_duration',
      'effective_schedule',
      'active_break',
    ]) {
      final v = data[key];
      if (v is Map) data[key] = Map<String, dynamic>.from(v);
    }
    final sessions = data['sessions_today'];
    if (sessions is List) {
      data['sessions_today'] = sessions
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return data;
  }

  Map<String, dynamic>? _attendanceMapFrom(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  Future<Map<String, dynamic>> checkIn() async {
    final current = await getCurrentAttendance();
    if (current['success'] == true) {
      final att = _attendanceMapFrom(current['data']?['current_attendance']);
      if (attendanceIsOpen(att)) {
        return {
          'success': true,
          'data': current['data'],
        };
      }
    }
    final result = await _postAttendanceAction(
      uri: Uri.parse(AppConfig.checkInUrl),
      label: 'Check-in',
      verifySuccess: attendanceIsOpen,
    );
    if (result['success'] != true) return result;

    final raw = result['data'];
    if (raw is Map && raw['today_work_duration'] != null) {
      final data = _normalizeAttendancePayload(Map<String, dynamic>.from(raw));
      await AttendanceCache.save(data);
      return {'success': true, 'data': data};
    }
    return getCurrentAttendance();
  }

  Future<Map<String, dynamic>> checkOut() async {
    final result = await _postAttendanceAction(
      uri: Uri.parse(AppConfig.checkOutUrl),
      label: 'Check-out',
      verifySuccess: (current) => !attendanceIsOpen(current),
    );

    Future<Map<String, dynamic>> withSummary(Map<String, dynamic> ok) async {
      final raw = ok['data'];
      if (raw is Map && raw['today_work_duration'] != null) {
        final data = _normalizeAttendancePayload(Map<String, dynamic>.from(raw));
        await AttendanceCache.save(data);
        return {'success': true, 'data': data};
      }
      final current = await getCurrentAttendance();
      if (current['success'] == true) return current;
      return ok;
    }

    if (result['success'] == true) {
      return withSummary(result);
    }

    // Server may have closed the session even when HTTP response was an error.
    final current = await getCurrentAttendance();
    if (current['success'] == true) {
      final data = current['data'] as Map<String, dynamic>? ?? {};
      if (data['is_clocked_in'] != true) {
        return withSummary(current);
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _fetchTasksFromUrl(String url, String label) async {
    try {
      final response = await _authorizedGet(Uri.parse(url));
      print('📊 Tasks ($label): ${response.statusCode}');
      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': 'Failed to load tasks (${response.statusCode})',
        };
      }
      final decoded = _decodeJsonBody(response.body, context: label);
      return {'success': true, 'data': _normalizeTaskList(decoded)};
    } on FormatException catch (e) {
      print('❌ Tasks ($label): $e');
      return {'success': false, 'error': e.message};
    }
  }

  Future<Map<String, dynamic>> getMyTasks({String? status, int? projectId}) async {
    try {
      final query = <String, String>{};
      if (status == 'pending') query['status'] = 'pending';
      if (status == 'completed') query['status'] = 'completed';
      if (projectId != null) query['project_id'] = '$projectId';
      final uri = Uri.parse(AppConfig.myTasksUrl).replace(queryParameters: query.isEmpty ? null : query);
      final response = await _authorizedGet(uri);
      if (response.statusCode == 200) {
        final decoded = _decodeJsonBody(response.body, context: 'GET ${AppConfig.myTasksUrl}');
        if (decoded is Map<String, dynamic>) {
          final tasks = _normalizeTaskList(decoded['tasks'] ?? decoded);
          final projects = (decoded['projects'] as List? ?? [])
              .whereType<Map>()
              .map((p) => Map<String, dynamic>.from(p))
              .toList();
          return {
            'success': true,
            'data': {
              'tasks': tasks,
              'projects': projects,
              'pending_count': decoded['pending_count'],
              'completed_count': decoded['completed_count'],
              'count': decoded['count'],
            },
          };
        }
      }
      if (response.statusCode == 404) {
        return getTasks(mineOnly: true);
      }
      return {
        'success': false,
        'error': _parseApiErrorBody(response.body, response.statusCode),
      };
    } catch (e) {
      return {'success': false, 'error': 'My tasks error: $e'};
    }
  }

  Future<Map<String, dynamic>> getTasks({bool mineOnly = false}) async {
    try {
      print('📋 Loading tasks...');
      final employeeId = await UserDataService.getEmployeeId();
      final userId = await UserDataService.getUserId();

      final endpoints = <(String, String)>[
        (
          mineOnly ? '${AppConfig.tasksUrl}?mine=true' : AppConfig.tasksUrl,
          mineOnly ? 'GET /api/tasks/?mine=true' : 'GET /api/tasks/',
        ),
        if (employeeId.isNotEmpty)
          (
            AppConfig.employeeTasksUrl(employeeId),
            'GET /api/employees/{employee_id}/tasks/',
          ),
        if (userId.isNotEmpty)
          (
            AppConfig.userTasksUrl(userId),
            'GET /api/users/{user_id}/tasks/',
          ),
      ];

      Map<String, dynamic>? last;
      for (final (url, label) in endpoints) {
        final result = await _fetchTasksFromUrl(url, label);
        last = result;
        if (result['success'] == true) {
          final list = result['data'] as List<dynamic>? ?? [];
          if (list.isNotEmpty) return result;
        }
      }

      if (last != null && last['success'] == true) return last;
      return {
        'success': false,
        'error': last?['error'] ??
            'No tasks found. Tried /api/tasks/ and employee/user fallbacks.',
      };
    } catch (e) {
      print('❌ Tasks error: $e');
      return {'success': false, 'error': 'Tasks error: $e'};
    }
  }

  Map<String, dynamic>? _parseTaskDetailResponse(String body, String context) {
    final decoded = _decodeJsonBody(body, context: context);
    if (decoded is Map<String, dynamic>) {
      if (decoded['task'] is Map) {
        return _normalizeTaskMap(Map<String, dynamic>.from(decoded['task'] as Map));
      }
      if (decoded['id'] != null || decoded['name'] != null || decoded['title'] != null) {
        return _normalizeTaskMap(decoded);
      }
    }
    return null;
  }

  /// Full task detail — tries `/api/tasks/{id}/` then project-scoped URL.
  Future<Map<String, dynamic>> getTask(int taskId, {int projectId = 0}) async {
    final urls = <String>['${AppConfig.tasksUrl}$taskId/'];
    if (projectId > 0) {
      urls.add(AppConfig.projectTaskUrl(projectId, taskId));
    }
    var lastErr = 'Task not found';
    for (final url in urls) {
      try {
        final response = await _authorizedGet(Uri.parse(url));
        if (response.statusCode == 200) {
          final task = _parseTaskDetailResponse(response.body, 'GET $url');
          if (task != null) {
            return {'success': true, 'data': task};
          }
          lastErr = 'Invalid task response from server';
          continue;
        }
        if (response.statusCode == 404) {
          lastErr = 'Task not found';
          continue;
        }
        lastErr = _parseApiErrorBody(response.body, response.statusCode);
      } on FormatException catch (e) {
        lastErr = e.message;
      } catch (e) {
        lastErr = '$e';
      }
    }
    return {'success': false, 'error': lastErr};
  }

  /// POST `/api/projects/{project_id}/tasks/{id}/complete/` — mirrors aims-webapps.
  Future<Map<String, dynamic>> completeTask(
    int taskId, {
    int projectId = 0,
    Map<String, dynamic>? task,
  }) async {
    final pid = projectId > 0 ? projectId : _projectIdFromTask(task);
    if (pid != null && pid > 0) {
      final scoped = await _postTaskAction(
        AppConfig.projectTaskCompleteUrl(pid, taskId),
        'complete task',
      );
      if (scoped['success'] == true) return scoped;
      // Fall through to PATCH when project-scoped route fails unexpectedly.
      if (scoped['error']?.toString().contains('not found') != true) {
        return scoped;
      }
    }
    return updateTask(
      taskId,
      {'status': 'completed'},
      projectId: pid ?? 0,
      task: task,
    );
  }

  /// POST `/api/projects/{project_id}/tasks/{id}/reopen/` — mirrors aims-webapps.
  Future<Map<String, dynamic>> reopenTask(
    int taskId, {
    int projectId = 0,
    Map<String, dynamic>? task,
  }) async {
    final pid = projectId > 0 ? projectId : _projectIdFromTask(task);
    if (pid != null && pid > 0) {
      final scoped = await _postTaskAction(
        AppConfig.projectTaskReopenUrl(pid, taskId),
        'reopen task',
      );
      if (scoped['success'] == true) return scoped;
      if (scoped['error']?.toString().contains('not found') != true) {
        return scoped;
      }
    }
    return updateTask(
      taskId,
      {'status': 'pending'},
      projectId: pid ?? 0,
      task: task,
    );
  }

  /// Mark complete or reopen — preferred over legacy `/toggle/` (status out of sync).
  Future<Map<String, dynamic>> setTaskCompleted(
    int taskId, {
    required bool completed,
    int projectId = 0,
    Map<String, dynamic>? task,
  }) {
    if (completed) {
      return completeTask(taskId, projectId: projectId, task: task);
    }
    return reopenTask(taskId, projectId: projectId, task: task);
  }

  Future<Map<String, dynamic>> toggleTask(
    int taskId, {
    bool? markCompleted,
    int projectId = 0,
    Map<String, dynamic>? task,
  }) async {
    if (markCompleted != null) {
      return setTaskCompleted(
        taskId,
        completed: markCompleted,
        projectId: projectId,
        task: task,
      );
    }
    final done = task != null &&
        (task['completed'] == true ||
            (task['status'] ?? '').toString().toLowerCase() == 'completed');
    return setTaskCompleted(
      taskId,
      completed: !done,
      projectId: projectId,
      task: task,
    );
  }

  int? _projectIdFromTask(Map<String, dynamic>? task) {
    if (task == null) return null;
    final raw = task['project_id'] ?? task['projectId'] ?? task['project'];
    return int.tryParse('$raw');
  }

  Future<Map<String, dynamic>> _postTaskAction(String url, String label) async {
    try {
      final response = await http
          .post(Uri.parse(url), headers: _getHeaders())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        dynamic data;
        try {
          data = jsonDecode(response.body);
        } catch (_) {
          data = {'success': true};
        }
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'error': _parseApiErrorBody(response.body, response.statusCode),
      };
    } catch (e) {
      return {'success': false, 'error': '$label error: $e'};
    }
  }

  Future<Map<String, dynamic>> getTaskAttachments(int taskId) async {
    try {
      final response = await _authorizedGet(
        Uri.parse('${AppConfig.tasksUrl}$taskId/attachments/'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data is List ? data : <dynamic>[]};
      }
      return {'success': false, 'error': 'Failed to load attachments'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteTaskAttachment(int taskId, int attachmentId) async {
    try {
      final response = await _authorizedDelete(
        Uri.parse('${AppConfig.tasksUrl}$taskId/attachments/$attachmentId/'),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to delete attachment'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getTaskActivity(int projectId, int taskId, {int page = 1}) async {
    if (projectId <= 0) {
      return {'success': false, 'error': 'Project id required for activity log'};
    }
    try {
      final uri = Uri.parse(AppConfig.projectTaskActivityUrl(projectId, taskId)).replace(
        queryParameters: {'page': '$page', 'page_size': '30'},
      );
      final response = await _authorizedGet(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['results'] is List) {
          return {'success': true, 'data': decoded['results']};
        }
        if (decoded is List) {
          return {'success': true, 'data': decoded};
        }
        return {'success': true, 'data': <dynamic>[]};
      }
      return {'success': false, 'error': 'Failed to load activity'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> uploadTaskAttachment(
    int taskId,
    List<int> bytes,
    String filename,
  ) async {
    try {
      final uri = Uri.parse('${AppConfig.tasksUrl}$taskId/attachments/');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_authHeaderOnly());
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      var err = 'Upload failed';
      try {
        final d = jsonDecode(response.body);
        if (d is Map && d['error'] != null) err = d['error'].toString();
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getSubTaskAttachments(int taskId, int subtaskId) async {
    try {
      final url =
          '${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/attachments/';
      final response = await http
          .get(Uri.parse(url), headers: _getHeaders())
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data is List ? data : <dynamic>[]};
      }
      return {'success': false, 'error': 'Failed to load attachments'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> uploadSubTaskAttachment(
    int taskId,
    int subtaskId,
    List<int> bytes,
    String filename,
  ) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/attachments/',
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_authHeaderOnly());
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      var err = 'Upload failed';
      try {
        final d = jsonDecode(response.body);
        if (d is Map && d['error'] != null) err = d['error'].toString();
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getChatUsers() async {
    try {
      print('👥 Loading chat users...');
      print('🔗 URL: ${AppConfig.chatUsersUrl}');
      print('🔑 Token: ${_token != null && _token!.isNotEmpty ? "Present" : "Missing"}');
      
      final response = await http
          .get(
            Uri.parse(AppConfig.chatUsersUrl),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Chat users response: ${response.statusCode}');
      print('📝 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List
            ? data
            : (data is Map && data['users'] is List)
                ? data['users']
                : (data is Map && data['results'] is List)
                    ? data['results']
                    : <dynamic>[];
        print('✅ Successfully loaded ${list.length} users');
        return {'success': true, 'data': list};
      } else if (response.statusCode == 401) {
        return {'success': false, 'error': 'Unauthorized - please login again'};
      } else if (response.statusCode == 403) {
        return {'success': false, 'error': 'Access denied - check subscription'};
      }
      return {'success': false, 'error': 'Failed to load users (${response.statusCode})'};
    } catch (e) {
      print('❌ Chat users error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> getConversation(int userId) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.chatConversationUrl}$userId/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List
            ? data
            : (data is Map && data['messages'] is List)
                ? data['messages']
                : <dynamic>[];
        return {'success': true, 'data': list};
      }
      return {'success': false, 'error': 'Failed to load conversation'};
    } catch (e) {
      return {'success': false, 'error': 'Conversation error: $e'};
    }
  }

  Future<Map<String, dynamic>> sendMessage(int userId, String message) async {
    try {
      print('💬 Sending message to user $userId: $message');
      final response = await http
          .post(
            Uri.parse(AppConfig.chatSendUrl),
            headers: _getHeaders(),
            body: jsonEncode({
              'receiver_id': userId,
              'message': message,
            }),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Send message response: ${response.statusCode}');
      print('📝 Response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to send message: ${response.statusCode}'};
    } catch (e) {
      print('❌ Send message error: $e');
      return {'success': false, 'error': 'Send error: $e'};
    }
  }

  // ─── Mark Messages Read ───
  Future<Map<String, dynamic>> sendVoiceMessage(int userId, List<int> audioBytes, String filename) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(AppConfig.chatSendUrl));
      final headers = _getHeaders(); headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.fields['receiver_id'] = userId.toString();
      request.fields['message'] = '';
      request.files.add(http.MultipartFile.fromBytes('voice_message', audioBytes, filename: filename));
      var response = await request.send().timeout(Duration(seconds: 30));
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
      return {'success': false, 'error': 'Failed: ${response.statusCode}'};
    } catch (e) { return {'success': false, 'error': '$e'}; }
  }

  Future<Map<String, dynamic>> sendImageMessage(int userId, List<int> imageBytes, String filename, {String message = ''}) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(AppConfig.chatSendUrl));
      final headers = _getHeaders(); headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.fields['receiver_id'] = userId.toString();
      request.fields['message'] = message;
      request.files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: filename, contentType: MediaType('image', filename.endsWith('.png') ? 'png' : 'jpeg')));
      var response = await request.send().timeout(Duration(seconds: 30));
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
      return {'success': false, 'error': 'Failed: ${response.statusCode}'};
    } catch (e) { return {'success': false, 'error': '$e'}; }
  }

  Future<Map<String, dynamic>> sendFileMessage(int userId, List<int> fileBytes, String filename, {String message = ''}) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(AppConfig.chatSendUrl));
      final headers = _getHeaders(); headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.fields['receiver_id'] = userId.toString();
      request.fields['message'] = message;
      // Detect content type from filename extension
      final ext = filename.split('.').last.toLowerCase();
      final mimeTypes = {
        'pdf': 'application/pdf', 'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'txt': 'text/plain', 'csv': 'text/csv', 'json': 'application/json',
        'zip': 'application/zip', 'rar': 'application/x-rar-compressed',
        '7z': 'application/x-7z-compressed', 'gz': 'application/gzip',
        'mp4': 'video/mp4', 'mp3': 'audio/mpeg', 'wav': 'audio/wav',
        'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
        'gif': 'image/gif', 'webp': 'image/webp',
      };
      final mime = mimeTypes[ext] ?? 'application/octet-stream';
      final parts = mime.split('/');
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename,
        contentType: MediaType(parts[0], parts[1])));
      var response = await request.send().timeout(Duration(seconds: 60));
      final body = await response.stream.bytesToString();
      print('📎 File upload response: ${response.statusCode} - $body');
      if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
      return {'success': false, 'error': 'Failed: ${response.statusCode} - $body'};
    } catch (e) {
      print('❌ File send error: $e');
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> markMessagesRead(int senderId) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.chatMarkReadUrl),
            headers: _getHeaders(),
            body: jsonEncode({'sender_id': senderId}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to mark read'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Unread Count ───
  Future<Map<String, dynamic>> getUnreadCount() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.chatUnreadUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          final total = data['total_unread'] ?? data['unread_count'] ?? data['count'];
          if (total != null) {
            return {
              'success': true,
              'data': {'unread_count': total is int ? total : int.tryParse('$total') ?? 0},
            };
          }
        }
        return {'success': true, 'data': data};
      }
      return {'success': false, 'error': 'Failed'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Edit Message ───
  Future<Map<String, dynamic>> editMessage(int messageId, String newText) async {
    try {
      final response = await http
          .patch(
            Uri.parse('${AppConfig.chatMessageDetailUrl}$messageId/'),
            headers: _getHeaders(),
            body: jsonEncode({'message': newText}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to edit message'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Delete Message ───
  Future<Map<String, dynamic>> deleteMessage(int messageId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.chatMessageDetailUrl}$messageId/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to delete message'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Group Chat APIs ───
  Future<Map<String, dynamic>> getChatGroups() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.chatGroupsUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List
            ? data
            : (data is Map && data['groups'] is List)
                ? data['groups']
                : (data is Map && data['results'] is List)
                    ? data['results']
                    : <dynamic>[];
        return {'success': true, 'data': list};
      }
      return {'success': false, 'error': 'Failed to load groups'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> createGroup(String name, String description, List<int> memberIds) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.chatGroupsUrl),
            headers: _getHeaders(),
            body: jsonEncode({
              'name': name,
              'description': description,
              'member_ids': memberIds,
            }),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to create group'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getGroupMessages(int groupId) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/messages/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List
            ? data
            : (data is Map && data['messages'] is List)
                ? data['messages']
                : <dynamic>[];
        return {'success': true, 'data': list};
      }
      return {'success': false, 'error': 'Failed to load group messages'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> sendGroupMessage(int groupId, String message) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/messages/'),
            headers: _getHeaders(),
            body: jsonEncode({'message': message}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to send group message'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getGroupMembers(int groupId) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/members/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load members'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> addGroupMembers(int groupId, List<int> memberIds) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/members/'),
            headers: _getHeaders(),
            body: jsonEncode({'member_ids': memberIds}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to add members'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> removeGroupMember(int groupId, int memberId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/members/$memberId/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to remove member'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteGroup(int groupId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/'),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to delete group'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateGroup(int groupId, String name, String description) async {
    try {
      final response = await http
          .patch(
            Uri.parse('${AppConfig.chatGroupsUrl}$groupId/'),
            headers: _getHeaders(),
            body: jsonEncode({'name': name, 'description': description}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to update group'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Create Task ───
  Future<Map<String, dynamic>> createTask({
    required String name,
    String description = '',
    String priority = 'medium',
    String? dueDate,
    int? projectId,
    int? stageId,
    List<int>? assigneeIds,
    bool isAttachmentRequired = false,
    List<int>? attachmentBytes,
    String? attachmentName,
  }) async {
    try {
      if (attachmentBytes != null && attachmentName != null) {
        // Multipart upload
        var request = http.MultipartRequest('POST', Uri.parse(AppConfig.tasksUrl));
        final headers = _getHeaders(); headers.remove('Content-Type');
        request.headers.addAll(headers);
        request.fields['title'] = name;
        request.fields['desc'] = description;
        request.fields['priority'] = priority;
        request.fields['is_attachment_required'] = isAttachmentRequired.toString();
        if (dueDate != null) request.fields['due_date'] = dueDate;
        if (projectId != null) request.fields['project_id'] = projectId.toString();
        if (stageId != null) request.fields['stage_id'] = stageId.toString();
        if (assigneeIds != null && assigneeIds.isNotEmpty) {
          request.fields['assignee_ids'] = jsonEncode(assigneeIds);
        }
        request.files.add(http.MultipartFile.fromBytes('attachment', attachmentBytes, filename: attachmentName));
        var response = await request.send().timeout(Duration(seconds: 30));
        final body = await response.stream.bytesToString();
        if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
        return {'success': false, 'error': 'Failed: ${response.statusCode} - $body'};
      } else {
        final body = <String, dynamic>{
          'title': name,
          'desc': description,
          'priority': priority,
          'is_attachment_required': isAttachmentRequired,
        };
        if (dueDate != null) body['due_date'] = dueDate;
        if (projectId != null) body['project_id'] = projectId;
        if (stageId != null) body['stage_id'] = stageId;
        if (assigneeIds != null && assigneeIds.isNotEmpty) {
          body['assignee_ids'] = assigneeIds;
        }

        final response = await _authorizedPost(
          Uri.parse(AppConfig.tasksUrl),
          body: jsonEncode(body),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          return {'success': true, 'data': jsonDecode(response.body)};
        }
        return {'success': false, 'error': 'Failed to create task: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Update Task ───
  Map<String, dynamic> _taskPatchBody(Map<String, dynamic> data) {
    final body = Map<String, dynamic>.from(data);
    if (body.containsKey('name')) {
      body['title'] = body.remove('name');
    }
    if (body.containsKey('description')) {
      body['desc'] = body.remove('description');
    }
    if (body.containsKey('user')) {
      body['assignee_ids'] = [body.remove('user')];
    }
    if (body.containsKey('user_id')) {
      body['assignee_ids'] = [body.remove('user_id')];
    }
    if (body.containsKey('assignee_id')) {
      body['assignee_ids'] = [body.remove('assignee_id')];
    }
    return body;
  }

  Future<Map<String, dynamic>> updateTaskAssignees(
    int taskId,
    List<int> assigneeIds, {
    int projectId = 0,
    Map<String, dynamic>? task,
  }) {
    return updateTask(
      taskId,
      {'assignee_ids': assigneeIds},
      projectId: projectId,
      task: task,
    );
  }

  /// PATCH task — project-scoped when [projectId] or task.project is known (aims-webapps).
  Future<Map<String, dynamic>> updateTask(
    int taskId,
    Map<String, dynamic> data, {
    int projectId = 0,
    Map<String, dynamic>? task,
  }) async {
    final pid = projectId > 0 ? projectId : _projectIdFromTask(task);
    final scoped = pid != null && pid > 0;
    final url = scoped
        ? AppConfig.projectTaskUrl(pid, taskId)
        : '${AppConfig.tasksUrl}$taskId/';
    final body = scoped ? Map<String, dynamic>.from(data) : _taskPatchBody(data);

    try {
      final response = await _authorizedPatch(
        Uri.parse(url),
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return {'success': true, 'data': _normalizeTaskMap(decoded)};
        }
        return {'success': true, 'data': decoded};
      }
      return {
        'success': false,
        'error': _parseApiErrorBody(response.body, response.statusCode),
      };
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Delete Task ───
  Future<Map<String, dynamic>> deleteTask(int taskId) async {
    try {
      final response = await http
          .delete(Uri.parse('${AppConfig.tasksUrl}$taskId/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final err = body['error'] ?? body['detail'];
        if (err != null) {
          return {'success': false, 'error': err is String ? err : err.toString()};
        }
      } catch (_) {}
      return {'success': false, 'error': 'Failed to delete task (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── SubTask APIs ───
  Future<Map<String, dynamic>> getSubTasks(int taskId) async {
    try {
      final response = await _authorizedGet(
        Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/'),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['subtasks'] is List) {
          return {'success': true, 'data': decoded['subtasks']};
        }
        if (decoded is List) {
          return {'success': true, 'data': decoded};
        }
        return {'success': true, 'data': decoded};
      }
      return {'success': false, 'error': 'Failed to load subtasks'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> createSubTask(int taskId, {
    required String summary,
    String description = '',
    String priority = 'medium',
    String status = 'to_do',
    int? assigneeId,
    String? dueDate,
    bool isAttachmentRequired = false,
    List<int>? attachmentBytes,
    String? attachmentName,
  }) async {
    try {
      if (attachmentBytes != null && attachmentName != null) {
        var request = http.MultipartRequest('POST', Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/'));
        final headers = _getHeaders(); headers.remove('Content-Type');
        request.headers.addAll(headers);
        request.fields['summary'] = summary;
        request.fields['description'] = description;
        request.fields['priority'] = priority;
        request.fields['status'] = status;
        request.fields['is_attachment_required'] = isAttachmentRequired.toString();
        if (dueDate != null) request.fields['due_date'] = dueDate;
        if (assigneeId != null) request.fields['assignee_id'] = assigneeId.toString();
        request.files.add(http.MultipartFile.fromBytes('attachment', attachmentBytes, filename: attachmentName));
        var response = await request.send().timeout(Duration(seconds: 30));
        final body = await response.stream.bytesToString();
        if (response.statusCode == 200 || response.statusCode == 201) return {'success': true, 'data': jsonDecode(body)};
        return {'success': false, 'error': _parseApiErrorBody(body, response.statusCode)};
      } else {
        final body = <String, dynamic>{
          'summary': summary,
          'description': description,
          'priority': priority,
          'status': status,
          'is_attachment_required': isAttachmentRequired,
        };
        if (dueDate != null) body['due_date'] = dueDate;
        if (assigneeId != null) body['assignee_id'] = assigneeId;

        final response = await http
            .post(Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/'), headers: _getHeaders(), body: jsonEncode(body))
            .timeout(Duration(seconds: 10));
        if (response.statusCode == 200 || response.statusCode == 201) {
          return {'success': true, 'data': jsonDecode(response.body)};
        }
        return {'success': false, 'error': _parseApiErrorBody(response.body, response.statusCode)};
      }
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateSubTask(
    int taskId,
    int subtaskId,
    Map<String, dynamic> data, {
    int projectId = 0,
    Map<String, dynamic>? task,
  }) async {
    final pid = projectId > 0 ? projectId : _projectIdFromTask(task);
    final url = pid != null && pid > 0
        ? AppConfig.projectSubtaskUrl(pid, taskId, subtaskId)
        : '${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/';

    try {
      final response = await _authorizedPatch(
        Uri.parse(url),
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'error': _parseApiErrorBody(response.body, response.statusCode),
      };
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteSubTaskAttachment(
    int taskId,
    int subtaskId,
    int attachmentId,
  ) async {
    try {
      final response = await _authorizedDelete(
        Uri.parse(
          '${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/attachments/$attachmentId/',
        ),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to delete attachment'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteSubTask(int taskId, int subtaskId) async {
    try {
      final response = await http
          .delete(Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to delete subtask'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> toggleSubTask(int taskId, int subtaskId) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.tasksUrl}$taskId/subtasks/$subtaskId/toggle/'),
            headers: _getHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      var err = 'Failed to toggle subtask';
      try {
        final d = jsonDecode(response.body);
        if (d is Map && d['error'] != null) err = d['error'].toString();
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Notification APIs ───
  Future<Map<String, dynamic>> getNotifications() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.notificationsUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List
            ? data
            : (data is Map && data['results'] is List)
                ? data['results']
                : (data is Map && data['notifications'] is List)
                    ? data['notifications']
                    : <dynamic>[];
        return {'success': true, 'data': list};
      }
      return {'success': false, 'error': 'Failed to load notifications'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getNotificationUnreadCount() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.notificationsUnreadUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> markNotificationRead(int notificationId) async {
    try {
      final response = await _authorizedPost(
        Uri.parse('${AppConfig.notificationsUrl}$notificationId/'),
        body: jsonEncode({'action': 'mark_read'}),
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Failed to mark notification read'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> markAllNotificationsRead() async {
    try {
      final response = await _authorizedPost(
        Uri.parse(AppConfig.notificationsMarkAllReadUrl),
        body: '{}',
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': _safeJsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to mark all as read (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> clearAllNotifications() async {
    try {
      final response = await http
          .delete(Uri.parse(AppConfig.notificationsClearUrl), headers: _getHeaders())
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401 && await refreshAccessToken()) {
        return clearAllNotifications();
      }
      if (response.statusCode == 200) {
        return {'success': true, 'data': _safeJsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to clear notifications (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<bool> refreshAccessToken() async {
    try {
      final refresh = await UserDataService.getRefreshToken();
      if (refresh.isEmpty) return false;
      final body = jsonEncode({'refresh': refresh});
      final headers = {'Content-Type': 'application/json'};
      var response = await http
          .post(
            Uri.parse(AppConfig.authRefreshUrl),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        response = await http
            .post(
              Uri.parse(AppConfig.authTokenRefreshUrl),
              headers: headers,
              body: body,
            )
            .timeout(const Duration(seconds: 15));
      }
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final access = data['access']?.toString();
      if (access == null || access.isEmpty) return false;
      _token = access;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', access);
      if (data['refresh'] != null) {
        await prefs.setString('refresh_token', data['refresh'].toString());
      }
      print('🔑 Access token refreshed');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Company APIs ───
  Future<Map<String, dynamic>> getCompanyDashboard() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.companyDashboardUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load company info'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getSubscriptionUsage() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.subscriptionUsageUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load usage'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Project APIs ───
  Future<Map<String, dynamic>> getProjectFiltersMeta() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.projectsMetaUrl), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = _decodeJsonBody(response.body, context: 'GET /api/projects/meta/');
        if (decoded is Map<String, dynamic>) {
          return {'success': true, 'data': decoded};
        }
        return {'success': false, 'error': 'Invalid projects meta response'};
      }
      return {'success': false, 'error': 'Failed to load filter options'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  /// Query params mirror web monitor: archived, customer_id, user_id, project_department_id, status, priority, search, sort.
  Future<Map<String, dynamic>> getProjects({
    bool archived = false,
    int? customerId,
    int? userId,
    int? projectDepartmentId,
    String? status,
    String? priority,
    String? search,
    String sort = 'newest',
  }) async {
    try {
      final params = <String, String>{'sort': sort};
      if (archived) params['archived'] = '1';
      if (customerId != null) params['customer_id'] = '$customerId';
      if (userId != null) params['user_id'] = '$userId';
      if (projectDepartmentId != null) {
        params['project_department_id'] = '$projectDepartmentId';
      }
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (priority != null && priority.isNotEmpty) params['priority'] = priority;
      if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();

      final uri = Uri.parse(AppConfig.projectsUrl).replace(queryParameters: params);
      final response = await _authorizedGet(uri);
      if (response.statusCode == 200) {
        dynamic decoded;
        try {
          decoded = _decodeJsonBody(response.body, context: 'GET /api/projects/');
        } on FormatException catch (e) {
          final fallback = await _fetchProjectsFallback();
          if (fallback != null) {
            return {'success': true, 'data': fallback};
          }
          return {'success': false, 'error': e.message};
        }

        final list = _extractJsonList(
          decoded,
          keys: const ['results', 'projects', 'data'],
        );
        if (list.isNotEmpty || decoded is List) {
          return {'success': true, 'data': _normalizeProjectItems(list)};
        }
        if (decoded is Map<String, dynamic> &&
            (decoded.containsKey('customers') || decoded.containsKey('employees'))) {
          return {
            'success': false,
            'error': 'Projects API returned filter metadata — deploy /api/projects/ list endpoint',
          };
        }

        final fallback = await _fetchProjectsFallback();
        if (fallback != null && fallback.isNotEmpty) {
          return {'success': true, 'data': fallback};
        }

        return {'success': true, 'data': _normalizeProjectItems(list)};
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return {
          'success': false,
          'error': _parseApiErrorBody(response.body, response.statusCode),
        };
      }
      return {'success': false, 'error': 'Failed to load projects (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> archiveProject(int projectId) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.projectArchiveUrl(projectId)),
            headers: _getHeaders(),
            body: jsonEncode({}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> restoreProject(int projectId) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.projectRestoreUrl(projectId)),
            headers: _getHeaders(),
            body: jsonEncode({}),
          )
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getProjectDetail(int projectId) async {
    try {
      final response = await _authorizedGet(
        Uri.parse('${AppConfig.projectsUrl}$projectId/'),
        timeout: const Duration(seconds: 15),
      );
      if (response.statusCode == 200) {
        try {
          final decoded = _decodeJsonBody(
            response.body,
            context: 'GET /api/projects/$projectId/',
          );
          if (decoded is Map<String, dynamic>) {
            return {
              'success': true,
              'data': _normalizeProjectDetailMap(decoded),
            };
          }
          if (decoded is Map) {
            return {
              'success': true,
              'data': _normalizeProjectDetailMap(Map<String, dynamic>.from(decoded)),
            };
          }
          return {'success': true, 'data': decoded};
        } on FormatException catch (e) {
          return {'success': false, 'error': e.message};
        }
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return {
          'success': false,
          'error': _parseApiErrorBody(response.body, response.statusCode),
        };
      }
      return {
        'success': false,
        'error': 'Failed to load project (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Project CRUD ───
  Future<Map<String, dynamic>> createProject({
    required String name,
    required int customerId,
    String description = '',
    String priority = 'medium',
    List<Map<String, dynamic>>? stages,
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'customer_id': customerId,
        'description': description,
        'priority': priority,
      };
      if (stages != null) body['stages'] = stages;
      final response = await http
          .post(
            Uri.parse('${AppConfig.projectsUrl}create/'),
            headers: _getHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'error': _parseApiErrorBody(response.body, response.statusCode),
      };
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateProject(int projectId, Map<String, dynamic> data) async {
    try {
      final response = await http
          .patch(Uri.parse('${AppConfig.projectsUrl}$projectId/update/'), headers: _getHeaders(), body: jsonEncode(data))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to update project'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteProject(int projectId) async {
    try {
      final response = await http
          .delete(Uri.parse('${AppConfig.projectsUrl}$projectId/update/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to delete project'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Stage CRUD ───
  Future<Map<String, dynamic>> createStage(int projectId, {required String name, String color = '#3B82F6'}) async {
    try {
      final response = await http
          .post(Uri.parse('${AppConfig.projectsUrl}$projectId/stages/'), headers: _getHeaders(), body: jsonEncode({'name': name, 'color': color}))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to create stage'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateStage(int projectId, int stageId, Map<String, dynamic> data) async {
    try {
      final response = await http
          .patch(Uri.parse('${AppConfig.projectsUrl}$projectId/stages/$stageId/'), headers: _getHeaders(), body: jsonEncode(data))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to update stage'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteStage(int projectId, int stageId) async {
    try {
      final response = await http
          .delete(Uri.parse('${AppConfig.projectsUrl}$projectId/stages/$stageId/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to delete stage'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> reorderStages(int projectId, List<int> stageIds) async {
    try {
      final stages = <Map<String, int>>[];
      for (var i = 0; i < stageIds.length; i++) {
        stages.add({'id': stageIds[i], 'order': i});
      }
      final response = await http
          .post(
            Uri.parse('${AppConfig.projectsUrl}$projectId/stages/reorder/'),
            headers: _getHeaders(),
            body: jsonEncode({'stages': stages}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Failed to reorder stages'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> moveTask(int taskId, int stageId) async {
    try {
      final response = await _authorizedPost(
        Uri.parse('${AppConfig.tasksUrl}$taskId/move/'),
        body: jsonEncode({'stage_id': stageId}),
      );
      if (response.statusCode == 200) return {'success': true};
      var err = 'Failed to move task';
      try {
        final d = jsonDecode(response.body);
        if (d is Map && d['error'] != null) err = d['error'].toString();
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Access Check (verify token is still valid) ───
  Future<Map<String, dynamic>> accessCheck() async {
    final urls = [AppConfig.authAccessCheckUrl, AppConfig.accessCheckLegacyUrl];
    for (final url in urls) {
      try {
        final response = await _authorizedGet(
          Uri.parse(url),
          timeout: const Duration(seconds: 10),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map && data['employee'] != null) {
            await UserDataService.saveEmployeeId(data['employee']);
          }
          return {'success': true, 'data': data};
        }
        if (response.statusCode == 403) {
          return {
            'success': false,
            'data': jsonDecode(response.body),
            'error': 'Access denied',
          };
        }
      } catch (e) {
        if (url == urls.last) {
          return {'success': false, 'error': '$e'};
        }
      }
    }
    return {'success': false, 'error': 'Access check failed'};
  }

  /// Accept current data & monitoring notice (JWT). Sets server-side accepted version + optional screenshot consent.
  Future<Map<String, dynamic>> acceptPrivacyNotice({bool screenshotMonitoringConsent = true}) async {
    final body = jsonEncode({'screenshot_monitoring_consent': screenshotMonitoringConsent});
    final urls = [
      AppConfig.privacyNoticeAcceptUrl,
      AppConfig.privacyNoticeAcceptLegacyUrl,
    ];

    for (final url in urls) {
      try {
        final response = await _authorizedPost(Uri.parse(url), body: body);
        final rawBody = response.body;
        if (_looksLikeHtml(rawBody)) {
          continue;
        }
        dynamic raw;
        try {
          raw = rawBody.isNotEmpty ? jsonDecode(rawBody) : null;
        } catch (_) {
          continue;
        }
        if (response.statusCode == 200 && raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          if (map['success'] == true || map.containsKey('data_privacy_notice_accepted_version')) {
            return {'success': true, 'data': map};
          }
        }
        if (raw is Map) {
          final err = raw['error'] ?? raw['detail'];
          if (err != null) {
            return {'success': false, 'error': err.toString()};
          }
        }
      } catch (_) {
        continue;
      }
    }

    // Production fallback until dedicated privacy route is deployed.
    try {
      final profileBody = jsonEncode({
        'accept_data_privacy_notice': true,
        'screenshot_monitoring_consent': screenshotMonitoringConsent,
      });
      final response = await _authorizedPatch(Uri.parse(AppConfig.profileUrl), body: profileBody);
      final rawBody = response.body;
      if (!_looksLikeHtml(rawBody) && response.statusCode == 200) {
        final raw = rawBody.isNotEmpty ? jsonDecode(rawBody) : null;
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final emp = map['employee'];
          if (emp is Map) {
            final e = Map<String, dynamic>.from(emp);
            return {
              'success': true,
              'data': {
                'data_privacy_notice_accepted_version': e['data_privacy_notice_accepted_version'],
                'screenshot_monitoring_consent': e['screenshot_monitoring_consent'],
                'data_privacy_notice_version': AppConfig.dataPrivacyNoticeVersion,
              },
            };
          }
        }
      }
    } catch (_) {}

    return {
      'success': false,
      'error': 'Could not save notice — server may need update. Contact admin or try again after login.',
    };
  }

  Future<Map<String, dynamic>> getCurrentAttendance({bool allowCache = true}) async {
    try {
      await ensureAuth();
      final response = await _authorizedGet(Uri.parse(AppConfig.attendanceCurrentUrl));
      if (response.statusCode != 200) {
        if (allowCache) {
          final cached = await AttendanceCache.load();
          if (cached != null) {
            return {'success': true, 'data': cached, 'from_cache': true};
          }
        }
        return {'success': false, 'error': 'Failed to load attendance (${response.statusCode})'};
      }
      final decoded = _safeJsonDecode(response.body);
      if (decoded is! Map) {
        return {'success': false, 'error': 'Unexpected attendance response format'};
      }
      final data = _normalizeAttendancePayload(decoded);
      await AttendanceCache.save(data);
      return {'success': true, 'data': data};
    } catch (e) {
      if (allowCache) {
        final cached = await AttendanceCache.load();
        if (cached != null) {
          return {'success': true, 'data': cached, 'from_cache': true};
        }
      }
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> _parseBreakPost(http.Response response, {required String failLabel}) async {
    if (response.statusCode == 200 || response.statusCode == 201) {
      try {
        return {'success': true, 'data': _safeJsonDecode(response.body)};
      } catch (_) {
        return {'success': true, 'data': <String, dynamic>{}};
      }
    }
    var err = failLabel;
    try {
      final d = _safeJsonDecode(response.body);
      if (d is Map) {
        err = d['error']?.toString() ?? d['message']?.toString() ?? d['detail']?.toString() ?? failLabel;
      }
    } catch (_) {}
    return {'success': false, 'error': err};
  }

  Future<Map<String, dynamic>> getAttendanceList() async {
    try {
      final response = await _authorizedGet(Uri.parse(AppConfig.attendanceListUrl));
      if (response.statusCode == 200) {
        final raw = jsonDecode(response.body);
        final list = raw is List ? List<dynamic>.from(raw) : <dynamic>[];
        return {'success': true, 'data': list};
      }
      return {'success': false, 'error': 'Failed to load attendance history'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getClosingReportPending() async {
    try {
      final response = await _authorizedGet(Uri.parse(AppConfig.closingReportsPendingUrl));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to check report status'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getClosingReports() async {
    try {
      final response = await _authorizedGet(Uri.parse(AppConfig.closingReportsUrl));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return {
          'success': true,
          'data': decoded is List ? decoded : _extractJsonList(decoded),
        };
      }
      return {'success': false, 'error': 'Failed to load reports'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> submitClosingReport({
    required String whatIDid,
    required String whatIWillDo,
    String blockers = '',
    List<int> dependencyEmployeeIds = const [],
  }) async {
    try {
      final body = jsonEncode({
        'what_i_did': whatIDid,
        'what_i_will_do': whatIWillDo,
        'blockers': blockers,
        'dependency_employee_ids': dependencyEmployeeIds,
      });
      final response = await _authorizedPost(
        Uri.parse(AppConfig.closingReportsUrl),
        body: body,
      );
      final raw = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 201 && raw is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(raw)};
      }
      if (raw is Map) {
        return {
          'success': false,
          'error': raw['detail'] ?? raw['error'] ?? 'Submit failed (${response.statusCode})',
        };
      }
      return {'success': false, 'error': 'Submit failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getCompanyEmployees() async {
    try {
      final response = await _authorizedGet(Uri.parse(AppConfig.companyEmployeesUrl));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return {
          'success': true,
          'data': decoded is List ? decoded : _extractJsonList(decoded, keys: const ['results', 'employees', 'data']),
        };
      }
      return {'success': false, 'error': 'Failed to load employees'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> uploadScreenshot(
    List<int> imageBytes, {
    bool isIdle = false,
    int idleDuration = 0,
    String? lastActivityAt,
  }) async {
    try {
      await ensureAuth();
      print('📤 Uploading screenshot (${imageBytes.length} bytes)...');
      print('   Activity Status: ${isIdle ? "IDLE" : "ACTIVE"}');
      if (isIdle) {
        print('   Idle Duration: ${idleDuration}m');
      }

      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final time = '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final relativePath = '$date/screen1/$time.png';

      Future<http.StreamedResponse> sendUpload() async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse(AppConfig.screenshotUploadUrl),
        );
        final headers = _getHeaders();
        headers.remove('Content-Type');
        request.headers.addAll(headers);

        final isJpeg = imageBytes.length > 2 && imageBytes[0] == 0xFF && imageBytes[1] == 0xD8;
        final ext = isJpeg ? 'jpg' : 'png';
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            imageBytes,
            filename: '$time.$ext',
            contentType: MediaType('image', isJpeg ? 'jpeg' : 'png'),
          ),
        );

        request.fields['relative_path'] = relativePath;
        request.fields['is_idle'] = isIdle.toString();
        request.fields['idle_duration'] = idleDuration.toString();
        if (lastActivityAt != null) {
          request.fields['last_activity_at'] = lastActivityAt;
        }

        return request.send().timeout(const Duration(seconds: 60));
      }

      print('📋 Upload URL: ${AppConfig.screenshotUploadUrl}');
      print('📋 Relative path: $relativePath');

      var response = await sendUpload();
      if (response.statusCode == 401 && await refreshAccessToken()) {
        response = await sendUpload();
      }
      final responseBody = await response.stream.bytesToString();

      print('📊 Upload response: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': responseBody};
      }
      String errorMsg = 'Upload failed: ${response.statusCode}';
      try {
        final json = jsonDecode(responseBody);
        errorMsg = json['error'] ?? json['errors']?.toString() ?? errorMsg;
      } catch (_) {}
      return {'success': false, 'error': errorMsg};
    } catch (e) {
      print('❌ Upload error: $e');
      return {'success': false, 'error': 'Upload error: $e'};
    }
  }

  Future<Map<String, dynamic>> updateActivityStatus(bool isActive) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/attendance/activity/'),
            headers: _getHeaders(),
            body: jsonEncode({'is_active': isActive}),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Activity update failed: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': 'Activity error: $e'};
    }
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      print('👤 Getting user profile...');
      final response = await http
          .get(
            Uri.parse(AppConfig.profileUrl),
            headers: _getHeaders(),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Profile response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load profile: ${response.statusCode}'};
    } catch (e) {
      print('❌ Profile error: $e');
      return {'success': false, 'error': 'Profile error: $e'};
    }
  }

  Future<Map<String, dynamic>> patchUserProfile(Map<String, dynamic> body) async {
    try {
      final response = await http
          .patch(
            Uri.parse(AppConfig.profileUrl),
            headers: _getHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      String err = 'Update failed (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          err = '${decoded['error']}';
        } else if (decoded is Map && decoded['detail'] != null) {
          err = '${decoded['detail']}';
        }
      } catch (_) {
        if (response.body.isNotEmpty) err = response.body;
      }
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateUserProfile({
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    try {
      print('✏️ Updating user profile...');
      final response = await http
          .put(
            Uri.parse(AppConfig.profileUrl),
            headers: _getHeaders(),
            body: jsonEncode({
              'email': email,
              'first_name': firstName ?? '',
              'last_name': lastName ?? '',
            }),
          )
          .timeout(Duration(seconds: 10));

      print('📊 Update profile response: ${response.statusCode}');
      print('📝 Response: ${response.body}');

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to update profile: ${response.statusCode}'};
    } catch (e) {
      print('❌ Update profile error: $e');
      return {'success': false, 'error': 'Update error: $e'};
    }
  }

  Future<Map<String, dynamic>> uploadProfilePhoto(List<int> imageBytes) async {
    try {
      print('📤 Uploading profile photo...');
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.uploadPhotoUrl),
      );

      request.headers.addAll(_authHeaderOnly());
      
      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'profile_photo',
          imageBytes,
          filename: 'profile.jpg',
        ),
      );

      var response = await request.send().timeout(Duration(seconds: 30));
      
      print('📊 Upload photo response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        print('✅ Profile photo uploaded: $responseBody');
        return {'success': true, 'data': jsonDecode(responseBody)};
      } else {
        final responseBody = await response.stream.bytesToString();
        print('❌ Upload failed: ${response.statusCode} - $responseBody');
        return {'success': false, 'error': 'Upload failed: ${response.statusCode}'};
      }
    } catch (e) {
      print('❌ Upload photo error: $e');
      return {'success': false, 'error': 'Upload error: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Peer-to-Peer File Transfer APIs
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> p2pGetIceServers() async {
    try {
      final response = await _authorizedGet(Uri.parse(AppConfig.p2pIceServersUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data is Map ? data : {}};
      }
      return {'success': false, 'error': 'Failed to load ICE servers'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> p2pCreateSession({String fileName = '', int fileSize = 0, int? receiverId}) async {
    try {
      final body = <String, dynamic>{
        'file_name': fileName,
        'file_size': fileSize,
      };
      if (receiverId != null) body['receiver_id'] = receiverId;

      final response = await http
          .post(Uri.parse(AppConfig.p2pCreateSessionUrl), headers: _getHeaders(), body: jsonEncode(body))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] != null) {
          return {'success': false, 'error': body['error'].toString()};
        }
      } catch (_) {}
      return {'success': false, 'error': 'Failed to create session (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> p2pJoinSession(String sessionId) async {
    try {
      final response = await http
          .post(Uri.parse(AppConfig.p2pJoinSessionUrl), headers: _getHeaders(), body: jsonEncode({'session_id': sessionId}))
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      final body = jsonDecode(response.body);
      return {'success': false, 'error': body['error'] ?? 'Failed to join'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> p2pGetSession(String sessionId) async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.p2pSessionDetailUrl}$sessionId/'), headers: _getHeaders())
          .timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Session not found'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getBreakStatus() async {
    try {
      await ensureAuth();
      final response = await _authorizedGet(Uri.parse(AppConfig.breaksStatusUrl));
      if (response.statusCode == 200) {
        return {'success': true, 'data': _safeJsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load break status (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getMyAttendanceReport({String? date}) async {
    try {
      await ensureAuth();
      var url = AppConfig.attendanceMyReportUrl;
      if (date != null && date.isNotEmpty) url = '$url?date=$date';
      final response = await _authorizedGet(Uri.parse(url));
      if (response.statusCode != 200) {
        return {'success': false, 'error': 'Failed to load attendance report (${response.statusCode})'};
      }
      final decoded = _safeJsonDecode(response.body);
      if (decoded is! Map) {
        return {'success': false, 'error': 'Unexpected report response format'};
      }
      return {'success': true, 'data': Map<String, dynamic>.from(decoded)};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> startBreak({DateTime? expectedBack}) async {
    try {
      await ensureAuth();
      final body = expectedBack != null
          ? jsonEncode({'expected_back': expectedBack.toUtc().toIso8601String()})
          : '{}';
      final response = await _authorizedPost(
        Uri.parse(AppConfig.breaksStartUrl),
        body: body,
      );
      return _parseBreakPost(response, failLabel: 'Could not start break');
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> endBreak() async {
    try {
      await ensureAuth();
      final response = await _authorizedPost(Uri.parse(AppConfig.breaksBackUrl), body: '{}');
      return _parseBreakPost(response, failLabel: 'Could not end break');
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getMyBreaks({String? date}) async {
    try {
      var url = AppConfig.breaksMyBreaksUrl;
      if (date != null && date.isNotEmpty) url = '$url?date=$date';
      final response = await _authorizedGet(Uri.parse(url));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load breaks'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ─── Project vault APIs ───

  Future<Map<String, dynamic>> getVaultCategories(int projectId) async {
    try {
      final response = await _authorizedGet(Uri.parse(AppConfig.vaultCategoriesUrl(projectId)));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return {
          'success': true,
          'data': decoded is List ? decoded : _extractJsonList(decoded),
        };
      }
      return {'success': false, 'error': 'Failed to load vault categories (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateVaultCategory(
    int projectId,
    int categoryId, {
    String? name,
    String? description,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (description != null) body['description'] = description;
      final response = await _authorizedPatch(
        Uri.parse(AppConfig.vaultCategoryUrl(projectId, categoryId)),
        body: jsonEncode(body),
      );
      final raw = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200 && raw is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(raw)};
      }
      if (raw is Map) {
        return {'success': false, 'error': raw['name'] ?? raw['detail'] ?? raw['error'] ?? 'Update failed'};
      }
      return {'success': false, 'error': 'Update category failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteVaultCategory(int projectId, int categoryId) async {
    try {
      final response = await _authorizedDelete(
        Uri.parse(AppConfig.vaultCategoryUrl(projectId, categoryId)),
      );
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Delete category failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> createVaultCategory(
    int projectId, {
    required String name,
    String description = '',
  }) async {
    try {
      final response = await _authorizedPost(
        Uri.parse(AppConfig.vaultCategoriesUrl(projectId)),
        body: jsonEncode({'name': name, 'description': description}),
      );
      final raw = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if ((response.statusCode == 201 || response.statusCode == 200) && raw is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(raw)};
      }
      if (raw is Map) {
        return {'success': false, 'error': raw['name'] ?? raw['detail'] ?? raw['error'] ?? 'Create failed'};
      }
      return {'success': false, 'error': 'Create category failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getVaultEntries(
    int projectId, {
    int? categoryId,
    String? query,
  }) async {
    try {
      final q = <String, String>{};
      if (categoryId != null) q['category_id'] = '$categoryId';
      if (query != null && query.trim().isNotEmpty) q['q'] = query.trim();
      final uri = Uri.parse(AppConfig.vaultEntriesUrl(projectId)).replace(queryParameters: q.isEmpty ? null : q);
      final response = await _authorizedGet(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return {
          'success': true,
          'data': decoded is List ? decoded : _extractJsonList(decoded),
        };
      }
      return {'success': false, 'error': 'Failed to load vault entries (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> createVaultEntry(
    int projectId, {
    required int categoryId,
    required String name,
    String url = '',
    String username = '',
    String password = '',
    String notes = '',
    bool isFavorite = false,
  }) async {
    try {
      final response = await _authorizedPost(
        Uri.parse(AppConfig.vaultEntriesUrl(projectId)),
        body: jsonEncode({
          'category': categoryId,
          'name': name,
          'url': url,
          'username': username,
          if (password.isNotEmpty) 'password': password,
          'notes': notes,
          'is_favorite': isFavorite,
        }),
      );
      final raw = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if ((response.statusCode == 201 || response.statusCode == 200) && raw is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(raw)};
      }
      if (raw is Map) {
        return {'success': false, 'error': raw['detail'] ?? raw['error'] ?? 'Create failed'};
      }
      return {'success': false, 'error': 'Create entry failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateVaultEntry(
    int projectId,
    int entryId, {
    int? categoryId,
    String? name,
    String? url,
    String? username,
    String? password,
    String? notes,
    bool? isFavorite,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (categoryId != null) body['category'] = categoryId;
      if (name != null) body['name'] = name;
      if (url != null) body['url'] = url;
      if (username != null) body['username'] = username;
      if (password != null) body['password'] = password;
      if (notes != null) body['notes'] = notes;
      if (isFavorite != null) body['is_favorite'] = isFavorite;
      final response = await _authorizedPatch(
        Uri.parse(AppConfig.vaultEntryUrl(projectId, entryId)),
        body: jsonEncode(body),
      );
      final raw = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200 && raw is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(raw)};
      }
      if (raw is Map) {
        return {'success': false, 'error': raw['detail'] ?? raw['error'] ?? 'Update failed'};
      }
      return {'success': false, 'error': 'Update failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> deleteVaultEntry(int projectId, int entryId) async {
    try {
      final response = await _authorizedDelete(Uri.parse(AppConfig.vaultEntryUrl(projectId, entryId)));
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Delete failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> revealVaultEntry(int projectId, int entryId) async {
    try {
      final response = await _authorizedPost(
        Uri.parse(AppConfig.vaultEntryRevealUrl(projectId, entryId)),
        body: '{}',
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Reveal failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> copyVaultField(int projectId, int entryId, String field) async {
    try {
      final response = await _authorizedPost(
        Uri.parse(AppConfig.vaultEntryCopyFieldUrl(projectId, entryId)),
        body: jsonEncode({'field': field}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Copy failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> hideVaultPassword(int projectId, int entryId) async {
    try {
      final response = await _authorizedPost(
        Uri.parse(AppConfig.vaultEntryHidePasswordUrl(projectId, entryId)),
        body: '{}',
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Hide failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> uploadVaultAttachment(
    int projectId,
    int entryId,
    List<int> bytes,
    String filename, {
    String? title,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.vaultEntryAttachmentUrl(projectId, entryId)),
      );
      request.headers.addAll(_authHeaderOnly());
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      if (title != null && title.trim().isNotEmpty) {
        request.fields['title'] = title.trim();
      }
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      var err = 'Upload failed';
      try {
        final d = jsonDecode(response.body);
        if (d is Map) err = d['detail']?.toString() ?? d['error']?.toString() ?? err;
      } catch (_) {}
      return {'success': false, 'error': err};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getVaultShares(int projectId, int entryId) async {
    try {
      final response = await _authorizedGet(
        Uri.parse(AppConfig.vaultEntrySharesUrl(projectId, entryId)),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return {
          'success': true,
          'data': decoded is List ? decoded : _extractJsonList(decoded),
        };
      }
      return {'success': false, 'error': 'Failed to load shares (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> shareVaultEntry(
    int projectId,
    int entryId, {
    required List<int> userIds,
    String permission = 'view',
    String? expiresAt,
  }) async {
    try {
      final body = <String, dynamic>{
        'user_ids': userIds,
        'permission': permission,
      };
      if (expiresAt != null) body['expires_at'] = expiresAt;
      final response = await _authorizedPost(
        Uri.parse(AppConfig.vaultEntryShareUrl(projectId, entryId)),
        body: jsonEncode(body),
      );
      final raw = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if ((response.statusCode == 201 || response.statusCode == 200) && raw is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(raw)};
      }
      if (raw is Map) {
        return {'success': false, 'error': raw['user_ids'] ?? raw['detail'] ?? raw['error'] ?? 'Share failed'};
      }
      return {'success': false, 'error': 'Share failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateVaultShare(
    int projectId,
    int entryId,
    int shareId, {
    String? permission,
    String? expiresAt,
    bool? isActive,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (permission != null) body['permission'] = permission;
      if (expiresAt != null) body['expires_at'] = expiresAt;
      if (isActive != null) body['is_active'] = isActive;
      final response = await _authorizedPatch(
        Uri.parse(AppConfig.vaultShareDetailUrl(projectId, entryId, shareId)),
        body: jsonEncode(body),
      );
      final raw = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200 && raw is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(raw)};
      }
      if (raw is Map) {
        return {'success': false, 'error': raw['detail'] ?? raw['error'] ?? 'Update failed'};
      }
      return {'success': false, 'error': 'Update share failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> removeVaultShare(int projectId, int entryId, int shareId) async {
    try {
      final response = await _authorizedDelete(
        Uri.parse(AppConfig.vaultShareDetailUrl(projectId, entryId, shareId)),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        final raw = response.body.isNotEmpty ? jsonDecode(response.body) : null;
        return {'success': true, 'data': raw is Map ? Map<String, dynamic>.from(raw) : null};
      }
      return {'success': false, 'error': 'Remove share failed (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getVaultActivity(int projectId, {int page = 1}) async {
    try {
      final uri = Uri.parse(AppConfig.vaultActivityUrl(projectId)).replace(
        queryParameters: {'page': '$page', 'page_size': '30'},
      );
      final response = await _authorizedGet(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['results'] is List) {
          return {'success': true, 'data': decoded['results'], 'next': decoded['next']};
        }
        if (decoded is List) {
          return {'success': true, 'data': decoded};
        }
        return {'success': true, 'data': <dynamic>[]};
      }
      return {'success': false, 'error': 'Failed to load vault activity'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getVaultEntryActivity(
    int projectId,
    int entryId, {
    int page = 1,
  }) async {
    try {
      final uri = Uri.parse(AppConfig.vaultEntryActivityUrl(projectId, entryId)).replace(
        queryParameters: {'page': '$page', 'page_size': '30'},
      );
      final response = await _authorizedGet(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['results'] is List) {
          return {'success': true, 'data': decoded['results'], 'next': decoded['next']};
        }
        if (decoded is List) {
          return {'success': true, 'data': decoded};
        }
        return {'success': true, 'data': <dynamic>[]};
      }
      return {'success': false, 'error': 'Failed to load entry activity'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getVaultContextCustomers() async {
    try {
      final response = await _authorizedGet(Uri.parse(AppConfig.vaultContextCustomersUrl));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return {
          'success': true,
          'data': decoded is List ? decoded : _extractJsonList(decoded),
        };
      }
      return {'success': false, 'error': 'Failed to load customers (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getVaultContextCustomerProjects(int customerId) async {
    try {
      final response = await _authorizedGet(
        Uri.parse(AppConfig.vaultContextCustomerProjectsUrl(customerId)),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          return {'success': true, 'data': Map<String, dynamic>.from(decoded)};
        }
        return {'success': false, 'error': 'Invalid response'};
      }
      return {'success': false, 'error': 'Failed to load projects (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }
}

