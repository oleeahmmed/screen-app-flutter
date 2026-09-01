import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_capabilities.dart';

/// Message pop + looping call ringtone / ringback (WhatsApp-like originals).
class NotificationSound {
  NotificationSound._();

  static AudioPlayer? _alertPlayer;
  static AudioPlayer? _callPlayer;
  static DateTime? _lastPlayedAt;
  static String? _callMode; // ringtone | ringback

  static bool get _useNativePlayer => PlatformCapabilities.nativeAudio;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notification_sound_enabled') ?? true;
  }

  /// Short message chime (debounced ~1.5s to avoid double-firing).
  static Future<void> playNotification() async {
    if (!await isEnabled()) return;

    final now = DateTime.now();
    if (_lastPlayedAt != null &&
        now.difference(_lastPlayedAt!) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastPlayedAt = now;

    if (_useNativePlayer) {
      try {
        _alertPlayer ??= AudioPlayer();
        await _alertPlayer!.stop();
        await _alertPlayer!.setReleaseMode(ReleaseMode.stop);
        await _alertPlayer!.setVolume(1.0);
        await _alertPlayer!.play(AssetSource('sounds/message.wav'));
        return;
      } catch (_) {
        try {
          await _alertPlayer!.play(AssetSource('sounds/notification.mp3'));
          return;
        } catch (_) {}
      }
    }

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  static Future<void> playRingtone() => _loopCallAsset('sounds/ringtone.wav', 'ringtone');

  static Future<void> playRingback() => _loopCallAsset('sounds/ringback.wav', 'ringback');

  static Future<void> _loopCallAsset(String asset, String mode) async {
    if (!await isEnabled()) return;
    if (!_useNativePlayer) return;
    if (_callMode == mode && _callPlayer != null) return;
    try {
      _callPlayer ??= AudioPlayer();
      await _callPlayer!.stop();
      await _callPlayer!.setReleaseMode(ReleaseMode.loop);
      await _callPlayer!.setVolume(1.0);
      _callMode = mode;
      await _callPlayer!.play(AssetSource(asset));
    } catch (_) {
      _callMode = null;
    }
  }

  static Future<void> stopCallSounds() async {
    _callMode = null;
    try {
      await _callPlayer?.stop();
    } catch (_) {}
  }

  @Deprecated('Use playNotification()')
  static Future<void> playPing() => playNotification();
}
