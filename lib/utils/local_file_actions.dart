import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Cross-platform open-file / open-folder for P2P received files.
class LocalFileActions {
  static const _channel = MethodChannel('com.example.igen_app/files');

  /// Directory where P2P received files should be stored (display path on Android).
  static Future<Directory> receiveDirectory() async {
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('getReceiveDirectory');
        if (path != null && path.isNotEmpty) {
          final dir = Directory(path);
          if (!await dir.exists()) await dir.create(recursive: true);
          return dir;
        }
      } catch (e) {
        debugPrint('[LocalFileActions] getReceiveDirectory: $e');
      }
    }
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Temp directory used while bytes are streaming in on Android.
  static Future<Directory> receiveTempDirectory() async {
    if (Platform.isAndroid) {
      return getTemporaryDirectory();
    }
    return receiveDirectory();
  }

  /// Move temp receive file into public Download/Aims (Android MediaStore).
  static Future<Map<String, String?>> commitReceiveFile(
    String sourcePath,
    String displayName,
  ) async {
    if (!Platform.isAndroid) {
      return {'path': sourcePath, 'contentUri': null};
    }
    try {
      final raw = await _channel.invokeMethod<Map>('commitReceiveFile', {
        'sourcePath': sourcePath,
        'displayName': displayName,
      });
      if (raw == null) return {'path': sourcePath, 'contentUri': null};
      return {
        'path': raw['path']?.toString() ?? sourcePath,
        'contentUri': raw['contentUri']?.toString(),
      };
    } catch (e) {
      debugPrint('[LocalFileActions] commitReceiveFile: $e');
      rethrow;
    }
  }

  /// Opens [path] with the system “Open with” chooser on Android.
  static Future<String> openFile(String path, {String? contentUri}) async {
    final file = File(path);
    if (contentUri == null && !await file.exists()) return 'missing';

    if (Platform.isAndroid) {
      try {
        final r = await _channel.invokeMethod<String>('openFile', {
          'path': path,
          if (contentUri != null) 'contentUri': contentUri,
        });
        if (r == 'ok' || r == 'no_handler') return r ?? 'ok';
      } catch (e) {
        debugPrint('[LocalFileActions] openFile channel failed: $e');
      }
      // Fallback — open_filex uses FileProvider on Android too.
      if (await file.exists()) {
        final mime = lookupMimeType(path);
        final r = await OpenFilex.open(path, type: mime);
        if (r.type == ResultType.done) return 'ok';
        if (r.type == ResultType.noAppToOpen) return 'no_handler';
        return r.message.isNotEmpty ? r.message : 'error';
      }
      return 'missing';
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final r = await OpenFilex.open(path);
      if (r.type == ResultType.done) return 'ok';
      if (r.type == ResultType.noAppToOpen) return 'no_handler';
      return r.message.isNotEmpty ? r.message : 'error';
    }

    final mime = lookupMimeType(path);
    final r = await OpenFilex.open(path, type: mime);
    if (r.type == ResultType.done) return 'ok';
    if (r.type == ResultType.noAppToOpen) return 'no_handler';
    return r.message.isNotEmpty ? r.message : 'error';
  }

  /// Opens the containing folder in a file manager when possible.
  static Future<String> openFolder(String path) async {
    final file = File(path);
    final dirPath = (await file.exists()) && !await FileSystemEntity.isDirectory(path)
        ? file.parent.path
        : path;

    if (Platform.isAndroid) {
      try {
        final r = await _channel.invokeMethod<String>('openFolder', {'path': dirPath});
        return r ?? 'ok';
      } catch (e) {
        debugPrint('[LocalFileActions] openFolder channel failed: $e');
        return 'error';
      }
    }

    try {
      if (Platform.isWindows) {
        if (await file.exists() && !await FileSystemEntity.isDirectory(path)) {
          await Process.run('explorer', ['/select,', path]);
        } else {
          await Process.run('explorer', [dirPath]);
        }
        return 'ok';
      }
      if (Platform.isMacOS) {
        if (await file.exists() && !await FileSystemEntity.isDirectory(path)) {
          await Process.run('open', ['-R', path]);
        } else {
          await Process.run('open', [dirPath]);
        }
        return 'ok';
      }
      if (Platform.isLinux) {
        await Process.run('xdg-open', [dirPath]);
        return 'ok';
      }
    } catch (e) {
      debugPrint('[LocalFileActions] openFolder desktop: $e');
      return 'error';
    }
    return 'unsupported';
  }
}
