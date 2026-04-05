import 'package:audioplayers/audioplayers.dart';

/// Short CC0-style ping when unread count increases (requires network once).
class NotificationSound {
  NotificationSound._();

  static final AudioPlayer _player = AudioPlayer();
  static const _url =
      'https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3';

  static Future<void> playPing() async {
    try {
      await _player.stop();
      await _player.play(UrlSource(_url));
    } catch (_) {}
  }
}
