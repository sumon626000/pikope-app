import 'dart:math';

import 'package:flutter/material.dart';

/// Looks of the striker, the piece sets and the boards the player can pick in
/// the Carrom lobby. Purely visual: physics never changes.
class StrikerSkin {
  const StrikerSkin(this.id, this.name, {required this.base, required this.edge, required this.accent, this.mark = StrikerMark.star});

  final String id;
  final String name;
  final Color base;
  final Color edge;
  final Color accent;
  final StrikerMark mark;
}

enum StrikerMark { star, ring, dots, bolt, flame }

class PieceSkin {
  const PieceSkin(this.id, this.name, {required this.light, required this.lightEdge, required this.dark, required this.darkEdge, required this.queen, required this.queenEdge});

  final String id;
  final String name;

  /// Seat 0's pieces ("white").
  final Color light;
  final Color lightEdge;

  /// Seat 1's pieces ("black").
  final Color dark;
  final Color darkEdge;
  final Color queen;
  final Color queenEdge;
}

const strikerSkins = [
  StrikerSkin('classic', 'CLASSIC', base: Color(0xFFE53935), edge: Color(0xFF8E1B16), accent: Colors.white),
  StrikerSkin('ocean', 'OCEAN', base: Color(0xFF1E88E5), edge: Color(0xFF0D3C78), accent: Color(0xFFBFE9FF), mark: StrikerMark.ring),
  StrikerSkin('gold', 'GOLD', base: Color(0xFFF2B824), edge: Color(0xFF8A5A00), accent: Color(0xFFFFF6CC)),
  StrikerSkin('emerald', 'EMERALD', base: Color(0xFF2EBD5B), edge: Color(0xFF0F5A2A), accent: Color(0xFFDFFFE8), mark: StrikerMark.dots),
  StrikerSkin('storm', 'STORM', base: Color(0xFF3B3F4A), edge: Color(0xFF0E1015), accent: Color(0xFFFFD54A), mark: StrikerMark.bolt),
  StrikerSkin('inferno', 'INFERNO', base: Color(0xFFFF6D00), edge: Color(0xFF7A2600), accent: Color(0xFFFFF176), mark: StrikerMark.flame),
  StrikerSkin('violet', 'VIOLET', base: Color(0xFF8E44AD), edge: Color(0xFF3F1457), accent: Color(0xFFF3D9FF), mark: StrikerMark.ring),
  StrikerSkin('ivory', 'IVORY', base: Color(0xFFF5EBDD), edge: Color(0xFFA38A6A), accent: Color(0xFFC62828)),
];

const pieceSkins = [
  PieceSkin('classic', 'CLASSIC', light: Color(0xFFEFE3D2), lightEdge: Color(0xFFB9A58C), dark: Color(0xFF2C2F33), darkEdge: Color(0xFF0D0E10), queen: Color(0xFFE53935), queenEdge: Color(0xFF8E1B16)),
  PieceSkin('walnut', 'WALNUT', light: Color(0xFFE8C9A0), lightEdge: Color(0xFFA67B4D), dark: Color(0xFF4A2C1A), darkEdge: Color(0xFF21110A), queen: Color(0xFFC62828), queenEdge: Color(0xFF6E1111)),
  PieceSkin('marble', 'MARBLE', light: Color(0xFFF4F4F6), lightEdge: Color(0xFFB4B8C4), dark: Color(0xFF1F2A44), darkEdge: Color(0xFF0B1020), queen: Color(0xFFD81B60), queenEdge: Color(0xFF7B0E36)),
  PieceSkin('neon', 'NEON', light: Color(0xFF7FFFD4), lightEdge: Color(0xFF1C8C6E), dark: Color(0xFF3D1A66), darkEdge: Color(0xFF160826), queen: Color(0xFFFF4081), queenEdge: Color(0xFF8E0A3F)),
  PieceSkin('royal', 'ROYAL', light: Color(0xFFFFE9A8), lightEdge: Color(0xFFB8860B), dark: Color(0xFF1B3A6B), darkEdge: Color(0xFF081A36), queen: Color(0xFFB71C1C), queenEdge: Color(0xFF5A0A0A)),
];

/// Look of the board itself: playfield wood, frame, corner caps, lane lines.
class BoardSkin {
  const BoardSkin(this.id, this.name, {required this.wood, required this.woodLight, required this.woodDark, required this.frame, required this.frameLight, required this.frameDark, required this.corner, required this.cornerLight, required this.cornerDark, required this.line, this.lineLight = const Color(0x47FFFFFF), this.grainLight = const Color(0x2EFFFFFF)});

  final String id;
  final String name;
  final Color wood;
  final Color woodLight;
  final Color woodDark;
  final Color frame;
  final Color frameLight;
  final Color frameDark;

  /// Corner caps and the filled circles at the lane ends.
  final Color corner;
  final Color cornerLight;
  final Color cornerDark;

  /// Engraved markings.
  final Color line;

  /// Light edge of the engraving and of the wood grain.
  final Color lineLight;
  final Color grainLight;
}

const boardSkins = [
  BoardSkin('classic', 'CLASSIC', wood: Color(0xFFE6BE8C), woodLight: Color(0xFFF1D1A6), woodDark: Color(0xFFC99A66), frame: Color(0xFF4E2E22), frameLight: Color(0xFF7A4A36), frameDark: Color(0xFF26130B), corner: Color(0xFFE2B33C), cornerLight: Color(0xFFFFEBA6), cornerDark: Color(0xFFA8761A), line: Color(0xFF9C5A33)),
  BoardSkin('walnut', 'WALNUT', wood: Color(0xFF9E6B3E), woodLight: Color(0xFFB8835A), woodDark: Color(0xFF7A4D27), frame: Color(0xFF2E1A10), frameLight: Color(0xFF4A2C1C), frameDark: Color(0xFF160A04), corner: Color(0xFFE8B84A), cornerLight: Color(0xFFFFD979), cornerDark: Color(0xFFB8882A), line: Color(0xFF3E2210), lineLight: Color(0x33FFE0B0)),
  BoardSkin('royal', 'ROYAL', wood: Color(0xFF1F3F7A), woodLight: Color(0xFF2C529A), woodDark: Color(0xFF152C58), frame: Color(0xFF3A2A12), frameLight: Color(0xFF5C4420), frameDark: Color(0xFF1C1206), corner: Color(0xFFF2C14E), cornerLight: Color(0xFFFFE08A), cornerDark: Color(0xFFBF8F22), line: Color(0xFFE7C66A), lineLight: Color(0x2AFFFFFF), grainLight: Color(0x1AFFFFFF)),
  BoardSkin('emerald', 'EMERALD', wood: Color(0xFF1E6B3A), woodLight: Color(0xFF2A8A4C), woodDark: Color(0xFF154D2A), frame: Color(0xFF2A1A12), frameLight: Color(0xFF4A3020), frameDark: Color(0xFF120A05), corner: Color(0xFFF2B824), cornerLight: Color(0xFFFFD95A), cornerDark: Color(0xFFBD8A10), line: Color(0xFFF3E6B0), lineLight: Color(0x22FFFFFF), grainLight: Color(0x18FFFFFF)),
  BoardSkin('cherry', 'CHERRY', wood: Color(0xFFC8744A), woodLight: Color(0xFFDC8F66), woodDark: Color(0xFFA2522E), frame: Color(0xFF3B1E14), frameLight: Color(0xFF5E3324), frameDark: Color(0xFF1C0C06), corner: Color(0xFFFFC857), cornerLight: Color(0xFFFFE2A0), cornerDark: Color(0xFFD39A2B), line: Color(0xFF5A2410)),
  BoardSkin('midnight', 'MIDNIGHT', wood: Color(0xFF1C1E26), woodLight: Color(0xFF2A2D38), woodDark: Color(0xFF111218), frame: Color(0xFF0C0D12), frameLight: Color(0xFF262833), frameDark: Color(0xFF040405), corner: Color(0xFF26E0C8), cornerLight: Color(0xFF8AFFF0), cornerDark: Color(0xFF0E9C8A), line: Color(0xFF3CF0D8), lineLight: Color(0x2026E0C8), grainLight: Color(0x12FFFFFF)),
];

BoardSkin boardSkinOf(String id) => boardSkins.firstWhere((s) => s.id == id, orElse: () => boardSkins.first);
StrikerSkin strikerSkinOf(String id) => strikerSkins.firstWhere((s) => s.id == id, orElse: () => strikerSkins.first);
PieceSkin pieceSkinOf(String id) => pieceSkins.firstWhere((s) => s.id == id, orElse: () => pieceSkins.first);

/// Kind of disc to draw.
enum DiscKind { light, dark, queen, striker }

/// Paints one carrom man as in Carrom Pool: a flat disc with a darker rim,
/// a gentle dome of light, and one thin ring inside; the striker carries its
/// mark on top.
void paintCarromDisc(Canvas canvas, Offset p, double r, DiscKind kind, {required StrikerSkin striker, required PieceSkin pieces, double shadow = 1}) {
  final Color base, edge, accent;
  switch (kind) {
    case DiscKind.light:
      base = pieces.light;
      edge = pieces.lightEdge;
      accent = pieces.lightEdge;
    case DiscKind.dark:
      base = pieces.dark;
      edge = pieces.darkEdge;
      accent = Color.lerp(pieces.dark, Colors.white, 0.35)!;
    case DiscKind.queen:
      base = pieces.queen;
      edge = pieces.queenEdge;
      accent = Color.lerp(pieces.queen, Colors.white, 0.45)!;
    case DiscKind.striker:
      base = striker.base;
      edge = striker.edge;
      accent = striker.accent;
  }
  final lighter = Color.lerp(base, Colors.white, 0.22)!;
  final darker = Color.lerp(base, edge, 0.5)!;
  final rect = Rect.fromCircle(center: p, radius: r);

  // Contact shadow on the board.
  if (shadow > 0) {
    canvas.drawCircle(p + Offset(r * 0.08, r * 0.16), r * 1.0, Paint()..color = Color.fromRGBO(0, 0, 0, 0.38 * shadow)..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.2));
  }
  // Rim.
  canvas.drawCircle(p, r, Paint()..color = edge);
  // Face: a soft dome lit from the top-left.
  canvas.drawCircle(p, r * 0.9, Paint()..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 1.0,
        colors: [lighter, base, darker],
        stops: const [0, 0.6, 1],
      ).createShader(rect));
  // One thin ring (two for the light pieces, as on real wooden men).
  final ring = Paint()..style = PaintingStyle.stroke..strokeWidth = max(1, r * 0.06)..color = accent.withValues(alpha: kind == DiscKind.light ? 0.55 : 0.45);
  canvas.drawCircle(p, r * 0.62, ring);
  if (kind == DiscKind.light) canvas.drawCircle(p, r * 0.42, ring);
  if (kind == DiscKind.striker) {
    _strikerMark(canvas, p, r, striker.mark, accent);
  }
  // A small soft highlight.
  canvas.drawCircle(p + Offset(-r * 0.3, -r * 0.34), r * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.22)..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12));
}

void _strikerMark(Canvas canvas, Offset p, double r, StrikerMark mark, Color accent) {
  final paint = Paint()..color = accent;
  switch (mark) {
    case StrikerMark.star:
      final star = Path();
      for (var i = 0; i < 10; i++) {
        final a = -pi / 2 + i * pi / 5;
        final rr = i.isEven ? r * 0.34 : r * 0.15;
        final q = Offset(p.dx + cos(a) * rr, p.dy + sin(a) * rr);
        i == 0 ? star.moveTo(q.dx, q.dy) : star.lineTo(q.dx, q.dy);
      }
      star.close();
      canvas.drawPath(star.shift(Offset(0, r * 0.03)), Paint()..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawPath(star, paint);
    case StrikerMark.ring:
      canvas.drawCircle(p, r * 0.28, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.12..color = accent);
      canvas.drawCircle(p, r * 0.08, paint);
    case StrikerMark.dots:
      for (var i = 0; i < 6; i++) {
        final a = i * pi / 3;
        canvas.drawCircle(Offset(p.dx + cos(a) * r * 0.24, p.dy + sin(a) * r * 0.24), r * 0.08, paint);
      }
      canvas.drawCircle(p, r * 0.09, paint);
    case StrikerMark.bolt:
      final bolt = Path()
        ..moveTo(p.dx + r * 0.08, p.dy - r * 0.34)
        ..lineTo(p.dx - r * 0.16, p.dy + r * 0.04)
        ..lineTo(p.dx + r * 0.02, p.dy + r * 0.04)
        ..lineTo(p.dx - r * 0.08, p.dy + r * 0.34)
        ..lineTo(p.dx + r * 0.18, p.dy - r * 0.04)
        ..lineTo(p.dx, p.dy - r * 0.04)
        ..close();
      canvas.drawPath(bolt, paint);
    case StrikerMark.flame:
      final flame = Path()
        ..moveTo(p.dx, p.dy - r * 0.36)
        ..quadraticBezierTo(p.dx + r * 0.3, p.dy - r * 0.05, p.dx + r * 0.16, p.dy + r * 0.2)
        ..quadraticBezierTo(p.dx + r * 0.08, p.dy + r * 0.34, p.dx, p.dy + r * 0.34)
        ..quadraticBezierTo(p.dx - r * 0.3, p.dy + r * 0.3, p.dx - r * 0.18, p.dy)
        ..quadraticBezierTo(p.dx - r * 0.1, p.dy - r * 0.1, p.dx, p.dy - r * 0.36)
        ..close();
      canvas.drawPath(flame, paint);
      canvas.drawCircle(p + Offset(0, r * 0.12), r * 0.1, Paint()..color = Colors.white.withValues(alpha: 0.8));
  }
}
