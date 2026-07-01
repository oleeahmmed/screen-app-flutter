import 'package:flutter/material.dart';

import 'app_shell.dart';

/// Standard shell for pushed tool pages (report, activity, vault, P2P).
class ToolPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onLogout;
  final bool scrollable;

  const ToolPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.onLogout,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      showBack: true,
      showQuickMenu: true,
      onLogout: onLogout,
      scrollable: scrollable,
      child: child,
    );
  }
}
