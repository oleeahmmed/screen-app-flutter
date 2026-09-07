import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WhatsApp-style swipe right on a message to reply (mobile).
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  static const double _maxDrag = 78;
  static const double _trigger = 54;

  double _drag = 0;
  late final AnimationController _snap;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        if (_snap.isAnimating) {
          setState(() {});
        }
      });
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  double get _offset {
    if (_snap.isAnimating) {
      return _drag * (1 - Curves.easeOut.transform(_snap.value));
    }
    return _drag;
  }

  void _animateBack() {
    _snap.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => _drag = 0);
      _snap.reset();
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final dx = details.delta.dx;
    if (dx > 0 || _drag > 0) {
      setState(() => _drag = (_drag + dx).clamp(0.0, _maxDrag));
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_drag >= _trigger) {
      HapticFeedback.mediumImpact();
      widget.onReply();
    }
    _animateBack();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final progress = (_offset / _trigger).clamp(0.0, 1.0);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 2,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.65 + 0.35 * progress,
                child: Container(
                  width: 34,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.reply_rounded,
                    size: 22,
                    color: Color.lerp(const Color(0xFF8696A0), const Color(0xFF00A884), progress),
                  ),
                ),
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            behavior: HitTestBehavior.translucent,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
