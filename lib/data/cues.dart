import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Chalk end + ferrule — identical on every cue (shop and in-game).
abstract final class CueMarkings {
  static const ring = Color(0xFFEDEDED);
  static const ferrule = Color(0xFFF5F5F5);
  static const tip = Color(0xFF5CA9E6);
}

/// Body art only; tip/ring stay shared via [CueMarkings].
enum CueBodyPattern {
  classicMaple,
  ebonyChrome,
  crimsonFlame,
  oceanRipple,
  emeraldMesh,
  royalGold,
  neonPulse,
  dragonFury,
}

/// How a cue is drawn. Cues are looks only — every cue plays the same.
class CueStyle {
  const CueStyle(
    this.id,
    this.name, {
    required this.butt,
    required this.buttLight,
    required this.wrap,
    required this.shaft,
    required this.shaftLight,
    required this.pattern,
    this.glow,
  });

  final String id;
  final String name;
  final Color butt;
  final Color buttLight;
  final Color wrap;
  final Color shaft;
  final Color shaftLight;
  final CueBodyPattern pattern;

  /// Soft aura along the cue body (special cues).
  final Color? glow;

  static const classic = CueStyle(
    'classic',
    'Classic Maple',
    butt: Color(0xFF3A1A0C),
    buttLight: Color(0xFF6B3519),
    wrap: Color(0xFFD9A860),
    shaft: Color(0xFFE9C98F),
    shaftLight: Color(0xFFF7E3BD),
    pattern: CueBodyPattern.classicMaple,
  );

  static const all = <CueStyle>[
    classic,
    CueStyle(
      'ebony',
      'Ebony Pro',
      butt: Color(0xFF0E0E12),
      buttLight: Color(0xFF3A3A46),
      wrap: Color(0xFF8E939E),
      shaft: Color(0xFFE6D2A8),
      shaftLight: Color(0xFFFFF1D2),
      pattern: CueBodyPattern.ebonyChrome,
    ),
    CueStyle(
      'crimson',
      'Crimson Flame',
      butt: Color(0xFF5E0A12),
      buttLight: Color(0xFFD2283A),
      wrap: Color(0xFF1A1A1E),
      shaft: Color(0xFFF0D9B0),
      shaftLight: Color(0xFFFFF3D8),
      pattern: CueBodyPattern.crimsonFlame,
    ),
    CueStyle(
      'ocean',
      'Ocean Wave',
      butt: Color(0xFF07305E),
      buttLight: Color(0xFF2F8BFF),
      wrap: Color(0xFFE8F4FF),
      shaft: Color(0xFFE2E9F2),
      shaftLight: Color(0xFFFFFFFF),
      pattern: CueBodyPattern.oceanRipple,
    ),
    CueStyle(
      'emerald',
      'Emerald Strike',
      butt: Color(0xFF063B24),
      buttLight: Color(0xFF22C36B),
      wrap: Color(0xFF0C0F0D),
      shaft: Color(0xFFEAD9B2),
      shaftLight: Color(0xFFFFF4D9),
      pattern: CueBodyPattern.emeraldMesh,
    ),
    CueStyle(
      'royal',
      'Royal Gold',
      butt: Color(0xFF6B4A06),
      buttLight: Color(0xFFFFD257),
      wrap: Color(0xFF2A1A52),
      shaft: Color(0xFFF6E7C1),
      shaftLight: Color(0xFFFFFAE8),
      pattern: CueBodyPattern.royalGold,
      glow: Color(0xFFFFD257),
    ),
    CueStyle(
      'neon',
      'Neon Pulse',
      butt: Color(0xFF0B0B2E),
      buttLight: Color(0xFF00E5FF),
      wrap: Color(0xFFFF2DAA),
      shaft: Color(0xFFD9F7FF),
      shaftLight: Color(0xFFFFFFFF),
      pattern: CueBodyPattern.neonPulse,
      glow: Color(0xFF00E5FF),
    ),
    CueStyle(
      'dragon',
      'Dragon Fury',
      butt: Color(0xFF2A0606),
      buttLight: Color(0xFFFF7A1A),
      wrap: Color(0xFFFFC93C),
      shaft: Color(0xFF1E1E22),
      shaftLight: Color(0xFF55555E),
      pattern: CueBodyPattern.dragonFury,
      glow: Color(0xFFFF5A1F),
    ),
  ];

  static CueStyle of(String? id) => all.firstWhere((c) => c.id == id, orElse: () => classic);
}

typedef _CueAt = Offset Function(double t);

void _paintBodyPattern(Canvas canvas, _CueAt at, Offset axis, double w, CueStyle style) {
  final unit = axis / axis.distance;
  final perp = Offset(-unit.dy, unit.dx);
  final paint = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  void along(double t0, double t1, void Function(double t, Offset p, Offset n) draw) {
    for (var i = 0; i <= 12; i++) {
      final t = t0 + (t1 - t0) * i / 12;
      draw(t, at(t), perp);
    }
  }

  switch (style.pattern) {
    case CueBodyPattern.classicMaple:
      paint.strokeWidth = w * 0.06;
      paint.color = style.buttLight.withValues(alpha: 0.55);
      for (var i = 0; i < 5; i++) {
        final t = 0.62 + i * 0.07;
        canvas.drawLine(at(t) - perp * w * 0.35, at(t) + perp * w * 0.35, paint);
      }
    case CueBodyPattern.ebonyChrome:
      paint.strokeWidth = w * 0.12;
      paint.color = const Color(0xFFB8BEC8);
      canvas.drawLine(at(0.68) - perp * w * 0.42, at(0.68) + perp * w * 0.42, paint);
      paint.strokeWidth = w * 0.05;
      paint.color = style.buttLight.withValues(alpha: 0.35);
      for (var i = 0; i < 4; i++) {
        final t = 0.72 + i * 0.06;
        canvas.drawLine(at(t) - perp * w * 0.28, at(t) + perp * w * 0.28, paint);
      }
    case CueBodyPattern.crimsonFlame:
      paint.strokeWidth = w * 0.1;
      paint.color = style.buttLight;
      along(0.32, 0.58, (t, p, n) {
        final wave = math.sin(t * 28) * w * 0.22;
        canvas.drawLine(p + n * wave - n * w * 0.15, p + n * wave + n * w * 0.15, paint);
      });
    case CueBodyPattern.oceanRipple:
      paint.strokeWidth = w * 0.08;
      paint.color = style.buttLight.withValues(alpha: 0.85);
      for (var band = 0; band < 4; band++) {
        final t = 0.64 + band * 0.08;
        canvas.drawLine(at(t) - perp * w * 0.38, at(t) + perp * w * 0.38, paint);
      }
    case CueBodyPattern.emeraldMesh:
      paint.strokeWidth = w * 0.05;
      paint.color = style.buttLight.withValues(alpha: 0.7);
      for (var i = 0; i < 6; i++) {
        final t = 0.34 + i * 0.04;
        canvas.drawLine(at(t) - perp * w * 0.32, at(t) + perp * w * 0.32, paint);
        canvas.drawLine(at(t) - unit * w * 0.2, at(t) + unit * w * 0.2, paint..strokeWidth = w * 0.04);
      }
    case CueBodyPattern.royalGold:
      paint.strokeWidth = w * 0.09;
      paint.color = style.buttLight;
      for (var i = 0; i < 5; i++) {
        final t = 0.62 + i * 0.07;
        canvas.drawLine(at(t) - perp * w * 0.4 + unit * w * 0.08, at(t) + perp * w * 0.4 - unit * w * 0.08, paint);
      }
      paint.color = style.wrap.withValues(alpha: 0.9);
      paint.strokeWidth = w * 0.14;
      canvas.drawLine(at(0.38) - perp * w * 0.35, at(0.38) + perp * w * 0.35, paint);
    case CueBodyPattern.neonPulse:
      paint.strokeWidth = w * 0.11;
      for (var i = 0; i < 4; i++) {
        final t = 0.58 + i * 0.1;
        paint.color = i.isEven ? style.buttLight : style.wrap;
        canvas.drawLine(at(t) - perp * w * 0.4, at(t) + perp * w * 0.4, paint);
      }
    case CueBodyPattern.dragonFury:
      paint.strokeWidth = w * 0.07;
      paint.color = style.wrap;
      along(0.6, 0.92, (t, p, n) {
        final r = w * 0.18;
        canvas.drawArc(Rect.fromCircle(center: p + n * r * 0.5, radius: r), 0, math.pi, false, paint);
      });
  }
}

/// Draws a cue from its tip at [tip] backwards along [back] (a unit vector).
/// [w] is the thickness unit (the table uses the ball radius).
void paintCueStick(Canvas canvas, Offset tip, Offset back, double length, double w, CueStyle style, {bool shadow = true}) {
  final axis = back * length;
  Offset at(double t) => tip + axis * t;
  void seg(double a, double b, double width, Color color, [StrokeCap cap = StrokeCap.butt]) => canvas.drawLine(
      at(a),
      at(b),
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = cap);
  if (shadow) {
    canvas.drawLine(
        at(0) + Offset(w * 0.25, w * 0.4),
        at(1) + Offset(w * 0.25, w * 0.4),
        Paint()
          ..color = const Color(0x55000000)
          ..strokeWidth = w * 0.7
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }
  final glow = style.glow;
  if (glow != null) {
    canvas.drawLine(
        at(0.02),
        at(1),
        Paint()
          ..color = glow.withValues(alpha: 0.45)
          ..strokeWidth = w * 1.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.6));
  }
  seg(0.6, 1, w * 0.72, style.butt, StrokeCap.round);
  seg(0.6, 1, w * 0.3, style.buttLight, StrokeCap.round);
  seg(0.3, 0.6, w * 0.6, style.wrap);
  seg(0.04, 0.3, w * 0.5, style.shaft);
  seg(0.04, 0.6, w * 0.16, style.shaftLight);
  _paintBodyPattern(canvas, at, axis, w, style);
  seg(0.585, 0.615, w * 0.74, CueMarkings.ring);
  seg(0.015, 0.045, w * 0.46, CueMarkings.ferrule);
  seg(0, 0.018, w * 0.42, CueMarkings.tip, StrokeCap.round);
}

/// Small cue preview for shop / items (same markings on every cue).
class CueStickPreview extends StatelessWidget {
  const CueStickPreview({super.key, required this.cueId, this.stroke = 22});

  final String cueId;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final style = CueStyle.of(cueId);
    return CustomPaint(
      painter: _CueStickPreviewPainter(style, stroke),
      child: const SizedBox.expand(),
    );
  }
}

class _CueStickPreviewPainter extends CustomPainter {
  _CueStickPreviewPainter(this.style, this.stroke);

  final CueStyle style;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final tip = Offset(size.width * 0.04, size.height * 0.72);
    final end = Offset(size.width * 0.97, size.height * 0.26);
    final v = end - tip;
    paintCueStick(canvas, tip, v / v.distance, v.distance, stroke, style);
  }

  @override
  bool shouldRepaint(_CueStickPreviewPainter old) => old.style != style || old.stroke != stroke;
}
