import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'app_quick_menu.dart';

/// Standard page shell: gradient background, optional header, constrained content.
class AppShell extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? header;
  final Widget? trailing;
  final bool showBack;
  final bool showQuickMenu;
  final VoidCallback? onLogout;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;
  final bool wide;
  final Widget child;

  const AppShell({
    super.key,
    this.title,
    this.subtitle,
    this.header,
    this.trailing,
    this.showBack = false,
    this.showQuickMenu = false,
    this.onLogout,
    this.scrollable = true,
    this.padding,
    this.wide = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final pad = padding ?? EdgeInsets.all(Responsive.pagePadding(context));
    final hasHeader = header != null || title != null;

    return AppTheme.homeGlassBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                child: header ?? _defaultHeader(context),
              ),
            Expanded(
              child: wide
                  ? Responsive.constrainWide(
                      context,
                      scrollable
                          ? SingleChildScrollView(
                              padding: pad,
                              child: child,
                            )
                          : Padding(
                              padding: pad,
                              child: child,
                            ),
                    )
                  : Responsive.constrainContent(
                      context,
                      scrollable
                          ? SingleChildScrollView(
                              padding: pad,
                              child: child,
                            )
                          : Padding(
                              padding: pad,
                              child: child,
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBack) const AppBackButton(),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Text(
                  title!,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (showQuickMenu)
          AppHeaderMenuActions(onLogout: onLogout),
      ],
    );
  }
}
