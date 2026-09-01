import 'package:flutter/material.dart';

import '../pages/call_page.dart';

/// Opens [CallPage] from services without importing [main.dart].
class CallNavigation {
  CallNavigation._();

  static GlobalKey<NavigatorState>? navigatorKey;

  static void openCallPageIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey?.currentState;
      if (nav == null) return;
      final top = ModalRoute.of(nav.context)?.settings.name;
      if (top == '/call') return;
      nav.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/call'),
          builder: (_) => const CallPage(),
          fullscreenDialog: true,
        ),
      );
    });
  }
}
