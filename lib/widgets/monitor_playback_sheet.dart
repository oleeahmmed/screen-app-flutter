import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'monitor_ui.dart';

/// Legacy entry — opens the new report sheet for the employee's first screen.
class MonitorPlaybackSheet extends StatelessWidget {
  final ApiService apiService;
  final Map<String, dynamic> employee;

  const MonitorPlaybackSheet({
    super.key,
    required this.apiService,
    required this.employee,
  });

  @override
  Widget build(BuildContext context) {
    final item = flattenEmployeeScreens(employee).first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showMonitorReportSheet(context, apiService: apiService, item: item);
    });
    return const SizedBox.shrink();
  }
}
