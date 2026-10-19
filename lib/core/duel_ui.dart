import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';

export '../features/game/widgets/ball_painter.dart' show BallIcon;
import 'app_theme.dart';
import 'audio_service.dart';
import 'brand.dart';
import 'icon_motion.dart';

/// Look of the PikoPe lobby screens (client mockups): a dark blue pool hall,
/// neon-rimmed glass panels, silver display type.
class DuelColors {
  static const ink = Color(0xFF070A18);
  static const navy = Color(0xFF0E1433);
  static const glass = Color(0xE6101426);
  static const rim = Color(0xFF2B3566);
  static const rimLight = Color(0xFF4A5AA8);
  static const green = Color(0xFF3ED12F);
  static const purple = Color(0xFF7B4DFF);
  static const blue = Color(0xFF2F6BFF);
  static const gold = Color(0xFFFFC93C);
  static const red = Color(0xFFFF3B4E);
  static const silver = Color(0xFFE9ECF5);
  static const dim = Color(0xFF8E96B8);

  /// Accent of each bet level, low to high (green, red, blue, gold, purple).
  static const levels = [Color(0xFF35D05A), Color(0xFFFF4055), Color(0xFF3B6CFF), Color(0xFFE8D23A), Color(0xFFB04DFF)];
  static Color level(int i) => levels[i % levels.length];
}

/// 2450 -> "2,450"; with [compact], 10000 -> "10K", 1500000 -> "1.5M".
String formatCoins(int value, {bool compact = false}) {
  if (compact && value.abs() >= 10000) {
    String cut(double v, String unit) {
      final s = v >= 100 || v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
      return '$s$unit';
    }

    if (value.abs() >= 1000000000) return cut(value / 1000000000, 'B');
    if (value.abs() >= 1000000) return cut(value / 1000000, 'M');
    return cut(value / 1000, 'K');
  }
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Amount plus the Pico coin unit, e.g. "2,000 Pico coin".
String formatPicoCoins(int value, {bool compact = false}) => '${formatCoins(value, compact: compact)} ${PicoCoin.name}';

ui.Image? _hallImage;
bool _hallBakeFailed = false;

/// The pool hall behind every lobby screen, painted once at low resolution
/// (it is all soft light) and stretched.
ui.Image? _bakedHall() {
  if (_hallBakeFailed) return null;
  final cached = _hallImage;
  if (cached != null) return cached;
  const size = Size(800, 450);
  final rect = Offset.zero & size;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0B1030), Color(0xFF141C4A), Color(0xFF0A0F26), Color(0xFF05070F)],
        stops: [0, 0.38, 0.7, 1],
      ).createShader(rect),
  );
  void glow(Offset c, double r, Color color) => canvas.drawCircle(
        c,
        r,
        Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
  // Lamps and a neon sign somewhere at the back of the room.
  glow(const Offset(400, 120), 330, const Color(0x552F5BFF));
  glow(const Offset(650, 60), 150, const Color(0x55FF2D55));
  glow(const Offset(120, 90), 140, const Color(0x33FFB060));
  glow(const Offset(760, 230), 110, const Color(0x2238D0FF));
  // Out-of-focus lights.
  final random = Random(11);
  for (var i = 0; i < 26; i++) {
    final c = Offset(random.nextDouble() * 800, 20 + random.nextDouble() * 190);
    final hue = [const Color(0xFF7C9BFF), const Color(0xFFFF7A8C), const Color(0xFFFFD08A)][random.nextInt(3)];
    canvas.drawCircle(
        c,
        6 + random.nextDouble() * 18,
        Paint()
          ..color = hue.withValues(alpha: 0.03 + random.nextDouble() * 0.04)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }
  // The far rail and cloth of a table running off the bottom of the screen,
  // lit from above and falling into shadow toward the viewer.
  final cloth = Path()
    ..moveTo(-60, 450)
    ..lineTo(150, 268)
    ..lineTo(650, 268)
    ..lineTo(860, 450)
    ..close();
  canvas.drawPath(
    cloth,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF14463C), Color(0xFF0B2823), Color(0xFF040A0A)],
        stops: [0, 0.4, 1],
      ).createShader(const Rect.fromLTWH(0, 268, 800, 182)),
  );
  glow(const Offset(400, 300), 240, const Color(0x3348C8A0));
  canvas.drawPath(
    Path()
      ..moveTo(150, 268)
      ..lineTo(650, 268)
      ..lineTo(664, 256)
      ..lineTo(136, 256)
      ..close(),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2A3A86), Color(0xFF141B45)],
      ).createShader(const Rect.fromLTWH(136, 256, 528, 12)),
  );
  canvas.drawLine(
      const Offset(136, 256),
      const Offset(664, 256),
      Paint()
        ..color = const Color(0x886E8CFF)
        ..strokeWidth = 1);
  for (final x in const [250.0, 400.0, 550.0]) {
    canvas.drawCircle(Offset(x, 262), 1.6, Paint()..color = const Color(0x99DCE4FF));
  }
  // Two soft spotlight beams from lamps above the table.
  for (final beam in [(const Offset(300, -40), 130.0, 560.0), (const Offset(520, -40), 150.0, 560.0)]) {
    final (top, halfW, len) = beam;
    final path = Path()
      ..moveTo(top.dx - 14, top.dy)
      ..lineTo(top.dx + 14, top.dy)
      ..lineTo(top.dx + halfW, top.dy + len)
      ..lineTo(top.dx - halfW, top.dy + len)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0x2EFFFFFF), Color(0x12FFFFFF), Color(0x00FFFFFF)],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromLTWH(top.dx - halfW, top.dy, halfW * 2, len))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }
  // Darken the edges so panels read clearly anywhere.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const RadialGradient(
        radius: 0.95,
        colors: [Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
        stops: [0, 0.55, 1],
      ).createShader(rect),
  );
  final picture = recorder.endRecording();
  try {
    final image = picture.toImageSync(size.width.toInt(), size.height.toInt());
    picture.dispose();
    return _hallImage = image;
  } catch (_) {
    picture.dispose();
    _hallBakeFailed = true;
    return null;
  }
}

class _HallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final image = _bakedHall();
    final dest = Offset.zero & size;
    if (image == null) {
      canvas.drawRect(dest, Paint()..color = DuelColors.ink);
      return;
    }
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        dest, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_HallPainter old) => false;
}

/// The hall backdrop on its own, for screens that lay themselves out.
class DuelBackdrop extends StatelessWidget {
  const DuelBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _HallPainter(), child: child);
}

/// A lobby screen: the hall backdrop with a fixed 1600x900 layout on top.
class DuelCanvas extends StatelessWidget {
  const DuelCanvas({super.key, required this.child});

  static const size = Size(1600, 900);

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: DuelColors.ink,
        resizeToAvoidBottomInset: false,
        body: CustomPaint(
          painter: _HallPainter(),
          child: SafeArea(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox.fromSize(size: size, child: child),
              ),
            ),
          ),
        ),
      );
}

/// Dark glass panel with a coloured rim; [glow] lights the rim up. The fill
/// runs lighter at the top and darker at the bottom, like lit smoked glass.
BoxDecoration duelPanel({double radius = 22, Color rim = DuelColors.rim, double rimWidth = 2, bool glow = false, Color? fill}) {
  final base = fill ?? DuelColors.glass;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(base, Colors.white, 0.08)!, base, Color.lerp(base, Colors.black, 0.28)!],
      stops: const [0, 0.42, 1],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: rim, width: rimWidth),
    boxShadow: [
      const BoxShadow(color: Color(0xAA000000), blurRadius: 20, offset: Offset(0, 10)),
      BoxShadow(color: rim.withValues(alpha: glow ? 0.6 : 0.22), blurRadius: glow ? 32 : 12, spreadRadius: glow ? 1 : 0),
    ],
  );
}

/// A sheet of light across the top of a panel: lay it over a rounded box
/// (same [radius]) to make it read as polished glass. Ignores touches.
class DuelGloss extends StatelessWidget {
  const DuelGloss({super.key, this.radius = 22, this.strength = 0.14, this.diagonal = false});

  final double radius;
  final double strength;

  /// A diagonal sweep (cards) instead of a top-down sheet (panels).
  final bool diagonal;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: diagonal
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white.withValues(alpha: strength), Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: strength * 0.4)],
                      stops: const [0, 0.42, 0.75, 1],
                    )
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withValues(alpha: strength), Colors.white.withValues(alpha: strength * 0.25), Colors.white.withValues(alpha: 0)],
                      stops: const [0, 0.18, 0.5],
                    ),
            ),
          ),
        ),
      );
}

/// Gold PIKO token used anywhere coins are shown (balance, shop, history).
class PikoCoinIcon extends StatelessWidget {
  const PikoCoinIcon({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        PicoCoin.asset,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      );
}

class DuelLogo extends StatelessWidget {
  const DuelLogo({super.key, this.height = 78});

  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/pikope_logo.png',
        height: height,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => Text(
          'PikoPe',
          style: AppText.label(height * 0.22, color: DuelColors.gold, weight: FontWeight.w900),
        ),
      );
}

/// The premium currency: a purple casino chip.
class GemIcon extends StatelessWidget {
  const GemIcon({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _ChipPainter()));
}

class _ChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.47;
    canvas.drawCircle(c + Offset(0, r * 0.08), r, Paint()..color = const Color(0x80000000));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFF9D7BFF), Color(0xFF5B2FE0), Color(0xFF34128F)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..strokeWidth = r * 0.2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 8; i++) {
      final a = i * pi / 4;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.86), a - 0.16, 0.32, false, dash);
    }
    canvas.drawCircle(c, r * 0.62, Paint()..color = const Color(0xFF4521B8));
    canvas.drawCircle(
        c,
        r * 0.62,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.07
          ..color = Colors.white.withValues(alpha: 0.85));
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final a = -pi / 2 + i * pi / 5;
      final p = c + Offset(cos(a), sin(a)) * (i.isEven ? r * 0.36 : r * 0.16);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(star..close(), Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(_ChipPainter old) => false;
}

/// Wallet readout in the top bar: icon, amount, "+" (opens the shop).
class CurrencyPill extends StatelessWidget {
  const CurrencyPill({super.key, required this.icon, required this.amount, this.onAdd});

  final Widget icon;
  final int amount;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => PressScale(
        onTap: onAdd,
        enabled: onAdd != null,
        scale: 0.96,
        child: SizedBox(
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 50,
                margin: const EdgeInsets.only(left: 34),
                padding: const EdgeInsets.only(left: 52, right: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xEE1A2140), Color(0xEE070A16)]),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: DuelColors.rimLight.withValues(alpha: 0.8), width: 1.5),
                  boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 88),
                      child: Text(formatCoins(amount, compact: amount >= 10000000),
                          style: AppText.label(23, color: Colors.white, weight: FontWeight.w800).copyWith(shadows: const [Shadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1))])),
                    ),
                    if (onAdd != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.add_rounded, color: Color(0xFFFF8A3C), size: 30),
                    ],
                  ],
                ),
              ),
              Positioned(left: 0, child: icon),
            ],
          ),
        ),
      );
}

/// Square icon button of the bottom navigation row.
class NavTile extends StatelessWidget {
  const NavTile({super.key, required this.icon, required this.label, required this.onTap, this.active = false, this.badge = false});

  /// Two crossed cues, for the CUES tile (no stock icon shows that).
  static const cuesIcon = IconData(0);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final color = active ? DuelColors.green : const Color(0xFFB9BFD6);
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 132,
        height: 132,
        decoration: duelPanel(
          radius: 20,
          rim: active ? DuelColors.green : const Color(0xFF232A4A),
          glow: active,
          fill: active ? const Color(0xE60C2414) : const Color(0xCC0B0E1C),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: active
                        ? BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 26, spreadRadius: 4)])
                        : null,
                    child: icon == cuesIcon
                        ? CustomPaint(size: const Size.square(58), painter: _CrossedCuesPainter(color))
                        : Icon(icon, size: 58, color: color),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: AppText.label(15, color: color, weight: FontWeight.w700)),
                ],
              ),
            ),
            const DuelGloss(radius: 20, strength: 0.1),
            if (badge)
              Positioned(
                right: 14,
                top: 14,
                child: PulseBadge(child: CircleAvatar(radius: 8, backgroundColor: DuelColors.red)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pill-shaped glossy button of the mockups ("PLAY NOW", "SUBMIT").
class DuelButton extends StatefulWidget {
  const DuelButton({super.key, required this.label, required this.onPressed, this.color = DuelColors.green, this.width = 280, this.height = 62, this.fontSize = 26, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final double width;
  final double height;
  final double fontSize;
  final IconData? icon;

  @override
  State<DuelButton> createState() => _DuelButtonState();
}

class _DuelButtonState extends State<DuelButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                AudioService.tap();
                w.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 70),
          child: Container(
            width: w.width,
            height: w.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(w.color, Colors.white, 0.22)!, w.color, Color.lerp(w.color, Colors.black, 0.45)!],
                stops: const [0, 0.5, 1],
              ),
              borderRadius: BorderRadius.circular(w.height * 0.32),
              border: Border.all(color: Color.lerp(w.color, Colors.black, 0.55)!.withValues(alpha: 0.9), width: 1.5),
              boxShadow: [
                BoxShadow(color: w.color.withValues(alpha: 0.5), blurRadius: 22, spreadRadius: 1),
                const BoxShadow(color: Color(0xAA000000), blurRadius: 10, offset: Offset(0, 6)),
              ],
            ),
            child: Stack(
              children: [
                // Glossy cap over the top half.
                Positioned(
                  left: 2,
                  right: 2,
                  top: 2,
                  height: w.height * 0.46,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(w.height * 0.32)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white.withValues(alpha: 0.42), Colors.white.withValues(alpha: 0.08)],
                        ),
                      ),
                    ),
                  ),
                ),
                // Thin light rim inside the dark edge.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(w.height * 0.32 - 1.5),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.2),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (w.icon != null) ...[
                        Icon(w.icon, color: Colors.white, size: w.fontSize * 1.2),
                        SizedBox(width: w.fontSize * 0.4),
                      ],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(w.label,
                              maxLines: 1,
                              style: AppText.label(w.fontSize, color: Colors.white, weight: FontWeight.w900).copyWith(
                                letterSpacing: w.fontSize * 0.04,
                                shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 4, offset: Offset(0, 2))],
                              )),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Big silver display heading with the soft blue flare of the mockups.
class DuelTitle extends StatelessWidget {
  const DuelTitle(this.text, {super.key, this.size = 56, this.sub});

  final String text;
  final double size;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final style = AppText.label(size, color: Colors.white, weight: FontWeight.w900).copyWith(letterSpacing: size * 0.02);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // The glow and drop shadow, on an invisible copy of the text.
            Text(text,
                textAlign: TextAlign.center,
                style: style.copyWith(color: Colors.transparent, shadows: const [
                  Shadow(color: Color(0xBB3B6CFF), blurRadius: 30),
                  Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 4)),
                ])),
            // Brushed-metal face.
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (b) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Color(0xFFF2F4FB), Color(0xFFB9C4EE), Color(0xFFEDF0FA)],
                stops: [0, 0.45, 0.72, 1],
              ).createShader(b),
              child: Text(text, textAlign: TextAlign.center, style: style),
            ),
          ],
        ),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub!,
              textAlign: TextAlign.center,
              style: AppText.label(size * 0.4, color: Colors.white, weight: FontWeight.w700).copyWith(letterSpacing: 0.6, shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 4, offset: Offset(0, 2))])),
        ],
      ],
    );
  }
}

/// Small centred message box in the lobby style.
/// Shows a dialog scaled exactly like a [DuelCanvas] page, so dialogs laid
/// out in canvas units (fixed widths, big buttons) fit every phone. Plain
/// showDialog lays them out in the phone's own logical pixels: on a short
/// screen the content overflows the dialog box and the buttons at the
/// bottom, drawn outside it, never receive taps.
Future<T?> showDuelDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color barrierColor = const Color(0xB3000000),
  bool barrierDismissible = true,
}) =>
    showDialog<T>(
      context: context,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      builder: (context) => DuelDialogFrame(child: builder(context)),
    );

/// A canvas fitted to the screen with [child] centred in it. The canvas is
/// the page canvas shrunk by [zoom], so a dialog laid out in canvas units
/// shows [zoom] times larger than the same widths would on a page: dialogs
/// are small boxes and need to read well on a phone.
class DuelDialogFrame extends StatelessWidget {
  const DuelDialogFrame({super.key, required this.child});

  static const zoom = 1.65;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = DuelCanvas.size / zoom;
    return SafeArea(
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              // Dialogs size themselves from the "screen": give them the canvas.
              data: MediaQuery.of(context).copyWith(size: size, viewInsets: EdgeInsets.zero, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showDuelMessage(BuildContext context, {required String title, required String body, IconData icon = Icons.info_outline_rounded}) =>
    showDuelDialog<void>(
      context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final t = ref.watch(stringsProvider);
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(22),
              decoration: duelPanel(rim: DuelColors.rimLight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: DuelColors.gold, size: 38),
                  const SizedBox(height: 8),
                  Text(title, textAlign: TextAlign.center, style: AppText.label(18, weight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text(body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'sans-serif', fontSize: 14, height: 1.4, color: DuelColors.silver)),
                  const SizedBox(height: 16),
                  DuelButton(label: t.ok, width: 160, height: 42, fontSize: 16, onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          );
        },
      ),
    );

/// Two crossed cues as an icon.
class CrossedCuesIcon extends StatelessWidget {
  const CrossedCuesIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _CrossedCuesPainter(color));
}

class _CrossedCuesPainter extends CustomPainter {
  _CrossedCuesPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    void cue(Offset tip, Offset butt) {
      final v = butt - tip;
      final mid = tip + v * 0.55;
      canvas.drawLine(tip + v * 0.1, mid, Paint()
        ..color = color
        ..strokeWidth = s * 0.075
        ..strokeCap = StrokeCap.round);
      canvas.drawLine(mid, butt, Paint()
        ..color = color
        ..strokeWidth = s * 0.14
        ..strokeCap = StrokeCap.round);
      canvas.drawLine(tip, tip + v * 0.06, Paint()
        ..color = color
        ..strokeWidth = s * 0.075
        ..strokeCap = StrokeCap.round);
    }

    cue(Offset(s * 0.14, s * 0.14), Offset(s * 0.86, s * 0.86));
    cue(Offset(s * 0.86, s * 0.14), Offset(s * 0.14, s * 0.86));
  }

  @override
  bool shouldRepaint(_CrossedCuesPainter old) => old.color != color;
}
