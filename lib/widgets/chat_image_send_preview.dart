import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Result from the WhatsApp-style image send preview.
class ChatImageSendResult {
  final Uint8List bytes;
  final String caption;

  const ChatImageSendResult({required this.bytes, required this.caption});
}

/// In-app image clipboard (copy from chat → paste in composer).
abstract final class InAppImageClipboard {
  static Uint8List? bytes;
  static String filename = 'image.jpg';

  static void store(Uint8List data, {String name = 'image.jpg'}) {
    bytes = data;
    filename = name;
  }

  static void clear() {
    bytes = null;
    filename = 'image.jpg';
  }
}

/// Full-screen image preview before sending (WhatsApp-style).
class ChatImageSendPreview extends StatefulWidget {
  final Uint8List imageBytes;
  final String recipientName;

  const ChatImageSendPreview({
    super.key,
    required this.imageBytes,
    required this.recipientName,
  });

  static Future<ChatImageSendResult?> open(
    BuildContext context, {
    required Uint8List imageBytes,
    required String recipientName,
  }) {
    return Navigator.of(context).push<ChatImageSendResult>(
      PageRouteBuilder(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => ChatImageSendPreview(
          imageBytes: imageBytes,
          recipientName: recipientName,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<ChatImageSendPreview> createState() => _ChatImageSendPreviewState();
}

class _ChatImageSendPreviewState extends State<ChatImageSendPreview> {
  final _captionCtrl = TextEditingController();
  final _captionFocus = FocusNode();
  bool _sending = false;

  static const _waGreen = Color(0xFF00A884);
  static const _bg = Color(0xFF0B141A);
  static const _bar = Color(0xFF1F2C34);
  static const _input = Color(0xFF2A3942);

  @override
  void dispose() {
    _captionCtrl.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  void _close() {
    if (_sending) return;
    Navigator.of(context).pop();
  }

  void _send() {
    if (_sending) return;
    setState(() => _sending = true);
    Navigator.of(context).pop(
      ChatImageSendResult(
        bytes: widget.imageBytes,
        caption: _captionCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.85,
            maxScale: 4,
            child: Center(
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withValues(alpha: 0.72),
                  Colors.transparent,
                ],
              ),
            ),
            child: const SizedBox(height: 120, width: double.infinity),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  Colors.transparent,
                ],
              ),
            ),
            child: const SizedBox(height: 200, width: double.infinity),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _close,
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {},
                        icon: Icon(Icons.crop_rotate_rounded, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: Icon(Icons.emoji_emotions_outlined, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                      IconButton(
                        onPressed: () => _captionFocus.requestFocus(),
                        icon: Icon(Icons.title_rounded, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: Icon(Icons.edit_rounded, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(color: _bar),
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _input,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_rounded, size: 14, color: Colors.white.withValues(alpha: 0.7)),
                            const SizedBox(width: 6),
                            Text(
                              widget.recipientName,
                              style: const TextStyle(
                                color: Color(0xFFE9EDEF),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 44, maxHeight: 120),
                              decoration: BoxDecoration(
                                color: _input,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: TextField(
                                controller: _captionCtrl,
                                focusNode: _captionFocus,
                                maxLines: 4,
                                minLines: 1,
                                textCapitalization: TextCapitalization.sentences,
                                style: const TextStyle(color: Color(0xFFE9EDEF), fontSize: 16),
                                decoration: const InputDecoration(
                                  hintText: 'Add a caption…',
                                  hintStyle: TextStyle(color: Color(0xFF8696A0), fontSize: 16),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: _waGreen,
                            shape: const CircleBorder(),
                            elevation: 4,
                            shadowColor: _waGreen.withValues(alpha: 0.45),
                            child: InkWell(
                              onTap: _send,
                              customBorder: const CircleBorder(),
                              child: SizedBox(
                                width: 50,
                                height: 50,
                                child: _sending
                                    ? const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
