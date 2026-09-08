import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/chat_p2p_file_service.dart';
import '../theme/app_theme.dart';

/// Premium in-chat overlay for P2P file send/receive progress.
class ChatP2pTransferSheet extends StatelessWidget {
  final ChatP2pTransferState state;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenFile;

  const ChatP2pTransferSheet({
    super.key,
    required this.state,
    this.onAccept,
    this.onReject,
    this.onCancel,
    this.onOpenFile,
  });

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isIncoming = state.phase == ChatP2pPhase.incoming;
    final isTransferring = state.phase == ChatP2pPhase.transferring;
    final isComplete = state.phase == ChatP2pPhase.complete;
    final isFailed = state.phase == ChatP2pPhase.failed;
    final accent = state.isSender ? AppTheme.primaryBright : const Color(0xFF22C55E);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.glassSurfaceDecoration(borderRadius: 20, elevated: true),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.9),
                          (state.isSender ? AppTheme.primary : const Color(0xFF10B981)).withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                    child: Icon(
                      isComplete ? LucideIcons.checkCircle2 : (isIncoming ? LucideIcons.download : LucideIcons.upload),
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isIncoming
                              ? 'Incoming file'
                              : (isComplete ? 'Transfer complete' : 'Direct transfer'),
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.peerName.isNotEmpty ? state.peerName : 'Peer',
                          style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (!isComplete && !isFailed && onCancel != null)
                    IconButton(
                      onPressed: onCancel,
                      icon: Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.9)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: AppTheme.loginInsetDecoration(borderRadius: 12),
                child: Row(
                  children: [
                    Icon(LucideIcons.file, size: 18, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      _fmtSize(state.fileSize),
                      style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isTransferring || isComplete) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: isComplete ? 1 : state.progress.clamp(0, 1),
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    color: accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  state.statusText,
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
                ),
              ] else if (!isIncoming) ...[
                const SizedBox(height: 8),
                Text(
                  state.statusText,
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
                ),
              ],
              if (isIncoming) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textMuted,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: onAccept,
                        icon: const Icon(LucideIcons.download, size: 18),
                        label: const Text('Receive'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (isComplete && state.savedPath != null && onOpenFile != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onOpenFile,
                  icon: const Icon(LucideIcons.folderOpen, size: 18),
                  label: const Text('Open file'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              if (isFailed) ...[
                const SizedBox(height: 8),
                Text(
                  state.error ?? 'Transfer failed',
                  style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
