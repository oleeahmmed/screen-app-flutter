import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'projects_page.dart';
import 'tasks_page.dart';

/// Web-style Work area: **Projects** list (grid) → open **Project detail** (stages, tasks, subtasks, DnD).
/// Second tab: **My tasks** (everything assigned to you).
class WorkHubPage extends StatefulWidget {
  final ApiService apiService;

  const WorkHubPage({super.key, required this.apiService});

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.screenGradient(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Work',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.surface2.withValues(alpha: 0.55),
                          AppTheme.surface.withValues(alpha: 0.42),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppTheme.primary.withValues(alpha: 0.28),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: AppTheme.primaryBright,
                      unselectedLabelColor: AppTheme.textMuted,
                      dividerColor: Colors.transparent,
                      overlayColor: WidgetStateProperty.all(Colors.white10),
                      tabs: const [
                        Tab(
                          height: 44,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_open, size: 18),
                              SizedBox(width: 8),
                              Text('Projects'),
                            ],
                          ),
                        ),
                        Tab(
                          height: 44,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_turned_in_outlined, size: 18),
                              SizedBox(width: 8),
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
                  TasksPage(apiService: widget.apiService),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
