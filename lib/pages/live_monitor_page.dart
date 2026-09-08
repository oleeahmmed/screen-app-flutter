import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../utils/monitor_media_url.dart';
import '../widgets/monitor_ui.dart';

class LiveMonitorPage extends StatefulWidget {
  final ApiService apiService;

  const LiveMonitorPage({super.key, required this.apiService});

  @override
  State<LiveMonitorPage> createState() => _LiveMonitorPageState();
}

class _LiveMonitorPageState extends State<LiveMonitorPage> {
  static const _pageBg = Color(0xFF0B141A);

  bool _loading = true;
  String? _error;
  bool _allowed = false;
  bool _checkingAccess = true;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _projects = [];
  String _statusFilter = 'all';
  String _search = '';
  int? _projectId;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final allowed = await UserDataService.isCompanyAdmin();
    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _checkingAccess = false;
    });
    if (!allowed) return;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _normalizeEmployee(Map<String, dynamic> e) {
    final screens = (e['screens'] as List? ?? [])
        .whereType<Map>()
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
    final screenshotRaw = e['screenshot_url'] ??
        e['latest_screenshot'] ??
        e['screenshotUrl'] ??
        e['latestScreenshot'];
    return {
      'id': e['user_id'] ?? e['id'],
      'employee_id': e['id'],
      'name': e['name']?.toString() ?? '',
      'username': e['username']?.toString() ?? '',
      'designation': e['designation']?.toString() ?? e['role']?.toString() ?? '',
      'department': e['project_department_name']?.toString() ?? e['department']?.toString() ?? '',
      'status': e['status']?.toString() ?? 'offline',
      'last_seen': e['lastSeen']?.toString() ?? e['last_seen']?.toString() ?? '',
      'screenshot': monitorMediaUrl(screenshotRaw),
      'screen_count': e['screen_count'] ?? screens.length,
      'screens': screens.map((s) {
        return {
          'id': s['slot']?.toString() ?? '${s['index'] ?? 1}',
          'index': s['index'] ?? 1,
          'slot': s['slot'],
          'label': 'Screen ${s['index'] ?? 1}',
          'url': monitorMediaUrl(s['url']),
        };
      }).toList(),
      'project_ids': e['project_ids'] ?? [],
    };
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await widget.apiService.getLiveMonitor(
      projectId: _projectId,
      includeProjects: _projects.isEmpty,
    );
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _loading = false;
        _error = r['error']?.toString() ?? 'Failed to load';
      });
      return;
    }
    final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
    final emps = (data['employees'] as List? ?? [])
        .whereType<Map>()
        .map((e) => _normalizeEmployee(Map<String, dynamic>.from(e)))
        .toList();
    final projects = (data['projects'] as List? ?? [])
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    setState(() {
      _employees = emps;
      if (projects.isNotEmpty) _projects = projects;
      _loading = false;
      _error = null;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _employees.where((e) {
      if (_statusFilter != 'all' && e['status'] != _statusFilter) return false;
      if (q.isEmpty) return true;
      final hay = '${e['name']} ${e['department']} ${e['username']}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  int _count(String status) {
    if (status == 'all') return _employees.length;
    return _employees.where((e) => e['status'] == status).length;
  }

  List<MonitorScreenItem> get _screenItems =>
      _filtered.expand((e) => flattenEmployeeScreens(e)).toList();

  void _openLive(MonitorScreenItem item) {
    showMonitorLiveDialog(context, apiService: widget.apiService, item: item);
  }

  void _openReport(MonitorScreenItem item) {
    showMonitorReportSheet(context, apiService: widget.apiService, item: item);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const ColoredBox(
        color: _pageBg,
        child: Center(child: CircularProgressIndicator(color: AppTheme.primaryBright)),
      );
    }
    if (!_allowed) {
      return ColoredBox(
        color: _pageBg,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 42, color: AppTheme.textMuted),
                  const SizedBox(height: 12),
                  const Text(
                    'Admin access required',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Live Monitor is only available to company admins.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 1400
        ? 4
        : width >= 1100
            ? 3
            : width >= 520
                ? 2
                : 2;

    return ColoredBox(
      color: _pageBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Live Monitor',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => _load(),
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search employees…',
                  hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8)),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_projects.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonFormField<int?>(
                  value: _projectId,
                  dropdownColor: const Color(0xFF1F2C34),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Project filter',
                    labelStyle: TextStyle(color: AppTheme.textMuted),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All projects')),
                    ..._projects.map(
                      (p) => DropdownMenuItem(
                        value: p['id'] as int?,
                        child: Text(p['name']?.toString() ?? 'Project'),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _projectId = v);
                    _load();
                  },
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('all', 'All', _count('all')),
                    _filterChip('online', 'Online', _count('online'), const Color(0xFF22C55E)),
                    _filterChip('idle', 'Idle', _count('idle'), const Color(0xFFF59E0B)),
                    _filterChip('offline', 'Offline', _count('offline'), AppTheme.textMuted),
                    _filterChip('break', 'Break', _count('break'), const Color(0xFF60A5FA)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBright))
                  : _error != null
                      ? _errorView()
                      : _screenItems.isEmpty
                          ? Center(
                              child: Text(
                                'No employees match your filters',
                                style: TextStyle(color: AppTheme.textMuted),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.78,
                              ),
                              itemCount: _screenItems.length,
                              itemBuilder: (_, i) {
                                final item = _screenItems[i];
                                return MonitorScreenCard(
                                  item: item,
                                  apiService: widget.apiService,
                                  onLiveTap: () => _openLive(item),
                                  onReportTap: () => _openReport(item),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: AppTheme.danger.withValues(alpha: 0.85)),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.danger)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String id, String label, int count, [Color? color]) {
    final active = _statusFilter == id;
    final c = color ?? AppTheme.primaryBright;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text('$label ($count)'),
        selected: active,
        onSelected: (_) => setState(() => _statusFilter = id),
        selectedColor: c.withValues(alpha: 0.2),
        checkmarkColor: c,
        labelStyle: TextStyle(
          color: active ? c : AppTheme.textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        side: BorderSide(color: active ? c.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08)),
      ),
    );
  }
}
