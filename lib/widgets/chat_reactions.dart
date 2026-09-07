import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WhatsApp-style message reactions (picker overlay + compact badge).
abstract final class ChatReactions {
  static const quick = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  static const _barBg = Color(0xFF233138);
  static const _barBorder = Color(0xFF3B4A54);
  static const _badgeBg = Color(0xFF1A262D);
  static const _badgeBorder = Color(0xFF2F3B43);

  static TextStyle emojiStyle(double size) => TextStyle(
        fontSize: size,
        height: 1.0,
        leadingDistribution: TextLeadingDistribution.even,
      );

  static Future<void> showPicker({
    required BuildContext context,
    required BuildContext anchorContext,
    required ValueChanged<String> onPick,
    List<String> extraEmojis = const [],
    double topBarrierInset = 0,
    VoidCallback? onDismiss,
  }) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final overlay = Overlay.of(anchorContext, rootOverlay: true);
    final topLeft = box.localToGlobal(Offset.zero);
    final bubbleSize = box.size;
    var showMore = false;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final screen = MediaQuery.sizeOf(ctx);
        const emojiSize = 34.0;
        const itemSize = 44.0;
        const gap = 2.0;
        const plusSize = 40.0;
        const hPad = 8.0;
        const vPad = 6.0;

        final quickCount = quick.length + 1;
        final barW = hPad * 2 + (quickCount * itemSize) + ((quickCount - 1) * gap);
        final left = (topLeft.dx + bubbleSize.width / 2 - barW / 2).clamp(10.0, screen.width - barW - 10);

        var top = topLeft.dy - 58;
        if (top < MediaQuery.paddingOf(ctx).top + 8) {
          top = topLeft.dy + bubbleSize.height + 10;
        }
        top = top.clamp(8.0, screen.height - 120);

        Widget emojiBtn(String emoji, {VoidCallback? onTap}) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              splashColor: Colors.white.withValues(alpha: 0.12),
              highlightColor: Colors.white.withValues(alpha: 0.06),
              child: SizedBox(
                width: itemSize,
                height: itemSize,
                child: Center(
                  child: Text(emoji, style: emojiStyle(emojiSize)),
                ),
              ),
            ),
          );
        }

        final moreRow = showMore && extraEmojis.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      constraints: BoxConstraints(maxWidth: screen.width - 24),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: _barBg.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _barBorder, width: 0.6),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: extraEmojis.take(24).map((e) => emojiBtn(e, onTap: () {
                            entry.remove();
                            HapticFeedback.selectionClick();
                            onPick(e);
                          })).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink();

        void dismiss() {
          entry.remove();
          onDismiss?.call();
        }

        final barrier = GestureDetector(
          onTap: dismiss,
          behavior: HitTestBehavior.opaque,
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
        );

        return Stack(
          children: [
            if (topBarrierInset > 0)
              Positioned(
                top: topBarrierInset,
                left: 0,
                right: 0,
                bottom: 0,
                child: barrier,
              )
            else
              Positioned.fill(child: barrier),
            Positioned(
              left: left,
              top: top,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Material(
                        elevation: 8,
                        shadowColor: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(28),
                        color: _barBg.withValues(alpha: 0.97),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: _barBorder, width: 0.6),
                          ),
                          padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < quick.length; i++) ...[
                                if (i > 0) SizedBox(width: gap),
                                emojiBtn(quick[i], onTap: () {
                                  entry.remove();
                                  HapticFeedback.selectionClick();
                                  onPick(quick[i]);
                                }),
                              ],
                              SizedBox(width: gap),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    if (extraEmojis.isEmpty) return;
                                    showMore = !showMore;
                                    entry.markNeedsBuild();
                                  },
                                  customBorder: const CircleBorder(),
                                  child: Container(
                                    width: plusSize,
                                    height: plusSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: showMore
                                          ? const Color(0xFF00A884).withValues(alpha: 0.25)
                                          : Colors.white.withValues(alpha: 0.08),
                                      border: Border.all(
                                        color: showMore
                                            ? const Color(0xFF00A884).withValues(alpha: 0.5)
                                            : Colors.white.withValues(alpha: 0.12),
                                      ),
                                    ),
                                    child: Icon(
                                      showMore ? Icons.close_rounded : Icons.add_rounded,
                                      size: 22,
                                      color: showMore ? const Color(0xFF00A884) : Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  moreRow,
                ],
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  }

  static Widget badge({
    required List<dynamic> reactions,
    required bool isOwn,
    required void Function(String emoji) onTap,
    VoidCallback? onBadgeTap,
  }) {
    final items = <({String emoji, int count, bool mine})>[];
    for (final r in reactions) {
      if (r is! Map) continue;
      final emoji = (r['emoji'] ?? '').toString();
      if (emoji.isEmpty) continue;
      final count = r['count'] is int
          ? r['count'] as int
          : int.tryParse('${r['count']}') ?? 1;
      items.add((
        emoji: emoji,
        count: count,
        mine: r['reacted_by_me'] == true,
      ));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    final mineAny = items.any((e) => e.mine);
    final total = items.fold<int>(0, (s, e) => s + e.count);

    return GestureDetector(
      onTap: onBadgeTap,
      child: Material(
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        color: mineAny ? const Color(0xFF0B3D34) : _badgeBg,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: mineAny ? const Color(0xFF00A884).withValues(alpha: 0.45) : _badgeBorder,
              width: 0.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length && i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                GestureDetector(
                  onTap: () => onTap(items[i].emoji),
                  child: Text(items[i].emoji, style: emojiStyle(15)),
                ),
              ],
              if (total > 1 || items.length > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '$total',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    color: mineAny
                        ? const Color(0xFF06CF9C)
                        : Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
