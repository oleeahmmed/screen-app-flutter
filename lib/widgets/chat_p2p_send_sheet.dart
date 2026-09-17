import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../utils/platform_capabilities.dart';
import 'premium_glass.dart';

class ChatP2pPendingFile {
  final String path;
  final String name;
  final int size;

  const ChatP2pPendingFile({
    required this.path,
    required this.name,
    required this.size,
  });
}

/// Compose sheet: pick / drag multiple files, then start P2P send to [peerName].
Future<List<ChatP2pPendingFile>?> showChatP2pSendSheet({
  required BuildContext context,
  required String peerName,
}) {
  return PremiumGlass.showSheet<List<ChatP2pPendingFile>>(
    context: context,
    builder: (ctx) => _ChatP2pSendSheet(peerName: peerName),
  );
}

class _ChatP2pSendSheet extends StatefulWidget {
  final String peerName;

  const _ChatP2pSendSheet({required this.peerName});

  @override
  State<_ChatP2pSendSheet> createState() => _ChatP2pSendSheetState();
}

class _ChatP2pSendSheetState extends State<_ChatP2pSendSheet> {
  final List<ChatP2pPendingFile> _files = [];
  bool _dragOver = false;

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _addFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    for (final pf in result.files) {
      final path = pf.path;
      if (path == null || path.isEmpty) continue;
      var size = pf.size;
      if (size <= 0) {
        try {
          size = await File(path).length();
        } catch (_) {
          size = 0;
        }
      }
      _files.removeWhere((f) => f.path == path);
      _files.add(ChatP2pPendingFile(path: path, name: pf.name, size: size));
    }
    if (mounted) setState(() {});
  }

  Future<void> _addDropped(List<XFile> dropped) async {
    for (final x in dropped) {
      final path = x.path;
      if (path.isEmpty) continue;
      var size = 0;
      try {
        size = await File(path).length();
      } catch (_) {}
      final name = x.name.isNotEmpty ? x.name : path.split(Platform.pathSeparator).last;
      _files.removeWhere((f) => f.path == path);
      _files.add(ChatP2pPendingFile(path: path, name: name, size: size));
    }
    if (mounted) setState(() {});
  }

  Widget _dropZone(Widget child) {
    if (!PlatformCapabilities.fileDragDrop) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragOver = true),
      onDragExited: (_) => setState(() => _dragOver = false),
      onDragDone: (details) async {
        setState(() => _dragOver = false);
        await _addDropped(details.files);
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _dropZone(
      PremiumGlass.sheetBody(
        context: context,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PremiumGlass.handle(),
              PremiumGlass.header(
                icon: Icons.bolt_rounded,
                title: 'Send files (P2P)',
                subtitle: 'To ${widget.peerName}',
                accentColor: const Color(0xFF818CF8),
                onClose: () => Navigator.pop(context),
              ),
              const SizedBox(height: 14),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _addFromPicker,
                  borderRadius: BorderRadius.circular(14),
                  child: PremiumGlass.insetRow(
                    padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
                    child: Column(
                      children: [
                        Icon(
                          LucideIcons.uploadCloud,
                          size: 28,
                          color: _dragOver
                              ? const Color(0xFF818CF8)
                              : const Color(0xFF818CF8).withValues(alpha: 0.95),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          PlatformCapabilities.fileDragDrop
                              ? 'Tap to add files · or drag & drop'
                              : 'Tap to add files',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Multiple files supported',
                          style: TextStyle(
                            color: AppTheme.textMuted.withValues(alpha: 0.85),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_files.isNotEmpty) ...[
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _files.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final f = _files[i];
                      return PremiumGlass.insetRow(
                        child: Row(
                          children: [
                            const Icon(LucideIcons.file, size: 18, color: Color(0xFF818CF8)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  Text(
                                    _fmtSize(f.size),
                                    style: TextStyle(
                                      color: AppTheme.textMuted.withValues(alpha: 0.85),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _files.removeAt(i)),
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppTheme.textMuted.withValues(alpha: 0.8),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ] else
                const SizedBox(height: 12),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _files.isEmpty
                    ? null
                    : () => Navigator.pop(context, List<ChatP2pPendingFile>.from(_files)),
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: Text(
                  _files.isEmpty
                      ? 'Add files to send'
                      : 'Send ${_files.length} file${_files.length == 1 ? '' : 's'}',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
