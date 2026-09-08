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
    final accent = state.isSender ? const Color(0xFF6366F1) : const Color(0xFF22C55E);

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2C34),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    isComplete ? LucideIcons.checkCircle2 : LucideIcons.zap,
                    color: accent,
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
                            : (isComplete ? 'Sent directly' : 'Direct transfer'),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.peerName.isNotEmpty ? state.peerName : 'Peer',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!isComplete && !isFailed && onCancel != null)
                  IconButton(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(LucideIcons.file, size: 16, color: accent),
                const SizedBox(width: 8),
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
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
            if (isTransferring || isComplete) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: isComplete ? 1 : state.progress.clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  color: accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.statusText,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ] else if (!isIncoming) ...[
              const SizedBox(height: 8),
              Text(
                state.statusText,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
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
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
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
                  backgroundColor: accent.withValues(alpha: 0.85),
                  foregroundColor: Colors.white,
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
    );
  }
}
