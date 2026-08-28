import 'package:flutter/material.dart';

import 'app_shell.dart';

/// Standard shell for pushed tool pages (report, activity, vault, P2P).
class ToolPageScaffold extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onLogout;
  final bool scrollable;
  final bool useBackground;
  final bool showHeader;

  const ToolPageScaffold({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.onLogout,
    this.scrollable = true,
    this.useBackground = true,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      showBack: false,
      showQuickMenu: false,
      onLogout: onLogout,
      scrollable: scrollable,
      useBackground: useBackground,
      showHeader: showHeader,
      child: child,
    );
  }
}
