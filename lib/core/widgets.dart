import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_state.dart';
import 'app_theme.dart';
import 'brand.dart';
import 'audio_service.dart';

/// Resolves an avatar reference: `asset:<name>` is bundled artwork,
/// `cld:<publicId>` is delivered by Cloudinary.
class AvatarImage extends ConsumerWidget {
  const AvatarImage(this.avatar, {super.key, required this.size});

  final String avatar;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.frame,
      child: Icon(Icons.person, size: size * 0.7, color: AppColors.text),
    );
    if (avatar.startsWith('cld:')) {
      final cloudinary = ref.watch(cloudinaryProvider);
      if (!cloudinary.isConfigured) return fallback;
      final px = (size * 2).round();
      return Image.network(
        cloudinary.imageUrl(avatar.substring(4), width: px, height: px),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    if (avatar.startsWith('url:')) {
      return Image.network(
        avatar.substring(4),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    if (!avatar.startsWith('asset:')) return fallback;
    return Image.asset(
      'assets/images/avatars/${avatar.substring(6)}.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// Rounded indigo-framed tile used for avatars, coins and menu buttons.
class FramedTile extends StatelessWidget {
  const FramedTile({
    super.key,
    required this.size,
    required this.child,
    this.frameColor = AppColors.frame,
    this.color = AppColors.panel,
    this.glow = false,
  });

  final double size;
  final Widget child;
  final Color frameColor;
  final Color color;

  /// Halo in the frame colour (active player, winner).
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.2;
    final rim = size * 0.065;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(rim),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(frameColor, Colors.white, 0.3)!, Color.lerp(frameColor, Colors.black, 0.25)!],
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          const BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
          if (glow) BoxShadow(color: frameColor.withValues(alpha: 0.65), blurRadius: size * 0.28),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius * 0.7),
        child: ColoredBox(color: color, child: child),
      ),
    );
  }
}

class CoinsTile extends StatelessWidget {
  const CoinsTile({
    super.key,
    required this.coins,
    this.size = 120,
    this.emphasis = false,
  });

  final int coins;
  final double size;
  /// Larger coin art and prize digits (in-match pot display).
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final coinH = size * (emphasis ? 0.46 : 0.5);
    final digits = size * (emphasis ? 0.28 : 0.2);
    return FramedTile(
      size: size,
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(PicoCoin.asset, height: coinH, filterQuality: FilterQuality.medium),
          FittedBox(
            child: Text('$coins',
                style: AppText.label(digits, color: AppColors.gold, weight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

/// Staked-match prize pot (carrom, ludo, pool, billiard poker — same size everywhere).
class MatchPrizeTile extends StatelessWidget {
  const MatchPrizeTile({super.key, required this.prize});

  final int prize;

  static const double size = 132;

  @override
  Widget build(BuildContext context) {
    return CoinsTile(coins: prize, size: size, emphasis: true);
  }
}

/// Chunky arcade button: top-lit face on a darker lip that sinks when pressed.
class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.active,
    this.width,
    this.height = 64,
    this.fontSize = 20,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final double? width;
  final double height;
  final double fontSize;

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onPressed != null;
    final color = w.color;
    final fg = color.computeLuminance() > 0.4 ? const Color(0xFF10131A) : Colors.white;
    final radius = BorderRadius.circular(w.height * 0.3);
    final lip = w.height * 0.09;
    final sink = _down ? lip : 0.0;
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
        child: SizedBox(
          width: w.width,
          height: w.height + lip,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: lip,
                height: w.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(color, Colors.black, 0.45),
                    borderRadius: radius,
                    boxShadow: const [
                      BoxShadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 6)),
                    ],
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 70),
                left: 0,
                right: 0,
                top: sink,
                height: w.height,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: w.height * 0.4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(color, Colors.white, 0.28)!, color, Color.lerp(color, Colors.black, 0.12)!],
                      stops: const [0, 0.55, 1],
                    ),
                    borderRadius: radius,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (w.icon != null) ...[
                        Icon(w.icon, color: fg, size: w.fontSize * 1.3),
                        SizedBox(width: w.fontSize * 0.5),
                      ],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(w.label,
                              maxLines: 1,
                              style: AppText.label(w.fontSize, color: fg, weight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dark room backdrop with the faint slab seams of the mockups.
class RoomBackground extends StatelessWidget {
  const RoomBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _RoomPainter(), child: child);
}

ui.Image? _roomImage;

/// Lamp glow and vignette are smooth full-screen gradients: bake them once
/// at low resolution and stretch, instead of shading every pixel per frame.
ui.Image _bakedRoom() {
  final cached = _roomImage;
  if (cached != null) return cached;
  const size = Size(640, 360);
  final rect = Offset.zero & size;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.05),
        radius: 0.85,
        colors: [Color(0xFF34343F), Color(0xFF23232A), Color(0xFF131316)],
        stops: [0, 0.55, 1],
      ).createShader(rect),
  );
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const RadialGradient(
        radius: 1.05,
        colors: [Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
        stops: [0, 0.6, 1],
      ).createShader(rect),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(size.width.toInt(), size.height.toInt());
  picture.dispose();
  return _roomImage = image;
}

class _RoomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final image = _bakedRoom();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
    final seam = Paint()
      ..color = const Color(0x1F000000)
      ..strokeWidth = 2;
    for (final f in const [0.31, 0.69]) {
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), seam);
    }
    for (final f in const [0.33, 0.67]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), seam);
    }
  }

  @override
  bool shouldRepaint(_RoomPainter old) => false;
}

/// Lays a fixed 1600x900 design canvas onto any landscape screen.
class DesignCanvas extends StatelessWidget {
  const DesignCanvas({super.key, required this.child, this.size = menuSize});

  /// 16:9 canvas of the menu screens.
  static const menuSize = Size(1600, 900);

  /// Wider canvas of the match screens, matching modern phone screens so the
  /// table can fill them.
  static const tableSize = Size(1950, 900);

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) => RoomBackground(
        child: SafeArea(
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox.fromSize(size: size, child: child),
            ),
          ),
        ),
      );
}
