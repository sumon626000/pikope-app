import 'package:flutter/material.dart';

import 'audio_service.dart';

/// Tap feedback: slight scale-down (matches [DuelButton] feel).
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.scale = 0.94,
    this.playTapSound = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double scale;
  final bool playTapSound;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: enabled
          ? () {
              if (widget.playTapSound) AudioService.tap();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 75),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Red dot / pill that gently pulses (notifications, challenge, daily ready).
class PulseBadge extends StatefulWidget {
  const PulseBadge({super.key, required this.child, this.minScale = 0.88, this.maxScale = 1.08});

  final Widget child;
  final double minScale;
  final double maxScale;

  @override
  State<PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<PulseBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  late final Animation<double> _scale = Tween(begin: widget.minScale, end: widget.maxScale).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    );
  }
}

/// Soft “claim me” breathing on an icon when something is ready.
class IdleAttentionScale extends StatefulWidget {
  const IdleAttentionScale({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<IdleAttentionScale> createState() => _IdleAttentionScaleState();
}

class _IdleAttentionScaleState extends State<IdleAttentionScale> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didUpdateWidget(IdleAttentionScale old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _c ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    } else if (!widget.active && old.active) {
      _c?.dispose();
      _c = null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_c == null) return widget.child;
    return AnimatedBuilder(
      animation: _c!,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_c!.value);
        final scale = 1 + 0.06 * (t - 0.5) * 2;
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}

/// One-shot pop when an action succeeds (e.g. daily claim).
class PopCelebration extends StatefulWidget {
  const PopCelebration({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<PopCelebration> createState() => _PopCelebrationState();
}

class _PopCelebrationState extends State<PopCelebration> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void didUpdateWidget(PopCelebration old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger > 0) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        final scale = t < 0.45 ? 1 + 0.18 * (t / 0.45) : 1 + 0.18 * (1 - (t - 0.45) / 0.55);
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}
