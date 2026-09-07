import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';
import '../utils/local_file_actions.dart';
import '../utils/platform_capabilities.dart';

/// WhatsApp-style fullscreen chat image viewer with reply / forward / delete / save.
class ChatImageViewer extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;
  final Future<void> Function(Map<String, dynamic> msg)? onReply;
  final Future<void> Function(Map<String, dynamic> msg)? onForward;
  final Future<void> Function(Map<String, dynamic> msg)? onDelete;
  final void Function(Map<String, dynamic> msg)? onInfo;
  final Future<void> Function(String url)? onOpenExternal;

  const ChatImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.onReply,
    this.onForward,
    this.onDelete,
    this.onInfo,
    this.onOpenExternal,
  });

  static Future<void> open(
    BuildContext context, {
    required List<Map<String, dynamic>> images,
    int initialIndex = 0,
    Future<void> Function(Map<String, dynamic> msg)? onReply,
    Future<void> Function(Map<String, dynamic> msg)? onForward,
    Future<void> Function(Map<String, dynamic> msg)? onDelete,
    void Function(Map<String, dynamic> msg)? onInfo,
    Future<void> Function(String url)? onOpenExternal,
  }) {
    if (images.isEmpty) return Future.value();
    final i = initialIndex.clamp(0, images.length - 1);
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ChatImageViewer(
          images: images,
          initialIndex: i,
          onReply: onReply,
          onForward: onForward,
          onDelete: onDelete,
          onInfo: onInfo,
          onOpenExternal: onOpenExternal,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  State<ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<ChatImageViewer> {
  late final PageController _pageController;
  late int _index;
  bool _uiVisible = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _index);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _current => widget.images[_index];

  String get _url => (_current['image_url'] ?? '').toString();

  String get _caption => (_current['message'] ?? '').toString().trim();

  String get _sender {
    if (_current['is_own'] == true) return 'You';
    return (_current['sender_name'] ??
            _current['sender_full_name'] ??
            _current['sender_username'] ??
            'Photo')
        .toString();
  }

  String get _time {
    final raw = (_current['timestamp'] ?? _current['created_at'] ?? '').toString();
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  bool get _isOwn => _current['is_own'] == true;

  Future<void> _runBusy(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCurrent() async {
    final url = _url;
    if (url.isEmpty) return;
    await _runBusy(() async {
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not download image')),
          );
        }
        return;
      }
      final name = 'aims_chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await LocalFileActions.saveImageToGallery(
        Uint8List.fromList(resp.bodyBytes),
        name,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              PlatformCapabilities.isDesktop ? 'Image saved' : 'Saved to gallery',
            ),
          ),
        );
      }
    });
  }

  Future<void> _confirmDelete() async {
    if (!_isOwn || widget.onDelete == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this photo?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This message will be deleted for everyone in the chat.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final msg = Map<String, dynamic>.from(_current);
    Navigator.pop(context);
    await widget.onDelete!(msg);
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final enabled = onTap != null && !_busy;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: enabled ? (color ?? Colors.white) : Colors.white38),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white.withValues(alpha: 0.9) : Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: count,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final url = (widget.images[i]['image_url'] ?? '').toString();
              return GestureDetector(
                onTap: () => setState(() => _uiVisible = !_uiVisible),
                child: InteractiveViewer(
                  minScale: 0.6,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (c, child, p) {
                        if (p == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white70),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined, color: Colors.white38, size: 56),
                          SizedBox(height: 8),
                          Text('Could not load image', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedOpacity(
            opacity: _uiVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_uiVisible,
              child: SafeArea(
                child: Column(
                  children: [
                    Material(
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _sender,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_time.isNotEmpty)
                                    Text(
                                      count > 1 ? '$_time · ${_index + 1}/$count' : _time,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (_busy)
                              const Padding(
                                padding: EdgeInsets.only(right: 12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            IconButton(
                              tooltip: 'More',
                              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                              onPressed: () async {
                                final action = await showModalBottomSheet<String>(
                                  context: context,
                                  backgroundColor: AppTheme.dialogBg,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                  ),
                                  builder: (_) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.open_in_new_rounded, color: AppTheme.primary),
                                          title: const Text('Open externally', style: TextStyle(color: AppTheme.textPrimary)),
                                          onTap: () => Navigator.pop(context, 'open'),
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.info_outline_rounded, color: AppTheme.textMuted),
                                          title: const Text('Message info', style: TextStyle(color: AppTheme.textPrimary)),
                                          onTap: () => Navigator.pop(context, 'info'),
                                        ),
                                        if (_caption.isNotEmpty)
                                          ListTile(
                                            leading: const Icon(Icons.copy_rounded, color: AppTheme.textMuted),
                                            title: const Text('Copy caption', style: TextStyle(color: AppTheme.textPrimary)),
                                            onTap: () => Navigator.pop(context, 'copy'),
                                          ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                );
                                if (!mounted || action == null) return;
                                final msg = Map<String, dynamic>.from(_current);
                                switch (action) {
                                  case 'open':
                                    if (widget.onOpenExternal != null) {
                                      await widget.onOpenExternal!(_url);
                                    }
                                    break;
                                  case 'info':
                                    widget.onInfo?.call(msg);
                                    break;
                                  case 'copy':
                                    await Clipboard.setData(ClipboardData(text: _caption));
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Caption copied')),
                                      );
                                    }
                                    break;
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_caption.isNotEmpty)
                      Container(
                        width: double.infinity,
                        color: Colors.black.withValues(alpha: 0.45),
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                        child: Text(
                          _caption,
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Material(
                      color: Colors.black.withValues(alpha: 0.72),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _action(
                              icon: Icons.reply_rounded,
                              label: 'Reply',
                              onTap: widget.onReply == null
                                  ? null
                                  : () async {
                                      final msg = Map<String, dynamic>.from(_current);
                                      Navigator.pop(context);
                                      await widget.onReply!(msg);
                                    },
                            ),
                            _action(
                              icon: Icons.shortcut_rounded,
                              label: 'Forward',
                              color: AppTheme.accent,
                              onTap: widget.onForward == null
                                  ? null
                                  : () async {
                                      final msg = Map<String, dynamic>.from(_current);
                                      Navigator.pop(context);
                                      await widget.onForward!(msg);
                                    },
                            ),
                            _action(
                              icon: Icons.download_rounded,
                              label: 'Save',
                              onTap: _saveCurrent,
                            ),
                            if (_isOwn && widget.onDelete != null)
                              _action(
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete',
                                color: AppTheme.danger,
                                onTap: _confirmDelete,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
