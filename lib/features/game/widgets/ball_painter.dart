import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const _ballColors = [
  Color(0xFFF7F4EA), // cue
  Color(0xFFFFD21F),
  Color(0xFF1F56D6),
  Color(0xFFE0261B),
  Color(0xFF6B2FA8),
  Color(0xFFFF7F1F),
  Color(0xFF1E9B4B),
  Color(0xFF8B2A1E),
  Color(0xFF151515),
];

Color ballColor(int number) => number <= 8 ? _ballColors[number] : _ballColors[number - 8];

final Map<String, TextPainter> _numberCache = {};

TextPainter _numberPainter(int number, double size) {
  final key = '$number@${size.toStringAsFixed(1)}';
  return _numberCache.putIfAbsent(
    key,
    () => TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          fontFamily: 'Orbitron',
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: Colors.black,
          height: 1,
          letterSpacing: -size * 0.06,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(),
  );
}

const double _spriteRadius = 76;
const int _spriteSize = 160;
final Map<int, ui.Image> _sprites = {};
final Paint _shadowPaint = Paint()
  ..color = const Color(0x73000000)
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
final Paint _spritePaint = Paint()..filterQuality = FilterQuality.medium;

/// Each ball is drawn once into a small image; frames then just blit it.
ui.Image _sprite(int number) => _sprites.putIfAbsent(number, () {
      final recorder = ui.PictureRecorder();
      _paintBallVector(
          Canvas(recorder), const Offset(_spriteSize / 2, _spriteSize / 2), _spriteRadius, number);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(_spriteSize, _spriteSize);
      picture.dispose();
      return image;
    });

/// Paints pool ball [number] (0 = cue ball) centred on [c].
void paintBall(Canvas canvas, Offset c, double r, int number,
    {bool shadow = true, double opacity = 1}) {
  if (shadow) canvas.drawCircle(c + Offset(r * 0.2, r * 0.3), r * 1.02, _shadowPaint);
  final half = r * _spriteSize / (2 * _spriteRadius);
  canvas.drawImageRect(
    _sprite(number),
    const Rect.fromLTWH(0, 0, _spriteSize + 0.0, _spriteSize + 0.0),
    Rect.fromCenter(center: c, width: half * 2, height: half * 2),
    opacity >= 1
        ? _spritePaint
        : (Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, opacity)),
  );
}

void _paintBallVector(Canvas canvas, Offset c, double r, int number) {
  final rect = Rect.fromCircle(center: c, radius: r);
  final color = ballColor(number);
  final striped = number > 8;
  const ivory = Color(0xFFFBF8EE);

  // Body: lit from the upper left, falling to a deeper tone at the rim.
  Shader body(Color base) => RadialGradient(
        center: const Alignment(-0.38, -0.45),
        radius: 1.15,
        colors: [
          Color.lerp(base, Colors.white, 0.42)!,
          base,
          Color.lerp(base, Colors.black, 0.5)!,
        ],
        stops: const [0, 0.5, 1],
      ).createShader(rect);

  canvas.drawCircle(c, r, Paint()..shader = body(striped ? ivory : color));
  if (striped) {
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    // A band that bulges like a stripe wrapped round a sphere.
    final band = Path()
      ..moveTo(c.dx - r, c.dy - r * 0.5)
      ..quadraticBezierTo(c.dx, c.dy - r * 0.72, c.dx + r, c.dy - r * 0.5)
      ..lineTo(c.dx + r, c.dy + r * 0.5)
      ..quadraticBezierTo(c.dx, c.dy + r * 0.72, c.dx - r, c.dy + r * 0.5)
      ..close();
    canvas.drawPath(band, Paint()..shader = body(color));
    canvas.restore();
  }
  if (number > 0) {
    final disc = r * 0.5;
    canvas.drawCircle(c, disc, Paint()..color = ivory);
    canvas.drawCircle(
        c,
        disc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.03
          ..color = const Color(0x33000000));
    final tp = _numberPainter(number, r * (number > 9 ? 0.6 : 0.72));
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }
  // Contact shadow inside the lower rim, then the glossy highlights.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.25, -0.3),
        radius: 1.0,
        colors: [Color(0x00000000), Color(0x00000000), Color(0x66000000)],
        stops: [0, 0.72, 1],
      ).createShader(rect),
  );
  final gloss = Rect.fromCenter(
      center: c + Offset(-r * 0.34, -r * 0.42), width: r * 0.78, height: r * 0.5);
  canvas.save();
  canvas.translate(gloss.center.dx, gloss.center.dy);
  canvas.rotate(-0.6);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: gloss.width, height: gloss.height),
    Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xF2FFFFFF), Color(0x00FFFFFF)],
      ).createShader(Rect.fromCenter(center: Offset.zero, width: gloss.width, height: gloss.height)),
  );
  canvas.restore();
  canvas.drawCircle(c + Offset(r * 0.42, r * 0.5), r * 0.16, Paint()..color = const Color(0x26FFFFFF));
  canvas.drawCircle(
      c,
      r - r * 0.015,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.03
        ..color = const Color(0x40000000));
}

/// Small static ball used in HUD chips.
class BallIcon extends StatelessWidget {
  const BallIcon(this.number, {super.key, this.size = 30, this.opacity = 1});

  final int number;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _BallIconPainter(number, opacity));
}

class _BallIconPainter extends CustomPainter {
  _BallIconPainter(this.number, this.opacity);
  final int number;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) => paintBall(
      canvas, size.center(Offset.zero), size.width / 2, number,
      shadow: false, opacity: opacity);

  @override
  bool shouldRepaint(_BallIconPainter old) => old.number != number || old.opacity != opacity;
}
