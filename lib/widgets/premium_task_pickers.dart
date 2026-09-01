import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/task_helpers.dart';

Color avatarColorForName(String name) {
  const palette = [
    Color(0xFF3B82F6),
    Color(0xFF06B6D4),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF6366F1),
  ];
  if (name.isEmpty) return palette[0];
  return palette[name.codeUnitAt(0) % palette.length];
}

/// Premium assignee picker — Submit Report sheet language + staggered motion.
Future<List<int>?> showPremiumAssigneeSheet({
  required BuildContext context,
  required List<dynamic> employees,
  required List<int> selectedIds,
  bool requireAtLeastOne = false,
  String title = 'Assign people',
}) {
  final people = normalizeProjectEmployeesList(employees);
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppTheme.modalBarrierColor,
    builder: (ctx) => _PremiumAssigneeSheet(
      employees: people,
      initialSelected: selectedIds,
      requireAtLeastOne: requireAtLeastOne,
      title: title,
    ),
  );
}

/// Premium stage picker — animated stage chips in a compact sheet.
Future<int?> showPremiumStageSheet({
  required BuildContext context,
  required List<dynamic> stages,
  int? selectedStageId,
  String? currentName,
}) {
  return showModalBottomSheet<int?>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppTheme.modalBarrierColor,
    builder: (ctx) => _PremiumStageSheet(
      stages: stages,
      selectedStageId: selectedStageId,
      currentName: currentName,
    ),
  );
}

Widget _sheetShell({
  required BuildContext context,
  required double maxHeightFactor,
  required Widget child,
}) {
  final media = MediaQuery.of(context);
  return Padding(
    padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * maxHeightFactor),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: DecoratedBox(
            decoration: AppTheme.taskCardDecoration(borderRadius: 20).copyWith(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(top: false, child: child),
          ),
        ),
      ),
    ),
  );
}

Widget _handle() => Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

class _PremiumAssigneeSheet extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final List<int> initialSelected;
  final bool requireAtLeastOne;
  final String title;

  const _PremiumAssigneeSheet({
    required this.employees,
    required this.initialSelected,
    required this.requireAtLeastOne,
    required this.title,
  });

  @override
  State<_PremiumAssigneeSheet> createState() => _PremiumAssigneeSheetState();
}

class _PremiumAssigneeSheetState extends State<_PremiumAssigneeSheet>
    with SingleTickerProviderStateMixin {
  late Set<int> _selected;
  late AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelected};
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  void _toggle(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _sheetShell(
      context: context,
      maxHeightFactor: 0.62,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          _handle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selected.isEmpty
                            ? 'Tap people to assign this task'
                            : '${_selected.length} selected',
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.9),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: AppTheme.textMuted.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          Flexible(
            child: widget.employees.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                    child: Text(
                      'No assignable people on this project',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.75)),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    itemCount: widget.employees.length,
                    itemBuilder: (context, i) {
                      final e = widget.employees[i];
                      final id = employeeUserIdFrom(e);
                      if (id == null) return const SizedBox.shrink();
                      final name = (e['full_name'] ?? e['username'] ?? e['name'] ?? 'User').toString();
                      final role = (e['designation'] ?? e['role'] ?? '').toString();
                      final on = _selected.contains(id);
                      final interval = Interval(
                        (i * 0.05).clamp(0.0, 0.55),
                        ((i * 0.05) + 0.45).clamp(0.2, 1.0),
                        curve: Curves.easeOutCubic,
                      );
                      return FadeTransition(
                        opacity: _enter.drive(CurveTween(curve: interval)),
                        child: SlideTransition(
                          position: _enter.drive(
                            Tween(begin: const Offset(0, 0.18), end: Offset.zero)
                                .chain(CurveTween(curve: interval)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PersonTile(
                              name: name,
                              role: role,
                              selected: on,
                              onTap: () => _toggle(id),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: _selected.isEmpty
                        ? [
                            AppTheme.primary.withValues(alpha: 0.45),
                            AppTheme.primary.withValues(alpha: 0.35),
                          ]
                        : const [Color(0xFF3B82F6), Color(0xFF2563EB)],
                  ),
                  boxShadow: [
                    if (_selected.isNotEmpty)
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                  ],
                ),
                child: FilledButton(
                  onPressed: () {
                    if (widget.requireAtLeastOne && _selected.isEmpty) {
                      AppToast.warning(context, 'Select at least one assignee');
                      return;
                    }
                    Navigator.pop(context, _selected.toList()..sort());
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _selected.isEmpty ? 'Clear assignees' : 'Save assignees',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  final String name;
  final String role;
  final bool selected;
  final VoidCallback onTap;

  const _PersonTile({
    required this.name,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = avatarColorForName(name);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryBright.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: selected ? 1.05 : 1,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: color.withValues(alpha: 0.9),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (role.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        role,
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppTheme.success : Colors.transparent,
                  border: Border.all(
                    color: selected ? AppTheme.success : Colors.white.withValues(alpha: 0.25),
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumStageSheet extends StatefulWidget {
  final List<dynamic> stages;
  final int? selectedStageId;
  final String? currentName;

  const _PremiumStageSheet({
    required this.stages,
    required this.selectedStageId,
    this.currentName,
  });

  @override
  State<_PremiumStageSheet> createState() => _PremiumStageSheetState();
}

class _PremiumStageSheetState extends State<_PremiumStageSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _enter;
  int? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.selectedStageId;
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stages = widget.stages.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

    return _sheetShell(
      context: context,
      maxHeightFactor: 0.48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          _handle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Move to stage',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.currentName?.isNotEmpty == true
                            ? 'Current: ${widget.currentName}'
                            : 'Pick a stage for this task',
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.9),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: AppTheme.textMuted.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: stages.length,
              itemBuilder: (context, i) {
                final s = stages[i];
                final id = int.tryParse('${s['id']}');
                final name = s['name']?.toString() ?? 'Stage';
                final selected = id != null && id == _picked;
                final interval = Interval(
                  (i * 0.06).clamp(0.0, 0.5),
                  ((i * 0.06) + 0.5).clamp(0.25, 1.0),
                  curve: Curves.easeOutCubic,
                );
                return FadeTransition(
                  opacity: _enter.drive(CurveTween(curve: interval)),
                  child: SlideTransition(
                    position: _enter.drive(
                      Tween(begin: const Offset(0, 0.16), end: Offset.zero)
                          .chain(CurveTween(curve: interval)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() => _picked = id);
                            Future.delayed(const Duration(milliseconds: 140), () {
                              if (context.mounted) Navigator.pop(context, id);
                            });
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: selected
                                  ? LinearGradient(
                                      colors: [
                                        AppTheme.accent.withValues(alpha: 0.22),
                                        AppTheme.primary.withValues(alpha: 0.14),
                                      ],
                                    )
                                  : null,
                              color: selected ? null : Colors.white.withValues(alpha: 0.04),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.accent.withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selected ? AppTheme.accent : AppTheme.textMuted.withValues(alpha: 0.45),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                              color: AppTheme.accent.withValues(alpha: 0.55),
                                              blurRadius: 8,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 14.5,
                                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
