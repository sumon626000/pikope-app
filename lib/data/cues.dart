import 'dart:ui';

/// How a cue is drawn. Cues are looks only - every cue plays the same.
class CueStyle {
  const CueStyle(this.id, this.name,
      {required this.butt, required this.buttLight, required this.wrap, required this.shaft, required this.shaftLight,
      this.ring = const Color(0xFFEDEDED), this.tip = const Color(0xFF5CA9E6), this.glow});

  final String id;
  final String name;
  final Color butt;
  final Color buttLight;
  final Color wrap;
  final Color shaft;
  final Color shaftLight;
  final Color ring;
  final Color tip;

  /// Soft aura along the cue (special cues).
  final Color? glow;

  static const classic = CueStyle('classic', 'Classic Maple',
      butt: Color(0xFF3A1A0C), buttLight: Color(0xFF6B3519), wrap: Color(0xFFD9A860),
      shaft: Color(0xFFE9C98F), shaftLight: Color(0xFFF7E3BD));

  static const all = <CueStyle>[
    classic,
    CueStyle('ebony', 'Ebony Pro',
        butt: Color(0xFF0E0E12), buttLight: Color(0xFF3A3A46), wrap: Color(0xFF8E939E),
        shaft: Color(0xFFE6D2A8), shaftLight: Color(0xFFFFF1D2), ring: Color(0xFFC9CED6)),
    CueStyle('crimson', 'Crimson Flame',
        butt: Color(0xFF5E0A12), buttLight: Color(0xFFD2283A), wrap: Color(0xFF1A1A1E),
        shaft: Color(0xFFF0D9B0), shaftLight: Color(0xFFFFF3D8), ring: Color(0xFFFFC93C), tip: Color(0xFFFF6B5C)),
    CueStyle('ocean', 'Ocean Wave',
        butt: Color(0xFF07305E), buttLight: Color(0xFF2F8BFF), wrap: Color(0xFFE8F4FF),
        shaft: Color(0xFFE2E9F2), shaftLight: Color(0xFFFFFFFF), ring: Color(0xFF7FD4FF)),
    CueStyle('emerald', 'Emerald Strike',
        butt: Color(0xFF063B24), buttLight: Color(0xFF22C36B), wrap: Color(0xFF0C0F0D),
        shaft: Color(0xFFEAD9B2), shaftLight: Color(0xFFFFF4D9), ring: Color(0xFFFFD86B), tip: Color(0xFF6BE39C)),
    CueStyle('royal', 'Royal Gold',
        butt: Color(0xFF6B4A06), buttLight: Color(0xFFFFD257), wrap: Color(0xFF2A1A52),
        shaft: Color(0xFFF6E7C1), shaftLight: Color(0xFFFFFAE8), ring: Color(0xFFFFFFFF), tip: Color(0xFFB98BFF),
        glow: Color(0xFFFFD257)),
    CueStyle('neon', 'Neon Pulse',
        butt: Color(0xFF0B0B2E), buttLight: Color(0xFF00E5FF), wrap: Color(0xFFFF2DAA),
        shaft: Color(0xFFD9F7FF), shaftLight: Color(0xFFFFFFFF), ring: Color(0xFFFF2DAA), tip: Color(0xFF00E5FF),
        glow: Color(0xFF00E5FF)),
    CueStyle('dragon', 'Dragon Fury',
        butt: Color(0xFF2A0606), buttLight: Color(0xFFFF7A1A), wrap: Color(0xFFFFC93C),
        shaft: Color(0xFF1E1E22), shaftLight: Color(0xFF55555E), ring: Color(0xFFFF3B1F), tip: Color(0xFFFF3B1F),
        glow: Color(0xFFFF5A1F)),
  ];

  static CueStyle of(String? id) => all.firstWhere((c) => c.id == id, orElse: () => classic);
}

/// Draws a cue from its tip at [tip] backwards along [back] (a unit vector).
/// [w] is the thickness unit (the table uses the ball radius).
void paintCueStick(Canvas canvas, Offset tip, Offset back, double length, double w, CueStyle style, {bool shadow = true}) {
  Offset at(double t) => tip + back * (length * t);
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
  // Shaft tapers toward the tip; butt with a wrap and a joint ring.
  seg(0.6, 1, w * 0.72, style.butt, StrokeCap.round);
  seg(0.6, 1, w * 0.3, style.buttLight, StrokeCap.round);
  seg(0.3, 0.6, w * 0.6, style.wrap);
  seg(0.04, 0.3, w * 0.5, style.shaft);
  seg(0.04, 0.6, w * 0.16, style.shaftLight);
  seg(0.585, 0.615, w * 0.74, style.ring);
  seg(0.015, 0.045, w * 0.46, const Color(0xFFF5F5F5));
  seg(0, 0.018, w * 0.42, style.tip, StrokeCap.round);
}
