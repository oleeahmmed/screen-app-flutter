import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/monitor_media_url.dart';
import '../widgets/report_ui.dart';

/// One physical monitor screen for an employee.
class MonitorScreenItem {
  final Map<String, dynamic> employee;
  final Map<String, dynamic> screen;

  const MonitorScreenItem({required this.employee, required this.screen});

  int get userId => employee['id'] is int ? employee['id'] as int : int.parse('${employee['id']}');
  int get employeeId => employee['employee_id'] is int
      ? employee['employee_id'] as int
      : int.parse('${employee['employee_id'] ?? employee['id']}');
  int get screenIndex => screen['index'] is int
      ? screen['index'] as int
      : int.tryParse('${screen['index']}') ?? 1;
  String get screenLabel => screen['label']?.toString() ?? 'Screen $screenIndex';
  String? get previewUrl => screen['url']?.toString();
  String get employeeName => employee['name']?.toString() ?? 'Employee';
  String get status => employee['status']?.toString() ?? 'offline';
}

List<MonitorScreenItem> flattenEmployeeScreens(Map<String, dynamic> emp) {
  final screens = (emp['screens'] as List? ?? [])
      .whereType<Map>()
      .map((s) => Map<String, dynamic>.from(s))
      .toList();
  if (screens.isEmpty) {
    return [
      MonitorScreenItem(
        employee: emp,
        screen: {
          'index': 1,
          'label': 'Screen 1',
          'url': emp['screenshot'],
        },
      ),
    ];
  }
  return screens
      .map((s) => MonitorScreenItem(employee: emp, screen: s))
      .toList();
}

Color monitorStatusColor(String status) {
  switch (status) {
    case 'online':
      return const Color(0xFF22C55E);
    case 'idle':
      return const Color(0xFFF59E0B);
    case 'break':
      return const Color(0xFF60A5FA);
    default:
      return AppTheme.textMuted;
  }
}

void showMonitorLiveDialog(
  BuildContext context, {
  required ApiService apiService,
  required MonitorScreenItem item,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _MonitorLiveDialog(apiService: apiService, item: item),
  );
}

void showMonitorReportSheet(
  BuildContext context, {
  required ApiService apiService,
  required MonitorScreenItem item,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MonitorReportSheet(apiService: apiService, item: item),
  );
}

/// Premium card — one monitor screen with live polling.
class MonitorScreenCard extends StatefulWidget {
  final MonitorScreenItem item;
  final ApiService apiService;
  final VoidCallback onLiveTap;
  final VoidCallback onReportTap;

  const MonitorScreenCard({
    super.key,
    required this.item,
    required this.apiService,
    required this.onLiveTap,
    required this.onReportTap,
  });

  @override
  State<MonitorScreenCard> createState() => _MonitorScreenCardState();
}

class _MonitorScreenCardState extends State<MonitorScreenCard> {
  String? _liveUrl;
  Timer? _poll;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _liveUrl = monitorMediaUrlCached(widget.item.previewUrl);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant MonitorScreenCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.screenIndex != widget.item.screenIndex ||
        oldWidget.item.employeeId != widget.item.employeeId) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final r = await widget.apiService.getLiveMonitorEmployeeScreen(
        widget.item.employeeId,
        widget.item.screenIndex,
      );
      if (!mounted || r['success'] != true) return;
      final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
      final url = monitorMediaUrlCached(
        data['url'] ?? data['screenshot_url'],
        uploadedAt: data['uploaded_at']?.toString(),
      );
      if (url != null && url != _liveUrl) {
        setState(() => _liveUrl = url);
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = monitorStatusColor(widget.item.status);
    final img = _liveUrl;

    return Container(
      decoration: AppTheme.taskCardDecoration(borderRadius: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onLiveTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (img != null && img.isNotEmpty)
                      Image.network(
                        img,
                        key: ValueKey(img),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => _thumbPlaceholder(),
                      )
                    else
                      _thumbPlaceholder(),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              widget.item.screenLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 8,
                      bottom: 8,
                      child: Icon(Icons.fullscreen_rounded, color: Colors.white70, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: widget.onReportTap,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(LucideIcons.film, size: 13, color: AppTheme.bgDeep),
                            SizedBox(width: 5),
                            Text(
                              'Report',
                              style: TextStyle(
                                color: AppTheme.bgDeep,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.04),
      child: const Center(
        child: Icon(LucideIcons.monitor, size: 28, color: AppTheme.textMuted),
      ),
    );
  }
}

class _MonitorLiveDialog extends StatefulWidget {
  final ApiService apiService;
  final MonitorScreenItem item;

  const _MonitorLiveDialog({required this.apiService, required this.item});

  @override
  State<_MonitorLiveDialog> createState() => _MonitorLiveDialogState();
}

class _MonitorLiveDialogState extends State<_MonitorLiveDialog> {
  String? _liveUrl;
  String? _lastUpdated;
  Timer? _poll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _liveUrl = monitorMediaUrlCached(widget.item.previewUrl);
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final r = await widget.apiService.getLiveMonitorEmployeeScreen(
      widget.item.employeeId,
      widget.item.screenIndex,
    );
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() => _loading = false);
      return;
    }
    final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
    final url = monitorMediaUrlCached(
      data['url'] ?? data['screenshot_url'],
      uploadedAt: data['uploaded_at']?.toString(),
    );
    if (url != null) {
      setState(() {
        _liveUrl = url;
        _lastUpdated = data['uploaded_at']?.toString();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
        decoration: AppTheme.loginShell().copyWith(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.employeeName,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${widget.item.screenLabel} · Live',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        const Text('LIVE', style: TextStyle(color: AppTheme.success, fontSize: 9, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            if (_lastUpdated != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Last capture: ${_formatTime(_lastUpdated!)}',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                  ),
                ),
              ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black,
                    child: _liveUrl != null && _liveUrl!.isNotEmpty
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 280),
                                child: Image.network(
                                  _liveUrl!,
                                  key: ValueKey(_liveUrl),
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) => _noSignal(),
                                ),
                              ),
                              if (_loading)
                                const Positioned(
                                  top: 8,
                                  right: 8,
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                  ),
                                ),
                            ],
                          )
                        : _noSignal(loading: _loading),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('h:mm:ss a').format(dt);
    } catch (_) {
      return iso;
    }
  }

  Widget _noSignal({bool loading = false}) {
    return SizedBox(
      height: 220,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBright),
              )
            else
              const Icon(LucideIcons.monitor, color: AppTheme.textMuted, size: 36),
            const SizedBox(height: 8),
            Text(
              loading ? 'Fetching latest screenshot…' : 'Waiting for screenshot…',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonitorReportSheet extends StatefulWidget {
  final ApiService apiService;
  final MonitorScreenItem item;

  const _MonitorReportSheet({required this.apiService, required this.item});

  @override
  State<_MonitorReportSheet> createState() => _MonitorReportSheetState();
}

class _MonitorReportSheetState extends State<_MonitorReportSheet> {
  late DateTime _startDate;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _endDateManual = false;
  bool _generating = false;
  String? _error;
  String? _localVideoPath;
  VideoPlayerController? _player;
  int? _jobId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = _startDate;
    _startTime = const TimeOfDay(hour: 9, minute: 0);
    _endTime = TimeOfDay(hour: now.hour, minute: now.minute);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.primaryBright, surface: AppTheme.surface2),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (!_endDateManual) _endDate = picked;
      } else {
        _endDate = picked;
        _endDateManual = true;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.primaryBright, surface: AppTheme.surface2),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
      _localVideoPath = null;
      _player?.dispose();
      _player = null;
    });

    final r = await widget.apiService.generateMonitorVideo(
      employeeId: widget.item.employeeId,
      startDate: _fmtDate(_startDate),
      endDate: _fmtDate(_endDate),
      startTime: _fmtTime(_startTime),
      endTime: _fmtTime(_endTime),
    );
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _generating = false;
        _error = r['error']?.toString() ?? 'Could not start video job';
      });
      return;
    }
    final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
    final jobId = data['job_id'];
    _jobId = jobId is int ? jobId : int.tryParse('$jobId');
    if (_jobId == null) {
      setState(() {
        _generating = false;
        _error = 'No job id returned';
      });
      return;
    }
    await _pollJob();
  }

  Future<void> _pollJob() async {
    for (var i = 0; i < 120; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final r = await widget.apiService.getMonitorVideoStatus(_jobId!);
      if (r['success'] != true) continue;
      final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
      final status = data['status']?.toString() ?? '';
      if (status == 'completed') {
        final url = monitorMediaUrl(data['video_url']);
        if (url == null) {
          setState(() {
            _generating = false;
            _error = 'Video URL missing';
          });
          return;
        }
        await _preparePlayer(url);
        return;
      }
      if (status == 'failed') {
        setState(() {
          _generating = false;
          _error = data['error_message']?.toString() ?? 'Video generation failed';
        });
        return;
      }
    }
    if (mounted) {
      setState(() {
        _generating = false;
        _error = 'Video generation timed out';
      });
    }
  }

  Future<void> _preparePlayer(String url) async {
    final bytes = await widget.apiService.downloadMediaBytes(url);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _generating = false;
        _error = 'Could not download video';
      });
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/monitor_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final file = File(path);
    await file.writeAsBytes(bytes);
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    if (!mounted) {
      controller.dispose();
      return;
    }
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() {
      _generating = false;
      _localVideoPath = path;
      _player = controller;
    });
  }

  Future<void> _downloadVideo() async {
    if (_localVideoPath == null) return;
    final src = File(_localVideoPath!);
    if (!await src.exists()) return;
    final dir = await getTemporaryDirectory();
    final name = 'monitor_${widget.item.employeeName.replaceAll(' ', '_')}_${_fmtDate(_startDate)}.mp4';
    final dest = File('${dir.path}/$name');
    await dest.writeAsBytes(await src.readAsBytes());
    await OpenFilex.open(dest.path);
  }

  Widget _pickerTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: ReportUi.inset(radius: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(label, style: ReportUi.mutedStyle.copyWith(fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(
        top: screenH * 0.10,
        left: 10,
        right: 10,
        bottom: bottom + 16,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: screenH * 0.78),
        decoration: AppTheme.loginShell().copyWith(
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  ReportUi.iconBox(icon: LucideIcons.film, color: AppTheme.primaryBright, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Activity Report',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${widget.item.employeeName} · ${widget.item.screenLabel}',
                          style: ReportUi.mutedStyle.copyWith(fontSize: 11.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('From', style: ReportUi.titleStyle),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _pickerTile(
                          label: 'Date',
                          value: DateFormat('d MMM yyyy').format(_startDate),
                          icon: Icons.calendar_today_outlined,
                          onTap: () => _pickDate(isStart: true),
                        ),
                        const SizedBox(width: 8),
                        _pickerTile(
                          label: 'Time',
                          value: _fmtTime(_startTime),
                          icon: Icons.schedule_outlined,
                          onTap: () => _pickTime(isStart: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('To', style: ReportUi.titleStyle),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _pickerTile(
                          label: 'Date',
                          value: DateFormat('d MMM yyyy').format(_endDate),
                          icon: Icons.calendar_today_outlined,
                          onTap: () => _pickDate(isStart: false),
                        ),
                        const SizedBox(width: 8),
                        _pickerTile(
                          label: 'Time',
                          value: _fmtTime(_endTime),
                          icon: Icons.schedule_outlined,
                          onTap: () => _pickTime(isStart: false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _generating ? null : _generate,
                      style: ReportUi.primaryButton(),
                      child: _generating
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.sparkles, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'Generate video',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ],
                            ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                    ],
                    if (_player != null && _player!.value.isInitialized) ...[
                      const SizedBox(height: 16),
                      const Text('Preview', style: ReportUi.titleStyle),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: _player!.value.aspectRatio,
                          child: VideoPlayer(_player!),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  if (_player!.value.isPlaying) {
                                    _player!.pause();
                                  } else {
                                    _player!.play();
                                  }
                                });
                              },
                              icon: Icon(
                                _player!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: Text(_player!.value.isPlaying ? 'Pause' : 'Play'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _downloadVideo,
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('Download'),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
