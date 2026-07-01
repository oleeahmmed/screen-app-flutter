import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android MediaProjection screenshot capture via platform channel.
class AndroidScreenshotChannel {
  static const MethodChannel _channel =
      MethodChannel('com.example.igen_app/screenshot');

  static Future<bool> requestAndroidPermissions() async {
    final notif = await Permission.notification.request();
    if (!notif.isGranted && !notif.isLimited) {
      // Continue — notification may be optional on older Android.
    }
    return true;
  }

  static Future<bool> requestScreenCapturePermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      return granted == true;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isPermissionGranted() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isPermissionGranted');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startForeground() async {
    try {
      await _channel.invokeMethod('startForeground');
    } catch (_) {}
  }

  static Future<void> stopForeground() async {
    try {
      await _channel.invokeMethod('stopForeground');
    } catch (_) {}
  }

  static Future<Uint8List?> capture() async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('capture');
      return bytes;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> releaseProjection() async {
    try {
      await _channel.invokeMethod('releaseProjection');
    } catch (_) {}
  }
}
