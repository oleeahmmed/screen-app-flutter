import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/monitor_media_url.dart';

class MonitorPlaybackSheet extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> employee;

  const MonitorPlaybackSheet({
    super.key,
    required this.apiService,
    required this.employee,
  });

  @override
  State<MonitorPlaybackSheet> createState() => _MonitorPlaybackSheetState();
}

class _MonitorPlaybackSheetState extends State<MonitorPlaybackSheet> {
  late List<Map<String, dynamic>> _screens;
  int _activeScreen = 0;
  String? _liveUrl;
  Timer? _poll;
  bool _generating = false;
  String? _videoUrl;
  String? _videoError;
  int? _jobId;
  DateTime _start = DateTime.now().subtract(const Duration(hours: 1));
  DateTime _end = DateTime.now();

  int get _userId => widget.employee['id'] is int
      ? widget.employee['id'] as int
      : int.parse('${widget.employee['id']}');

  @override
  void initState() {
    super.initState();
    _screens = (widget.employee['screens'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (_screens.isEmpty) {
      _screens = [
        {
          'id': '1',
          'index': 1,
          'label': 'Screen 1',
          'url': widget.employee['screenshot'],
        },
      ];
    }
    _liveUrl = _screens.first['url']?.toString();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refreshLive());
    unawaited(_refreshLive());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshLive() async {
    final screenNum = _screens[_activeScreen]['index'] is int
        ? _screens[_activeScreen]['index'] as int
        : int.tryParse('${_screens[_activeScreen]['index']}') ?? (_activeScreen + 1);
    final r = await widget.apiService.getLiveMonitorEmployeeScreen(_userId, screenNum);
    if (!mounted || r['success'] != true) return;
    final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
    final url = monitorMediaUrl(data['url'] ?? data['screenshot_url']);
    if (url != null) setState(() => _liveUrl = url);
  }

  Future<void> _generateVideo() async {
    setState(() {
      _generating = true;
      _videoError = null;
      _videoUrl = null;
    });
    final fmt = DateFormat('yyyy-MM-dd');
    final r = await widget.apiService.generateMonitorVideo(
      userId: _userId,
      startDate: fmt.format(_start),
      endDate: fmt.format(_end),
    );
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _generating = false;
        _videoError = r['error']?.toString();
      });
      return;
    }
    final jobId = r['data']?['job_id'];
    _jobId = jobId is int ? jobId : int.tryParse('$jobId');
    if (_jobId == null) {
      setState(() {
        _generating = false;
        _videoError = 'No job id returned';
      });
      return;
    }
    await _pollVideoJob();
  }

  Future<void> _pollVideoJob() async {
    for (var i = 0; i < 120; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final r = await widget.apiService.getMonitorVideoStatus(_jobId!);
      if (r['success'] != true) continue;
      final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
      final status = data['status']?.toString() ?? '';
      if (status == 'completed') {
        setState(() {
          _generating = false;
          _videoUrl = monitorMediaUrl(data['video_url']);
        });
        return;
      }
      if (status == 'failed') {
        setState(() {
          _generating = false;
          _videoError = data['error_message']?.toString() ?? 'Video generation failed';
        });
        return;
      }
    }
    if (mounted) {
      setState(() {
        _generating = false;
        _videoError = 'Video generation timed out';
      });
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.92;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF111B21),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.employee['name']?.toString() ?? 'Employee',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.employee['designation']?.toString() ?? '',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
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
          if (_screens.length > 1)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _screens.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final active = i == _activeScreen;
                  return ChoiceChip(
                    label: Text(_screens[i]['label']?.toString() ?? 'Screen ${i + 1}'),
                    selected: active,
                    onSelected: (_) {
                      setState(() {
                        _activeScreen = i;
                        _liveUrl = _screens[i]['url']?.toString();
                      });
                      unawaited(_refreshLive());
                    },
                    selectedColor: AppTheme.primary.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      color: active ? AppTheme.primaryBright : AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _videoUrl != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.film, color: Colors.white, size: 40),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: () async {
                                    final uri = Uri.parse(_videoUrl!);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  },
                                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                  label: const Text('Open video'),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton.filled(
                              onPressed: () => setState(() => _videoUrl = null),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ),
                        ],
                      )
                    : _liveUrl != null && _liveUrl!.isNotEmpty
                        ? Image.network(
                            _liveUrl!,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => _noImage(),
                          )
                        : _noImage(),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Generate timelapse video',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(start: true),
                        child: Text(DateFormat('yyyy-MM-dd').format(_start)),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded, color: AppTheme.textMuted, size: 18),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(start: false),
                        child: Text(DateFormat('yyyy-MM-dd').format(_end)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _generating ? null : _generateVideo,
                  icon: _generating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.film, size: 18),
                  label: Text(_generating ? 'Generating…' : 'Generate video'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_videoError != null) ...[
                  const SizedBox(height: 8),
                  Text(_videoError!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noImage() {
    return Container(
      color: const Color(0xFF1F2C34),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.monitor, color: AppTheme.textMuted, size: 36),
          const SizedBox(height: 8),
          Text('No live screenshot', style: TextStyle(color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}
