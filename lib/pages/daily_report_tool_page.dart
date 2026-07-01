import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/closing_report_panel.dart';
import '../widgets/tool_page_scaffold.dart';

class DailyReportToolPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;

  const DailyReportToolPage({
    super.key,
    required this.apiService,
    this.onLogout,
  });

  @override
  State<DailyReportToolPage> createState() => _DailyReportToolPageState();
}

class _DailyReportToolPageState extends State<DailyReportToolPage> {
  int _refresh = 0;

  @override
  Widget build(BuildContext context) {
    return ToolPageScaffold(
      title: 'Daily Report',
      subtitle: 'Submit your closing report for today',
      onLogout: widget.onLogout,
      child: ClosingReportPanel(
        apiService: widget.apiService,
        refreshToken: _refresh,
        onSubmitted: () => setState(() => _refresh++),
      ),
    );
  }
}
