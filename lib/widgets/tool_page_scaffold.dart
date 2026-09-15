import 'package:flutter/material.dart';

import 'app_shell.dart';

/// Standard shell for pushed tool pages (report, activity, vault, P2P).
class ToolPageScaffold extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? header;
  final Widget? trailing;
  final Widget child;
  final VoidCallback? onLogout;
  final bool scrollable;
  final bool useBackground;
  final bool showHeader;
  /// When null, shows back if this route can be popped.
  final bool? showBack;

  const ToolPageScaffold({
    super.key,
    this.title,
    this.subtitle,
    this.header,
    this.trailing,
    required this.child,
    this.onLogout,
    this.scrollable = true,
    /// Prefer false inside [AppTabShell] so Home ambient background is not doubled.
    this.useBackground = false,
    this.showHeader = true,
    this.showBack,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Material(
      color: Colors.transparent,
      child: AppShell(
        title: title,
        subtitle: subtitle,
        header: header,
        trailing: trailing,
        showBack: showBack ?? canPop,
        showQuickMenu: false,
        onLogout: onLogout,
        scrollable: scrollable,
        useBackground: useBackground,
        showHeader: showHeader,
        child: child,
      ),
    );
  }
}
