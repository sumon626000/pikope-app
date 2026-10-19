import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/carrom/carrom_physics.dart';
import '../../game/physics/vec2.dart';
import 'carrom_controller.dart';
import 'carrom_skins.dart';

/// The board as in Carrom Pool: a light wood playfield in a dark wood frame
/// with orange corners, black corner pockets, double-lined base lanes with
/// orange-filled circles at their ends, and a thin centre circle.
///
/// The widget is square; the playfield (1000 x 1000 units) sits inside a
/// frame of [frame] of the widget's width. [rotated] turns the whole board
/// half a turn so seat 1 sees its own base line at the bottom.
class CarromBoard extends StatelessWidget {
  const CarromBoard({super.key, required this.controller, required this.onPanStart, required this.onPanUpdate, required this.onPanEnd});

  final CarromController controller;
  final void Function(Offset local, Size size) onPanStart;
  final void Function(Offset local, Size size) onPanUpdate;
  final VoidCallback onPanEnd;

  /// Frame thickness as a fraction of the widget width.
  static const frame = 0.042;

  /// Board units -> widget pixels for a widget of width [w].
  static double unit(double w) => w * (1 - 2 * frame) / CarromWorld.size;

  /// Widget point -> board units (undoing the rotation for seat 1).
  static Vec2 toBoard(Offset p, Size size, bool rotated) {
    final u = unit(size.width);
    final off = size.width * frame;
    var x = (p.dx - off) / u, y = (p.dy - off) / u;
    if (rotated) {
      x = CarromWorld.size - x;
      y = CarromWorld.size - y;
    }
    return Vec2(x, y);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, c.maxWidth);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => onPanStart(d.localPosition, size),
            onPanUpdate: (d) => onPanUpdate(d.localPosition, size),
            onPanEnd: (_) => onPanEnd(),
            onPanCancel: onPanEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: CustomPaint(painter: CarromBoardPainter(controller.boardSkin), isComplex: true)),
                CustomPaint(painter: _DiscsPainter(controller)),
              ],
            ),
          );
        },
      );
}

/// Everything that never moves: frame, pockets, lanes, centre circle, in the
/// colours of [skin]. Also used for the board thumbnails in the lobby.
class CarromBoardPainter extends CustomPainter {
  const CarromBoardPainter(this.skin);

  final BoardSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final wood = skin.wood, woodLight = skin.woodLight, woodDark = skin.woodDark;
    final frameColor = skin.frame, frameLight = skin.frameLight, frameDark = skin.frameDark;
    final corner = skin.corner, cornerLight = skin.cornerLight, cornerDark = skin.cornerDark;
    final line = skin.line;
    final w = size.width;
    final f = w * CarromBoard.frame;
    final u = CarromBoard.unit(w);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.04));
    final field = Rect.fromLTWH(f, f, w - 2 * f, w - 2 * f);
    Offset at(double x, double y) => Offset(f + x * u, f + y * u);

    // Drop shadow under the whole board.
    canvas.drawRRect(outer.shift(Offset(0, w * 0.014)), Paint()..color = const Color(0x88000000)..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.016));

    // ---- frame: four lacquered rails mitred at the corners, lit from the
    // outer edge like the pool table's rails, with metal corner brackets and
    // sight diamonds.
    final metal = corner, metalLight = cornerLight, metalDark = cornerDark;
    canvas.save();
    canvas.clipRRect(outer);
    void rail(Rect r, Alignment from, Alignment to, bool horizontal, Path mitre) {
      canvas.save();
      canvas.clipPath(mitre);
      canvas.drawRect(r, Paint()..shader = LinearGradient(
            begin: from,
            end: to,
            colors: [Color.lerp(frameLight, Colors.white, 0.28)!, frameLight, frameColor, frameDark],
            stops: const [0, 0.16, 0.72, 1],
          ).createShader(r));
      // Grain along the rail.
      final rnd = Random(r.left.toInt() * 7 + r.top.toInt());
      for (var i = 0; i < 14; i++) {
        final t = (i + rnd.nextDouble()) / 14;
        final wobble = (rnd.nextDouble() - 0.5) * u * 3;
        final paint = Paint()..color = Colors.black.withValues(alpha: 0.05 + rnd.nextDouble() * 0.1)..strokeWidth = u * (0.6 + rnd.nextDouble());
        if (horizontal) {
          final y = r.top + r.height * t;
          canvas.drawLine(Offset(r.left, y), Offset(r.right, y + wobble), paint);
        } else {
          final x = r.left + r.width * t;
          canvas.drawLine(Offset(x, r.top), Offset(x + wobble, r.bottom), paint);
        }
      }
      canvas.restore();
    }

    rail(Rect.fromLTWH(0, 0, w, f), Alignment.topCenter, Alignment.bottomCenter, true, Path()..moveTo(0, 0)..lineTo(w, 0)..lineTo(w - f, f)..lineTo(f, f)..close());
    rail(Rect.fromLTWH(0, w - f, w, f), Alignment.bottomCenter, Alignment.topCenter, true, Path()..moveTo(0, w)..lineTo(w, w)..lineTo(w - f, w - f)..lineTo(f, w - f)..close());
    rail(Rect.fromLTWH(0, 0, f, w), Alignment.centerLeft, Alignment.centerRight, false, Path()..moveTo(0, 0)..lineTo(f, f)..lineTo(f, w - f)..lineTo(0, w)..close());
    rail(Rect.fromLTWH(w - f, 0, f, w), Alignment.centerRight, Alignment.centerLeft, false, Path()..moveTo(w, 0)..lineTo(w - f, f)..lineTo(w - f, w - f)..lineTo(w, w)..close());
    // Polished highlight along the outer edge.
    canvas.drawRRect(outer.deflate(u * 1.5), Paint()..style = PaintingStyle.stroke..strokeWidth = u * 2..color = Colors.white.withValues(alpha: 0.22));

    // Sights: little brushed-metal diamonds along each rail.
    void diamond(Offset c, bool horizontal) {
      final dw = u * (horizontal ? 9 : 5.5), dh = u * (horizontal ? 5.5 : 9);
      final path = Path()..moveTo(c.dx, c.dy - dh)..lineTo(c.dx + dw, c.dy)..lineTo(c.dx, c.dy + dh)..lineTo(c.dx - dw, c.dy)..close();
      canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [metalLight, metal, metalDark]).createShader(path.getBounds()));
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = u * 0.8..color = Colors.black.withValues(alpha: 0.5));
    }
    for (final k in const [160.0, 330.0, 500.0, 670.0, 840.0]) {
      diamond(Offset(f + k * u, f / 2), true);
      diamond(Offset(f + k * u, w - f / 2), true);
      diamond(Offset(f / 2, f + k * u), false);
      diamond(Offset(w - f / 2, f + k * u), false);
    }

    // Metal corner brackets on the rails (clipped off the playfield).
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRect(field)));
    final capLen = w * 0.115;
    void cap(Rect r, Alignment a, Alignment b) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(w * 0.03));
      canvas.drawRRect(rr, Paint()..shader = LinearGradient(begin: a, end: b, colors: [metalLight, metal, metalDark, metal, metalLight], stops: const [0, 0.3, 0.55, 0.8, 1]).createShader(r));
      canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = u * 1.4..color = Colors.black.withValues(alpha: 0.45));
      canvas.drawRRect(rr.deflate(u * 2.5), Paint()..style = PaintingStyle.stroke..strokeWidth = u * 0.9..color = Colors.white.withValues(alpha: 0.35));
    }
    cap(Rect.fromLTWH(0, 0, capLen, capLen), Alignment.topLeft, Alignment.bottomRight);
    cap(Rect.fromLTWH(w - capLen, 0, capLen, capLen), Alignment.topRight, Alignment.bottomLeft);
    cap(Rect.fromLTWH(0, w - capLen, capLen, capLen), Alignment.bottomLeft, Alignment.topRight);
    cap(Rect.fromLTWH(w - capLen, w - capLen, capLen, capLen), Alignment.bottomRight, Alignment.topLeft);
    canvas.restore();
    canvas.restore();
    // Bevel going down into the playfield.
    canvas.drawRect(field.inflate(f * 0.30), Paint()..style = PaintingStyle.stroke..strokeWidth = f * 0.22..color = frameLight.withValues(alpha: 0.8));
    canvas.drawRect(field.inflate(f * 0.10), Paint()..style = PaintingStyle.stroke..strokeWidth = f * 0.2..color = frameDark);

    // ---- playfield: clean, lightly grained wood -----------------------------
    canvas.drawRect(field, Paint()..shader = RadialGradient(radius: 0.9, colors: [woodLight, wood, woodDark], stops: const [0, 0.65, 1]).createShader(field));
    canvas.save();
    canvas.clipRect(field);
    // A few long, soft grain lines; no speckle, so the pieces read cleanly.
    final grainRnd = Random(7);
    for (var i = 0; i < 26; i++) {
      final y = field.top + grainRnd.nextDouble() * field.height;
      final x0 = field.left - field.width * 0.1;
      final len = field.width * 1.2;
      final dark = grainRnd.nextDouble() < 0.5;
      final path = Path()..moveTo(x0, y);
      path.cubicTo(x0 + len * 0.3, y + (grainRnd.nextDouble() - 0.5) * u * 10, x0 + len * 0.7, y + (grainRnd.nextDouble() - 0.5) * u * 10, x0 + len, y + (grainRnd.nextDouble() - 0.5) * u * 6);
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * (1.5 + grainRnd.nextDouble() * 4)
        ..color = dark ? woodDark.withValues(alpha: 0.10 + grainRnd.nextDouble() * 0.08) : skin.grainLight.withValues(alpha: 0.08));
    }
    // Shadow of the frame falling onto the field edges.
    canvas.drawRect(field, Paint()..style = PaintingStyle.stroke..strokeWidth = u * 24..color = Colors.black.withValues(alpha: 0.14)..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 14));
    canvas.restore();

    // ---- markings: soft tinted bands with a thin outline, as in Carrom Pool --
    final band = Paint()..color = line.withValues(alpha: 0.16);
    final outline = Paint()..style = PaintingStyle.stroke..strokeWidth = u * 2.2..color = line.withValues(alpha: 0.55);
    final hairline = Paint()..style = PaintingStyle.stroke..strokeWidth = u * 1.2..color = line.withValues(alpha: 0.4);

    const half = 32.0, c0 = 220.0, c1 = 780.0, inner = 20.0;
    for (final side in const [160.0, 840.0]) {
      final h = RRect.fromRectAndRadius(Rect.fromLTRB(f + (c0 - half) * u, f + (side - half) * u, f + (c1 + half) * u, f + (side + half) * u), Radius.circular(half * u));
      final v = RRect.fromRectAndRadius(Rect.fromLTRB(f + (side - half) * u, f + (c0 - half) * u, f + (side + half) * u, f + (c1 + half) * u), Radius.circular(half * u));
      for (final r in [h, v]) {
        canvas.drawRRect(r, band);
        canvas.drawRRect(r, outline);
        canvas.drawRRect(r.deflate(u * 7), hairline);
      }
    }
    for (final side in const [160.0, 840.0]) {
      for (final c in const [c0, c1]) {
        for (final p in [at(c, side), at(side, c)]) {
          canvas.drawCircle(p, half * u, Paint()..color = wood);
          canvas.drawCircle(p, half * u, outline);
          canvas.drawCircle(p, inner * u, Paint()..shader = RadialGradient(center: const Alignment(-0.3, -0.3), colors: [cornerLight, corner, cornerDark]).createShader(Rect.fromCircle(center: p, radius: inner * u)));
        }
      }
    }
    // Centre: a soft eight-point star under the ring, and the ring itself.
    final cc = at(500, 500);
    final star = Path();
    for (var i = 0; i < 16; i++) {
      final ang = -pi / 2 + i * pi / 8;
      final rr = (i.isEven ? 175.0 : 128.0) * u;
      final q = Offset(cc.dx + cos(ang) * rr, cc.dy + sin(ang) * rr);
      i == 0 ? star.moveTo(q.dx, q.dy) : star.lineTo(q.dx, q.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = line.withValues(alpha: 0.10));
    canvas.drawPath(star, Paint()..style = PaintingStyle.stroke..strokeWidth = u * 1.6..color = line.withValues(alpha: 0.35));
    canvas.drawCircle(cc, 110 * u, Paint()..color = line.withValues(alpha: 0.10));
    canvas.drawCircle(cc, 110 * u, outline);
    canvas.drawCircle(cc, 95 * u, hairline);
    canvas.drawCircle(cc, 30 * u, outline);

    // ---- pockets: holes sunk into the corners ------------------------------
    for (final p in CarromWorld.pockets) {
      final c = at(p[0], p[1]);
      final r = 52 * u;
      canvas.drawCircle(c + Offset(u * 2, u * 3), r + u * 2, Paint()..color = const Color(0x77000000)..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 6));
      canvas.drawCircle(c, r, Paint()..shader = RadialGradient(center: const Alignment(0.25, 0.3), radius: 0.95, colors: const [Color(0xFF060606), Color(0xFF151515), Color(0xFF3C3C3C)], stops: const [0, 0.65, 1]).createShader(Rect.fromCircle(center: c, radius: r)));
      // Lip of the hole.
      canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = u * 2.2..shader = SweepGradient(transform: const GradientRotation(-pi * 0.75), colors: [frameDark, Color.lerp(frameLight, Colors.white, 0.3)!, frameDark, Colors.black, frameDark]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
  }

  @override
  bool shouldRepaint(CarromBoardPainter old) => old.skin != skin;
}

/// Pieces, the striker, the aim guide and sinking pieces (repaints every frame).
class _DiscsPainter extends CustomPainter {
  _DiscsPainter(this.c) : super(repaint: c.frame);

  final CarromController c;

  DiscKind _kindOf(int disc) {
    if (disc == CarromWorld.striker) return DiscKind.striker;
    if (disc == CarromWorld.queen) return DiscKind.queen;
    return CarromWorld.colourOf(disc) == 0 ? DiscKind.light : DiscKind.dark;
  }

  void _disc(Canvas canvas, Offset p, double r, int disc, {double shadow = 1}) =>
      paintCarromDisc(canvas, p, r, _kindOf(disc), striker: c.strikerSkin, pieces: c.pieceSkin, shadow: shadow);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final f = w * CarromBoard.frame;
    final u = CarromBoard.unit(w);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(f, f, w - 2 * f, w - 2 * f).inflate(f));
    if (c.viewRotated) {
      canvas.translate(w / 2, w / 2);
      canvas.rotate(pi);
      canvas.translate(-w / 2, -w / 2);
    }
    Offset at(double x, double y) => Offset(f + x * u, f + y * u);
    final world = c.world;

    // Sinking pieces: shrink into the pocket.
    for (final s in c.sinking) {
      final k = ((c.frameTime - s.start) / SinkingDisc.seconds).clamp(0.0, 1.0);
      final p = CarromWorld.pockets[s.pocket];
      final pos = Offset.lerp(at(s.at.x, s.at.y), at(p[0], p[1]), k)!;
      _disc(canvas, pos, CarromWorld.radiusOf(s.disc) * u * (1 - k * 0.7), s.disc, shadow: 1 - k);
    }

    // The striker at rest on a base line while someone is placing / aiming.
    final strikerSeat = c.strikerSeat;
    if (strikerSeat != null) {
      final sy = strikerSeat == 0 ? CarromWorld.baseNear : CarromWorld.baseFar;
      final sp = at(c.strikerX, sy);
      final dir = c.aimDir;
      if (dir != null && (c.canAim || c.showRemoteStriker)) {
        _drawGuide(canvas, world, c.strikerX, sy, dir, u, f, c.power);
      }
      if (c.canAim) {
        final pulse = 0.5 + 0.5 * sin(c.frameTime * 4);
        canvas.drawCircle(sp, CarromWorld.strikerR * u * (1.35 + pulse * 0.15), Paint()..color = Color.fromRGBO(255, 213, 74, 0.35 + pulse * 0.25)..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 12));
      }
      _disc(canvas, sp, CarromWorld.strikerR * u, CarromWorld.striker);
      if (c.canAim && c.aimDir == null) {
        // Little arrows: slide left / right.
        final arrow = Paint()..color = Colors.white..strokeWidth = u * 4.5..strokeCap = StrokeCap.round;
        final bob = sin(c.frameTime * 6) * u * 4;
        for (final s in const [-1.0, 1.0]) {
          final ax = sp.dx + s * (CarromWorld.strikerR * u + u * 24 + bob);
          canvas.drawLine(Offset(ax, sp.dy), Offset(ax - s * u * 13, sp.dy - u * 11), arrow);
          canvas.drawLine(Offset(ax, sp.dy), Offset(ax - s * u * 13, sp.dy + u * 11), arrow);
        }
      }
    }

    // Pieces on the board (striker included while a stroke is running).
    for (var i = CarromWorld.count - 1; i >= 0; i--) {
      if (world.gone[i]) continue;
      if (i == CarromWorld.striker && !c.shooting) continue;
      _disc(canvas, at(world.x[i], world.y[i]), CarromWorld.radiusOf(i) * u, i);
    }
    canvas.restore();
  }

  void _drawGuide(Canvas canvas, CarromWorld world, double sx, double sy, Vec2 dir, double u, double f, double power) {
    Offset at(double x, double y) => Offset(f + x * u, f + y * u);
    final aim = world.predict(dir, from: Vec2(sx, sy));
    final from = at(sx, sy);
    final ghost = at(aim.ghost.x, aim.ghost.y);
    final dirPx = Offset(dir.x, dir.y);
    // Dotted range circle around the striker (how far it can be pulled).
    final range = 236 * u;
    for (var i = 0; i < 56; i++) {
      final a = i * 2 * pi / 56;
      canvas.drawCircle(from + Offset(cos(a), sin(a)) * range, u * 2.2, Paint()..color = const Color(0xFFFF3B3B).withValues(alpha: 0.55));
    }
    // Dotted path from the striker to the first impact (or the cushion).
    final total = (ghost - from).distance;
    final step = u * 22;
    for (var d = CarromWorld.strikerR * u + step * 0.5; d < total; d += step) {
      canvas.drawCircle(from + dirPx * d, u * 4, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }
    // After the hit piece: a short trail of shrinking dots the way it will go.
    final td = aim.targetDir;
    if (aim.hitDisc != null) {
      final hit = at(world.x[aim.hitDisc!], world.y[aim.hitDisc!]);
      canvas.drawCircle(
        hit,
        CarromWorld.radiusOf(aim.hitDisc!) * u + u * 7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 4
          ..color = const Color(0xFFFFD54A),
      );
      if (td != null) {
        final tdPx = Offset(td.x, td.y);
        for (var i = 0; i < 5; i++) {
          final d = CarromWorld.pieceR * u + u * 16 + i * u * 20;
          canvas.drawCircle(hit + tdPx * d, u * (4.2 - i * 0.5), Paint()..color = Colors.white.withValues(alpha: 0.9 - i * 0.12));
        }
      }
    }
    // Red arrow from the striker: direction, and its length is the power.
    if (power > 0) {
      final len = CarromWorld.strikerR * u + u * (30 + 150 * power);
      final tip = from + dirPx * len;
      final shaft = Paint()..color = const Color(0xFFE8362E)..strokeWidth = u * 7..strokeCap = StrokeCap.round;
      canvas.drawLine(from + dirPx * (CarromWorld.strikerR * u + u * 4), tip, Paint()..color = Colors.black.withValues(alpha: 0.35)..strokeWidth = u * 9..strokeCap = StrokeCap.round);
      canvas.drawLine(from + dirPx * (CarromWorld.strikerR * u + u * 4), tip, shaft);
      final n = Offset(-dirPx.dy, dirPx.dx);
      final head = Path()
        ..moveTo(tip.dx + dirPx.dx * u * 16, tip.dy + dirPx.dy * u * 16)
        ..lineTo(tip.dx + n.dx * u * 11, tip.dy + n.dy * u * 11)
        ..lineTo(tip.dx - n.dx * u * 11, tip.dy - n.dy * u * 11)
        ..close();
      canvas.drawPath(head, Paint()..color = const Color(0xFFFFB300));
      canvas.drawPath(head, Paint()..style = PaintingStyle.stroke..strokeWidth = u * 1.5..color = const Color(0xFFE8362E));
    }
  }

  @override
  bool shouldRepaint(_DiscsPainter old) => true;
}
