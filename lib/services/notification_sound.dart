import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_capabilities.dart';

/// Plays a short alert when a notification arrives.
class NotificationSound {
  NotificationSound._();

  static AudioPlayer? _player;
  static DateTime? _lastPlayedAt;

  static bool get _useNativePlayer => PlatformCapabilities.nativeAudio;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notification_sound_enabled') ?? true;
  }

  /// Play notification chime (debounced ~1.5s to avoid double-firing).
  static Future<void> playNotification() async {
    if (!await isEnabled()) return;

    final now = DateTime.now();
    if (_lastPlayedAt != null && now.difference(_lastPlayedAt!) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastPlayedAt = now;

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    if (!_useNativePlayer) return;

    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.setVolume(1.0);
      await _player!.play(AssetSource('sounds/notification.mp3'));
    } catch (_) {
      try {
        await _player!.play(UrlSource(
          'https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3',
        ));
      } catch (_) {}
    }
  }

  @Deprecated('Use playNotification()')
  static Future<void> playPing() => playNotification();
}
