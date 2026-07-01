import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HubQuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const HubQuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

/// Glass quick-action chips — optional collapsible header.
class HubQuickActionsCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<HubQuickAction> actions;
  final bool collapsible;
  final bool initiallyExpanded;

  const HubQuickActionsCard({
    super.key,
    this.title = 'Quick Actions',
    this.subtitle,
    required this.actions,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  @override
  State<HubQuickActionsCard> createState() => _HubQuickActionsCardState();
}

class _HubQuickActionsCardState extends State<HubQuickActionsCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.glassPanel(borderRadius: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.collapsible ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 18, color: AppTheme.primaryBright.withValues(alpha: 0.9)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: AppTheme.sectionTitle.copyWith(fontSize: 13),
                          ),
                          if (widget.subtitle != null && (!_expanded || !widget.collapsible))
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                widget.subtitle!,
                                style: AppTheme.caption.copyWith(fontSize: 11),
                              ),
                            ),
                          if (widget.collapsible && !_expanded)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${widget.actions.length} shortcuts',
                                style: AppTheme.caption.copyWith(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.collapsible)
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: AppTheme.textMuted.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeIn,
            crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOut,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.actions.map(_chip).toList(),
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _chip(HubQuickAction action) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: action.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 15, color: action.color),
              const SizedBox(width: 7),
              Text(
                action.label,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
