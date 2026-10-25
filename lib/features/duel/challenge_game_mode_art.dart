import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/widgets/ball_painter.dart' show paintBall;

/// Mini game art for challenge mode picker (matches home card style).
class ChallengePoolArt extends StatelessWidget {
  const ChallengePoolArt({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 120.0;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 90.0;
        return CustomPaint(
          size: Size(w, h),
          painter: const _ChallengePoolArtPainter(),
        );
      },
    );
  }
}

class _ChallengePoolArtPainter extends CustomPainter {
  const _ChallengePoolArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.15),
          radius: 0.95,
          colors: [Color(0xFF2FA45C), Color(0xFF166B38), Color(0xFF062A14)],
        ).createShader(rect),
    );

    // Scale art to the card (home billiard art uses ~120px-wide coords; cards are much smaller).
    final u = size.shortestSide;
    final cx = size.width * 0.5;
    final cy = size.height * 0.48;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(u / 120);

    canvas.save();
    canvas.translate(0, 38);
    canvas.rotate(-0.12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-72, -4, 144, 8), const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF6B3519), Color(0xFFE9C98F), Color(0xFFF7E3BD)])
            .createShader(const Rect.fromLTWH(-72, -4, 144, 8)),
    );
    canvas.restore();

    paintBall(canvas, const Offset(-42, 8), 11, 4);
    paintBall(canvas, const Offset(-6, -28), 7, 1);
    paintBall(canvas, const Offset(14, -20), 9, 3);
    paintBall(canvas, const Offset(38, -12), 11, 8);
    paintBall(canvas, const Offset(-34, -32), 6, 11);
    paintBall(canvas, const Offset(0, 12), 22, 9);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChallengePoolArtPainter old) => false;
}

class ChallengeCarromArt extends StatelessWidget {
  const ChallengeCarromArt({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _ChallengeCarromArtPainter());
}

class _ChallengeCarromArtPainter extends CustomPainter {
  const _ChallengeCarromArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A1414), Color(0xFF1A0808)],
        ).createShader(rect),
    );
    final b = size.shortestSide * 0.82;
    final left = (size.width - b) / 2, top = (size.height - b) / 2 + size.height * 0.04;
    final board = Rect.fromLTWH(left, top, b, b);
    canvas.drawRRect(RRect.fromRectAndRadius(board, Radius.circular(b * 0.05)), Paint()..color = const Color(0xFF5B3A2E));
    final f = b * 0.06;
    final field = board.deflate(f);
    canvas.drawRect(field, Paint()..color = const Color(0xFFE8BF8E));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFA2613B);
    final u = field.width;
    for (final s in const [0.16, 0.84]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(field.left + u * 0.19, field.top + u * (s - 0.03), field.left + u * 0.81, field.top + u * (s + 0.03)),
          Radius.circular(u * 0.03),
        ),
        line,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(field.left + u * (s - 0.03), field.top + u * 0.19, field.left + u * (s + 0.03), field.top + u * 0.81),
          Radius.circular(u * 0.03),
        ),
        line,
      );
    }
    canvas.drawCircle(field.center, u * 0.17, line);
    for (final c in [field.topLeft, field.topRight, field.bottomLeft, field.bottomRight]) {
      canvas.drawCircle(
        c + Offset(c.dx < field.center.dx ? u * 0.04 : -u * 0.04, c.dy < field.center.dy ? u * 0.04 : -u * 0.04),
        u * 0.05,
        Paint()..color = const Color(0xFF111111),
      );
    }
    final r = u * 0.03;
    canvas.drawCircle(field.center, r, Paint()..color = const Color(0xFFE53935));
    for (var k = 0; k < 6; k++) {
      final a = -math.pi / 2 + k * math.pi / 3;
      final p = field.center + Offset(2.1 * r * math.cos(a), 2.1 * r * math.sin(a));
      canvas.drawCircle(p, r, Paint()..color = k.isEven ? const Color(0xFF2C2F33) : const Color(0xFFEFE3D2));
    }
    canvas.drawCircle(Offset(field.center.dx, field.top + u * 0.84), r * 1.35, Paint()..color = const Color(0xFFE53935));
  }

  @override
  bool shouldRepaint(_ChallengeCarromArtPainter old) => false;
}

class ChallengeLudoArt extends StatelessWidget {
  const ChallengeLudoArt({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _ChallengeLudoArtPainter());
}

class _ChallengeLudoArtPainter extends CustomPainter {
  const _ChallengeLudoArtPainter();

  static const _cols = [Color(0xFFE0333B), Color(0xFF2FA84F), Color(0xFFE8B91C), Color(0xFF2F6BDC)];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A2606), Color(0xFF1A1206)],
        ).createShader(rect),
    );
    final b = size.shortestSide * 0.82;
    final left = (size.width - b) / 2, top = (size.height - b) / 2 + size.height * 0.04;
    final s = b / 15;
    Rect cell(double c, double r, double w) => Rect.fromLTWH(left + c * s, top + r * s, w * s, w * s);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, b, b), Radius.circular(s)), Paint()..color = const Color(0xFFEFF2F8));
    final yards = [[0.0, 9.0], [0.0, 0.0], [9.0, 0.0], [9.0, 9.0]];
    for (var i = 0; i < 4; i++) {
      canvas.drawRRect(RRect.fromRectAndRadius(cell(yards[i][0], yards[i][1], 6), Radius.circular(s)), Paint()..color = _cols[i]);
      canvas.drawRRect(RRect.fromRectAndRadius(cell(yards[i][0] + 1, yards[i][1] + 1, 4), Radius.circular(s * 0.6)), Paint()..color = Colors.white);
      canvas.drawCircle(Offset(left + (yards[i][0] + 3) * s, top + (yards[i][1] + 3) * s), s * 1.1, Paint()..color = _cols[i]);
      canvas.drawCircle(
        Offset(left + (yards[i][0] + 3) * s, top + (yards[i][1] + 3) * s),
        s * 1.1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
    final mid = Offset(left + 7.5 * s, top + 7.5 * s);
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromCenter(center: mid, width: 3 * s, height: 3 * s), Paint()..color = const Color(0xFFDDE3EE));
    }
    final c = [Offset(left + 6 * s, top + 6 * s), Offset(left + 9 * s, top + 6 * s), Offset(left + 9 * s, top + 9 * s), Offset(left + 6 * s, top + 9 * s)];
    void tri(Offset a, Offset b2, Color col) => canvas.drawPath(Path()..moveTo(mid.dx, mid.dy)..lineTo(a.dx, a.dy)..lineTo(b2.dx, b2.dy)..close(), Paint()..color = col);
    tri(c[0], c[1], _cols[2]);
    tri(c[1], c[2], _cols[3]);
    tri(c[2], c[3], _cols[0]);
    tri(c[3], c[0], _cols[1]);
  }

  @override
  bool shouldRepaint(_ChallengeLudoArtPainter old) => false;
}
