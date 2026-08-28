import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pulsing glow border for active work / break stat cards.
class AnimatedGlowBorder extends StatefulWidget {
  final Widget child;
  final bool active;
  final Color color;
  final double borderRadius;

  const AnimatedGlowBorder({
    super.key,
    required this.child,
    required this.active,
    required this.color,
    this.borderRadius = 12,
  });

  @override
  State<AnimatedGlowBorder> createState() => _AnimatedGlowBorderState();
}

class _AnimatedGlowBorderState extends State<AnimatedGlowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AnimatedGlowBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.active) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final wave = 0.45 + 0.55 * _pulse.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius + 3),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.35 + 0.55 * wave),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.18 + 0.32 * wave),
                blurRadius: 10 + 14 * wave,
                spreadRadius: 0.5 + wave,
              ),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Larger animated frame for the status illustration below quick actions.
class AnimatedStatusFrame extends StatefulWidget {
  final Widget child;
  final bool active;
  final Color color;

  const AnimatedStatusFrame({
    super.key,
    required this.child,
    required this.active,
    required this.color,
  });

  @override
  State<AnimatedStatusFrame> createState() => _AnimatedStatusFrameState();
}

class _AnimatedStatusFrameState extends State<AnimatedStatusFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AnimatedStatusFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.active) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _spin,
      builder: (context, child) {
        final angle = _spin.value * 2 * math.pi;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: SweepGradient(
              center: Alignment.center,
              startAngle: angle,
              colors: [
                widget.color.withValues(alpha: 0.05),
                widget.color.withValues(alpha: 0.75),
                widget.color.withValues(alpha: 0.25),
                widget.color.withValues(alpha: 0.05),
              ],
              stops: const [0.0, 0.35, 0.65, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.22),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.all(2.5),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
