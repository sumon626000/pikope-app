import 'dart:math';

import 'package:flutter/material.dart';

import '../../../data/demo_data.dart';

/// Vector pool table drawn in the same 600x351 layout as the supplied table
/// images (cushion noses at 50..550 x 50.5..300.5), so it is sharp at any
/// resolution and lines up with the physics playfield.
void paintProTable(Canvas canvas, Size size, TableStyle st) {
  canvas.save();
  canvas.scale(size.width / 600);

  const outer = Rect.fromLTRB(6, 6, 594, 345);
  const bed = Rect.fromLTRB(38, 38, 562, 313);
  final outerR = RRect.fromRectAndRadius(outer, const Radius.circular(26));
  final railLight = Color.lerp(st.rail, Colors.white, 0.22)!;
  final metalLight = Color.lerp(st.metal, Colors.white, 0.55)!;
  final cushion = Color.lerp(st.cloth, Colors.black, 0.2)!;
  final cushionDark = Color.lerp(st.cloth, Colors.black, 0.45)!;
  final clothLight = Color.lerp(st.cloth, Colors.white, 0.16)!;

  canvas.save();
  canvas.clipRRect(outerR);

  // ---- rails: lit from the outer edge, darkening toward the cushion
  void rail(Rect r, Alignment from, Alignment to, bool horizontal) {
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: from,
          end: to,
          colors: [railLight, st.rail, st.rail, st.railDark],
          stops: const [0, 0.22, 0.7, 1],
        ).createShader(r),
    );
    // Wood grain / brushed lines along the rail.
    final rnd = Random(r.left.toInt() * 7 + r.top.toInt());
    for (var i = 0; i < 11; i++) {
      final t = (i + rnd.nextDouble()) / 11;
      final wobble = rnd.nextDouble() * 1.2 - 0.6;
      final paint = Paint()
        ..color = Colors.black.withValues(alpha: 0.05 + rnd.nextDouble() * 0.1)
        ..strokeWidth = 0.35 + rnd.nextDouble() * 0.5;
      if (horizontal) {
        final y = r.top + r.height * t;
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y + wobble), paint);
      } else {
        final x = r.left + r.width * t;
        canvas.drawLine(Offset(x, r.top), Offset(x + wobble, r.bottom), paint);
      }
    }
  }

  rail(const Rect.fromLTRB(6, 6, 594, 38), Alignment.topCenter, Alignment.bottomCenter, true);
  rail(const Rect.fromLTRB(6, 313, 594, 345), Alignment.bottomCenter, Alignment.topCenter, true);
  // Mitre the side rails so the corners do not show a seam.
  canvas.save();
  canvas.clipPath(Path()
    ..moveTo(6, 6)
    ..lineTo(38, 38)
    ..lineTo(38, 313)
    ..lineTo(6, 345)
    ..close());
  rail(const Rect.fromLTRB(6, 6, 38, 345), Alignment.centerLeft, Alignment.centerRight, false);
  canvas.restore();
  canvas.save();
  canvas.clipPath(Path()
    ..moveTo(594, 6)
    ..lineTo(562, 38)
    ..lineTo(562, 313)
    ..lineTo(594, 345)
    ..close());
  rail(const Rect.fromLTRB(562, 6, 594, 345), Alignment.centerRight, Alignment.centerLeft, false);
  canvas.restore();

  // ---- metal pocket hardware on the rail only
  canvas.save();
  canvas.clipPath(Path.combine(
    PathOperation.difference,
    Path()..addRect(outer),
    Path()..addRect(bed),
  ));
  void cap(Rect r, Alignment a, Alignment b) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(5));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: a,
          end: b,
          colors: [metalLight, st.metal, st.metalDark, st.metal, metalLight],
          stops: const [0, 0.3, 0.55, 0.8, 1],
        ).createShader(r),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.45),
    );
  }

  cap(const Rect.fromLTRB(0, 0, 64, 64), Alignment.topLeft, Alignment.bottomRight);
  cap(const Rect.fromLTRB(536, 0, 600, 64), Alignment.topRight, Alignment.bottomLeft);
  cap(const Rect.fromLTRB(0, 287, 64, 351), Alignment.bottomLeft, Alignment.topRight);
  cap(const Rect.fromLTRB(536, 287, 600, 351), Alignment.bottomRight, Alignment.topLeft);
  cap(const Rect.fromLTRB(279, 0, 321, 42), Alignment.topLeft, Alignment.bottomRight);
  cap(const Rect.fromLTRB(279, 309, 321, 351), Alignment.bottomLeft, Alignment.topRight);
  canvas.restore();

  // ---- sights (diamonds) on the rails
  final sight = Paint()..color = st.sight;
  final sightEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.4
    ..color = Colors.black.withValues(alpha: 0.5);
  void diamond(double x, double y, bool horizontal) {
    final w = horizontal ? 3.6 : 2.3, h = horizontal ? 2.3 : 3.6;
    final p = Path()
      ..moveTo(x, y - h)
      ..lineTo(x + w, y)
      ..lineTo(x, y + h)
      ..lineTo(x - w, y)
      ..close();
    canvas.drawPath(p, sight);
    canvas.drawPath(p, sightEdge);
  }

  for (final k in const [1, 2, 3, 5, 6, 7]) {
    diamond(50 + 62.5 * k, 22, true);
    diamond(50 + 62.5 * k, 329, true);
  }
  for (final k in const [1, 2, 3]) {
    diamond(22, 50.5 + 62.5 * k, false);
    diamond(578, 50.5 + 62.5 * k, false);
  }

  // ---- cloth
  canvas.drawRect(
    bed,
    Paint()
      ..shader = RadialGradient(
        radius: 0.72,
        colors: [clothLight, st.cloth, st.clothDark],
        stops: const [0, 0.55, 1],
      ).createShader(bed),
  );
  final mark = Paint()
    ..color = Colors.white.withValues(alpha: 0.2)
    ..strokeWidth = 0.7;
  canvas.drawLine(const Offset(175, 50.5), const Offset(175, 300.5), mark);
  canvas.drawCircle(const Offset(425, 175.5), 1.6, Paint()..color = Colors.white.withValues(alpha: 0.38));
  canvas.drawCircle(const Offset(175, 175.5), 1.4, Paint()..color = Colors.white.withValues(alpha: 0.3));

  // ---- cushions with a soft shadow on the cloth
  void cushionPiece(List<Offset> back, List<Offset> nose, Offset inward) {
    final shadow = Path()
      ..moveTo(nose[0].dx, nose[0].dy)
      ..lineTo(nose[1].dx, nose[1].dy)
      ..lineTo(nose[1].dx + inward.dx * 7, nose[1].dy + inward.dy * 7)
      ..lineTo(nose[0].dx + inward.dx * 7, nose[0].dy + inward.dy * 7)
      ..close();
    final sb = shadow.getBounds();
    canvas.drawPath(
      shadow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-inward.dx, -inward.dy),
          end: Alignment(inward.dx, inward.dy),
          colors: const [Color(0x59000000), Color(0x00000000)],
        ).createShader(sb),
    );
    final body = Path()
      ..moveTo(back[0].dx, back[0].dy)
      ..lineTo(back[1].dx, back[1].dy)
      ..lineTo(nose[1].dx, nose[1].dy)
      ..lineTo(nose[0].dx, nose[0].dy)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-inward.dx, -inward.dy),
          end: Alignment(inward.dx, inward.dy),
          colors: [cushionDark, cushion, Color.lerp(cushion, Colors.white, 0.18)!],
          stops: const [0, 0.6, 1],
        ).createShader(body.getBounds()),
    );
    canvas.drawLine(
      nose[0],
      nose[1],
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 0.7,
    );
  }

  cushionPiece(const [Offset(58, 38), Offset(290, 38)], const [Offset(69, 50.5), Offset(285, 50.5)], const Offset(0, 1));
  cushionPiece(const [Offset(310, 38), Offset(542, 38)], const [Offset(315, 50.5), Offset(531, 50.5)], const Offset(0, 1));
  cushionPiece(const [Offset(58, 313), Offset(290, 313)], const [Offset(69, 300.5), Offset(285, 300.5)], const Offset(0, -1));
  cushionPiece(const [Offset(310, 313), Offset(542, 313)], const [Offset(315, 300.5), Offset(531, 300.5)], const Offset(0, -1));
  cushionPiece(const [Offset(38, 58), Offset(38, 293)], const [Offset(50, 69.5), Offset(50, 281.5)], const Offset(1, 0));
  cushionPiece(const [Offset(562, 58), Offset(562, 293)], const [Offset(550, 69.5), Offset(550, 281.5)], const Offset(-1, 0));

  // ---- pockets
  void pocket(Offset c, double r) {
    canvas.drawCircle(c, r + 2.6, Paint()..color = const Color(0xFF17130F));
    canvas.drawCircle(
      c,
      r + 2.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = metalLight.withValues(alpha: 0.55),
    );
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.25),
          colors: [Color(0xFF000000), Color(0xFF050505), Color(0xFF26221E)],
          stops: [0, 0.7, 1],
        ).createShader(rect),
    );
  }

  pocket(const Offset(44, 44.5), 15);
  pocket(const Offset(556, 44.5), 15);
  pocket(const Offset(44, 306.5), 15);
  pocket(const Offset(556, 306.5), 15);
  pocket(const Offset(300, 39.5), 12.5);
  pocket(const Offset(300, 311.5), 12.5);

  canvas.restore();

  // Outer rim catch-light.
  canvas.drawRRect(
    outerR.deflate(0.6),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.16),
  );
  canvas.restore();
}

/// Static picture of a table skin (menus, thumbnails).
class TableArt extends StatelessWidget {
  const TableArt({super.key, required this.skin, required this.width});

  final TableSkin skin;
  final double width;

  @override
  Widget build(BuildContext context) {
    final size = Size(width, width * 351 / 600);
    final style = skin.style;
    if (style == null) {
      return Image.asset(skin.asset!, width: size.width, height: size.height, fit: BoxFit.fill,
          filterQuality: FilterQuality.medium);
    }
    return RepaintBoundary(child: CustomPaint(size: size, painter: _TableArtPainter(style)));
  }
}

class _TableArtPainter extends CustomPainter {
  _TableArtPainter(this.style);

  final TableStyle style;

  @override
  void paint(Canvas canvas, Size size) => paintProTable(canvas, size, style);

  @override
  bool shouldRepaint(_TableArtPainter old) => old.style != style;
}
