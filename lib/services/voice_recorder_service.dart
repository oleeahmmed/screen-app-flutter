import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Voice recording for chat — Android/iOS via [record], Windows via external script.
class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  String? get currentPath => _path;

  Future<bool> start() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;

    if (!await _recorder.hasPermission()) return false;

    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}${Platform.pathSeparator}voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _path!,
    );
    _isRecording = true;
    return true;
  }

  Future<String?> stop() async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    return path ?? _path;
  }

  Future<void> cancel() async {
    if (_isRecording) {
      await _recorder.stop();
      _isRecording = false;
    }
    final p = _path;
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    _path = null;
  }

  void dispose() {
    _recorder.dispose();
  }
}
