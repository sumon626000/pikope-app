import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../game/models/playing_card.dart';

/// Card face per the client's final spec: white card, small rank with the
/// suit right after it in the top-left, big rank bottom-right, all black.
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.card,
    this.width = 74,
    this.completed = false,
    this.penalty = false,
    this.selected = false,
    this.disabled = false,
  });

  final PlayingCard card;
  final double width;
  final bool completed;
  final bool penalty;
  final bool selected;
  final bool disabled;

  static const aspect = 1.46;

  @override
  Widget build(BuildContext context) {
    final h = width * aspect;
    final ink = completed ? const Color(0xFF6E6E74) : Colors.black;
    final border = selected
        ? AppColors.active
        : penalty
            ? AppColors.danger
            : const Color(0xFFBDBDC4);
    return Opacity(
      opacity: disabled && !completed ? 0.55 : 1,
      child: Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: completed
                ? const [Color(0xFFB4B4BB), Color(0xFF94949C)]
                : const [Colors.white, Color(0xFFECECF2)],
          ),
          borderRadius: BorderRadius.circular(width * 0.1),
          border: Border.all(color: border, width: selected || penalty ? width * 0.05 : width * 0.02),
          boxShadow: [
            BoxShadow(
              color: selected ? AppColors.active.withValues(alpha: 0.6) : Colors.black54,
              blurRadius: selected ? width * 0.25 : width * 0.08,
              offset: Offset(0, width * 0.03),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: width * 0.09,
              top: width * 0.03,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(card.rankLabel,
                      style: TextStyle(
                          fontFamily: AppText.card, fontSize: width * 0.34, color: ink, height: 1.1)),
                  SizedBox(width: width * 0.03),
                  CustomPaint(
                    size: Size.square(width * 0.24),
                    painter: SuitPainter(card.suit, ink),
                  ),
                ],
              ),
            ),
            Positioned(
              right: width * 0.08,
              bottom: 0,
              child: Text(card.rankLabel,
                  style: TextStyle(
                      fontFamily: AppText.card,
                      fontSize: width * (card.rank == 10 ? 0.66 : 0.8),
                      color: ink,
                      height: 1.05,
                      letterSpacing: card.rank == 10 ? -width * 0.04 : 0)),
            ),
            if (penalty)
              Positioned(
                right: width * 0.07,
                top: width * 0.07,
                child: Container(
                  width: width * 0.2,
                  height: width * 0.2,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                  child: Text('P',
                      style: AppText.label(width * 0.13, color: Colors.white, weight: FontWeight.w900)),
                ),
              ),
            if (completed)
              Positioned(
                right: width * 0.07,
                top: width * 0.07,
                child: Icon(Icons.check_circle, size: width * 0.24, color: const Color(0xFF2E7D32)),
              ),
          ],
        ),
      ),
    );
  }
}

class CardBack extends StatelessWidget {
  const CardBack({super.key, this.width = 74, this.completed = false, this.highlighted = false});

  final double width;
  final bool completed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * CardFace.aspect,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.08),
        border: highlighted ? Border.all(color: AppColors.active, width: width * 0.06) : null,
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: RawImage(image: _cardBackImage(completed), fit: BoxFit.fill, filterQuality: FilterQuality.medium),
    );
  }
}

final Map<bool, ui.Image> _cardBackImages = {};

/// The back is the most repeated graphic on screen (21+ copies), so it is
/// rasterised once instead of re-drawing its lattice for every card.
ui.Image _cardBackImage(bool completed) => _cardBackImages.putIfAbsent(completed, () {
      const size = Size(222, 222 * CardFace.aspect);
      final recorder = ui.PictureRecorder();
      _CardBackPainter(completed).paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(size.width.round(), size.height.round());
      picture.dispose();
      return image;
    });

class _CardBackPainter extends CustomPainter {
  _CardBackPainter(this.completed);

  final bool completed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final dark = completed ? const Color(0xFF5E5E66) : const Color(0xFFA4122B);
    final base = completed ? const Color(0xFF85858D) : const Color(0xFFE02A45);
    final light = completed ? const Color(0xFFC4C4CB) : const Color(0xFFFFD7DC);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.09));
    canvas.drawRRect(outer, Paint()..color = const Color(0xFFFDFDFD));
    final inner = RRect.fromRectAndRadius((Offset.zero & size).deflate(w * 0.055), Radius.circular(w * 0.055));
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, dark],
        ).createShader(inner.outerRect),
    );
    // Diamond lattice.
    canvas.save();
    canvas.clipRRect(inner);
    final line = Paint()
      ..color = light.withValues(alpha: 0.38)
      ..strokeWidth = w * 0.014;
    final step = w / 4.5;
    for (var d = -size.height; d < w + size.height; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), line);
      canvas.drawLine(Offset(d + size.height, 0), Offset(d, size.height), line);
    }
    canvas.restore();
    canvas.drawRRect(
      inner.deflate(w * 0.05),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.02
        ..color = light.withValues(alpha: 0.85),
    );
    // Centre medallion: a ball on a diamond.
    final c = size.center(Offset.zero);
    final m = w * 0.24;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - m * 1.25)
        ..lineTo(c.dx + m, c.dy)
        ..lineTo(c.dx, c.dy + m * 1.25)
        ..lineTo(c.dx - m, c.dy)
        ..close(),
      Paint()..color = light,
    );
    canvas.drawCircle(c, m * 0.5, Paint()..color = dark);
    canvas.drawCircle(c, m * 0.2, Paint()..color = light);
  }

  @override
  bool shouldRepaint(_CardBackPainter old) => old.completed != completed;
}

class SuitPainter extends CustomPainter {
  SuitPainter(this.suit, this.color);

  final Suit suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()..color = color;
    Path heart(bool flipped) {
      final p = Path()
        ..moveTo(w * 0.5, h * 0.95)
        ..cubicTo(w * 0.05, h * 0.6, -w * 0.05, h * 0.3, w * 0.12, h * 0.14)
        ..cubicTo(w * 0.27, 0, w * 0.45, h * 0.08, w * 0.5, h * 0.28)
        ..cubicTo(w * 0.55, h * 0.08, w * 0.73, 0, w * 0.88, h * 0.14)
        ..cubicTo(w * 1.05, h * 0.3, w * 0.95, h * 0.6, w * 0.5, h * 0.95)
        ..close();
      if (!flipped) return p;
      final m = Matrix4.identity()
        ..translateByDouble(0, h * 0.86, 0, 1)
        ..scaleByDouble(1, -0.86, 1, 1);
      return p.transform(m.storage);
    }

    Path stem() => Path()
      ..moveTo(w * 0.5, h * 0.55)
      ..quadraticBezierTo(w * 0.48, h * 0.9, w * 0.3, h)
      ..lineTo(w * 0.7, h)
      ..quadraticBezierTo(w * 0.52, h * 0.9, w * 0.5, h * 0.55)
      ..close();

    switch (suit) {
      case Suit.hearts:
        canvas.drawPath(heart(false), paint);
      case Suit.diamonds:
        canvas.drawPath(
            Path()
              ..moveTo(w * 0.5, 0)
              ..lineTo(w * 0.9, h * 0.5)
              ..lineTo(w * 0.5, h)
              ..lineTo(w * 0.1, h * 0.5)
              ..close(),
            paint);
      case Suit.spades:
        canvas.drawPath(heart(true), paint);
        canvas.drawPath(stem(), paint);
      case Suit.clubs:
        final r = w * 0.24;
        canvas.drawCircle(Offset(w * 0.5, h * 0.26), r, paint);
        canvas.drawCircle(Offset(w * 0.25, h * 0.6), r, paint);
        canvas.drawCircle(Offset(w * 0.75, h * 0.6), r, paint);
        canvas.drawCircle(Offset(w * 0.5, h * 0.52), r * 0.6, paint);
        canvas.drawPath(stem(), paint);
    }
  }

  @override
  bool shouldRepaint(SuitPainter old) => old.suit != suit || old.color != color;
}

/// Turns a card over. Only the back (a cached image) is squashed; the face,
/// which is text, appears at full size so it is never re-rasterised mid-turn.
class FlipCard extends StatelessWidget {
  const FlipCard({super.key, required this.faceUp, required this.front, required this.back});

  final bool faceUp;
  final Widget front;
  final Widget back;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: faceUp ? 1 : 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeIn,
      builder: (context, t, _) {
        if (t >= 1) return front;
        // Back and face are the same size, so the slot keeps its footprint.
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(cos(t * pi / 2), 1, 1),
          child: back,
        );
      },
    );
  }
}
