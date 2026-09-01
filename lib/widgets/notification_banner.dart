import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/notification_ui.dart';
import '../utils/whatsapp_avatar.dart';

/// WhatsApp-style heads-up banner when a notification arrives in the open app.
class NotificationBanner {
  NotificationBanner._();

  static OverlayEntry? _entry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    String notificationType = '',
    VoidCallback? onTap,
  }) {
    _dismissTimer?.cancel();
    _entry?.remove();
    _entry = null;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final isChat = notificationType == 'new_message' || notificationType == 'new_group_message';
    final color = isChat ? const Color(0xFF00A884) : NotificationUi.colorFor(notificationType);
    final icon = NotificationUi.iconFor(notificationType);

    _entry = OverlayEntry(
      builder: (ctx) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Material(
              color: Colors.transparent,
              child: Dismissible(
                key: const ValueKey('aims_wa_banner'),
                direction: DismissDirection.up,
                onDismissed: (_) => hide(),
                child: GestureDetector(
                  onTap: () {
                    hide();
                    onTap?.call();
                  },
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2C34),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: color,
                          child: isChat
                              ? Text(
                                  WhatsAppAvatar.initials(title),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                )
                              : Icon(icon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  height: 1.2,
                                ),
                              ),
                              if (message.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  message,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF8696A0),
                                    fontSize: 13.5,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'now',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_entry!);
    _dismissTimer = Timer(const Duration(seconds: 5), hide);
  }

  static void hide() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _entry?.remove();
    _entry = null;
  }
}
