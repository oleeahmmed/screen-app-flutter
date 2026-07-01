import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/day_activity_timeline.dart';
import '../widgets/tool_page_scaffold.dart';

class ActivityToolPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;

  const ActivityToolPage({
    super.key,
    required this.apiService,
    this.onLogout,
  });

  @override
  State<ActivityToolPage> createState() => _ActivityToolPageState();
}

class _ActivityToolPageState extends State<ActivityToolPage> {
  bool _isClockedIn = false;
  DateTime? _clockInTime;
  bool _onBreak = false;
  int _refresh = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final att = await widget.apiService.getCurrentAttendance();
    final br = await widget.apiService.getBreakStatus();
    if (!mounted) return;

    var clockedIn = false;
    DateTime? checkIn;
    final current = att['data']?['current_attendance'];
    if (current is Map && (current['check_out'] == null ||
        (current['check_out'] is String && (current['check_out'] as String).trim().isEmpty))) {
      clockedIn = true;
      checkIn = DateTime.tryParse(current['check_in']?.toString() ?? '')?.toLocal();
    }

    var onBreak = false;
    if (br['success'] == true) {
      onBreak = br['data']?['on_break'] == true;
    }

    setState(() {
      _isClockedIn = clockedIn;
      _clockInTime = checkIn;
      _onBreak = onBreak;
      _refresh++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ToolPageScaffold(
      title: 'Today\'s Activity',
      subtitle: 'Clock-in, breaks, and sessions',
      onLogout: widget.onLogout,
      child: DayActivityTimeline(
        apiService: widget.apiService,
        refreshToken: _refresh,
        isClockedIn: _isClockedIn,
        clockInTime: _clockInTime,
        onBreak: _onBreak,
        collapsible: false,
        initiallyExpanded: true,
      ),
    );
  }
}
