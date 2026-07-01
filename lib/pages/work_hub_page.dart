import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/screenshot_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/hub_quick_actions.dart';
import 'projects_page.dart';
import 'tasks_page.dart';
import 'daily_report_tool_page.dart';
import 'activity_tool_page.dart';
import 'vault_hub_page.dart';

/// Work hub — Projects + My tasks with collapsible quick actions.
class WorkHubPage extends StatefulWidget {
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
  State<WorkHubPage> createState() => _WorkHubPageState();
}

class _WorkHubPageState extends State<WorkHubPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openTool(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.apiService;
    final logout = widget.onLogout;
    final pad = Responsive.pagePadding(context);

    return Container(
      decoration: AppTheme.screenGradient(),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 6, pad, 6),
              child: HubQuickActionsCard(
                  collapsible: true,
                  initiallyExpanded: false,
                  subtitle: 'Reports, activity & vault',
                  actions: [
                    HubQuickAction(
                      label: 'Daily Report',
                      icon: Icons.assignment_outlined,
                      color: AppTheme.featureReport,
                      onTap: () => _openTool(DailyReportToolPage(apiService: api, onLogout: logout)),
                    ),
                    HubQuickAction(
                      label: 'Today\'s Activity',
                      icon: Icons.timeline_rounded,
                      color: AppTheme.featureChat,
                      onTap: () => _openTool(ActivityToolPage(apiService: api, onLogout: logout)),
                    ),
                    HubQuickAction(
                      label: 'Vault',
                      icon: Icons.lock_outline_rounded,
                      color: AppTheme.featureVault,
                      onTap: () => _openTool(VaultHubPage(apiService: api, onLogout: logout)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        color: AppTheme.surface2.withValues(alpha: 0.45),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: AppTheme.primary.withValues(alpha: 0.26),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.32)),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorPadding: const EdgeInsets.all(5),
                        labelColor: AppTheme.primaryBright,
                        unselectedLabelColor: AppTheme.textMuted,
                        dividerColor: Colors.transparent,
                        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        tabs: const [
                          Tab(
                            height: 40,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.folder_open, size: 17),
                                SizedBox(width: 7),
                                Text('Projects'),
                              ],
                            ),
                          ),
                          Tab(
                            height: 40,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.assignment_turned_in_outlined, size: 17),
                                SizedBox(width: 7),
                                Text('My tasks'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ProjectsPage(
                      apiService: widget.apiService,
                      embeddedInParent: true,
                    ),
                    TasksPage(apiService: widget.apiService, embeddedInParent: true),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }
}
