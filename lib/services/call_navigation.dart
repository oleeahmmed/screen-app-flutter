import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/call_page.dart';

/// Opens [CallPage] from services without importing [main.dart].
class CallNavigation {
  CallNavigation._();

  static GlobalKey<NavigatorState>? navigatorKey;

  static bool _isCallRouteOpen(NavigatorState nav) {
    final top = ModalRoute.of(nav.context)?.settings.name;
    return top == '/call';
  }

  /// Full-screen call UI on the root navigator (never the chat split pane).
  static Future<void> openCallPageIfNeeded() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_pushCallRoute().whenComplete(completer.complete));
    });
    return completer.future;
  }

  static Future<void> _pushCallRoute() async {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    if (_isCallRouteOpen(nav)) return;

    await nav.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/call'),
        fullscreenDialog: true,
        builder: (_) => const CallPage(),
      ),
    );
  }
}
