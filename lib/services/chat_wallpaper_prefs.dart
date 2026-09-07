import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChatWallpaperKind { doodle, solid, image }

class ChatWallpaperPrefs {
  ChatWallpaperPrefs._();

  static const _kindKey = 'chat_wallpaper_kind';
  static const _solidKey = 'chat_wallpaper_solid';
  static const _imageKey = 'chat_wallpaper_image_path';

  static Future<({
    ChatWallpaperKind kind,
    int solidColor,
    String? imagePath,
  })> load() async {
    final prefs = await SharedPreferences.getInstance();
    final kindStr = prefs.getString(_kindKey) ?? 'doodle';
    final kind = ChatWallpaperKind.values.firstWhere(
      (k) => k.name == kindStr,
      orElse: () => ChatWallpaperKind.doodle,
    );
    final solid = prefs.getInt(_solidKey) ?? 0xFF0B141A;
    final imagePath = prefs.getString(_imageKey);
    if (kind == ChatWallpaperKind.image &&
        (imagePath == null || !File(imagePath).existsSync())) {
      return (kind: ChatWallpaperKind.doodle, solidColor: solid, imagePath: null);
    }
    return (kind: kind, solidColor: solid, imagePath: imagePath);
  }

  static Future<void> setDoodle() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kindKey, ChatWallpaperKind.doodle.name);
  }

  static Future<void> setSolid(int argb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kindKey, ChatWallpaperKind.solid.name);
    await prefs.setInt(_solidKey, argb);
  }

  static Future<String> setImageFile(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final wallpapers = Directory('${dir.path}/chat_wallpapers');
    if (!await wallpapers.exists()) {
      await wallpapers.create(recursive: true);
    }
    final dest = File('${wallpapers.path}/active.jpg');
    await source.copy(dest.path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kindKey, ChatWallpaperKind.image.name);
    await prefs.setString(_imageKey, dest.path);
    return dest.path;
  }

  static Future<void> clearImage() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_imageKey);
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await prefs.remove(_imageKey);
    await prefs.setString(_kindKey, ChatWallpaperKind.doodle.name);
  }
}
