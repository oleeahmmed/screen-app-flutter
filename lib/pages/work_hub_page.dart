import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/screenshot_service.dart';
import '../theme/app_theme.dart';
import 'projects_page.dart';

/// Project hub — project list.
class WorkHubPage extends StatelessWidget {
  final ApiService apiService;
  final ScreenshotService? screenshotService;
  final VoidCallback? onLogout;

  const WorkHubPage({
    super.key,
    required this.apiService,
    this.screenshotService,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return AppTheme.homeGlassBackground(
      child: SafeArea(
        bottom: false,
        child: ProjectsPage(
          apiService: apiService,
          embeddedInParent: true,
        ),
      ),
    );
  }
}
