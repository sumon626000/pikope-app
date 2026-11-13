import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';
import '../../core/widgets.dart';
import '../../data/demo_data.dart';
import '../game/widgets/ball_painter.dart' show paintBall;
import '../game/widgets/table_art.dart' show paintProTable;

/// Building blocks of the portrait home in the Pool City look. Everything is
/// laid out in design units on a [PortraitCanvas] 1080 wide; geometry and
/// colours follow the reference app's home screen (1080×2340).

// -------------------------------------------------------------------- text

/// Title Case for home labels ("Play Pool", "Daily Bonus") — the reference
/// app's casing. Bangla and roman numerals are left alone.
String titleCase(String s) {
  if (s.runes.any((r) => r > 0x24F)) return s;
  return s
      .replaceAll('\n', ' ')
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((w) {
        if (w.isEmpty) return w;
        if (RegExp(r'^(i|ii|iii|iv|v|vi)$').hasMatch(w)) return w.toUpperCase();
        return w[0].toUpperCase() + w.substring(1);
      })
      .join(' ');
}

/// Rubik, bold by default, with the soft dark drop shadow every home label has.
TextStyle pcText(
  double size, {
  Color color = Colors.white,
  FontWeight weight = FontWeight.w700,
  bool shadow = true,
}) => TextStyle(
  fontFamily: DesignTypography.poolCityFont,
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: 1.1,
  shadows: shadow
      ? const [
          Shadow(color: Color(0xB3000000), blurRadius: 6, offset: Offset(0, 2)),
        ]
      : null,
);

// ------------------------------------------------------------------ canvas

/// Portrait page: 1080 design units wide; the height follows the screen so
/// the layout can spread with Spacers. Below [minHeight] the page scrolls
/// instead of squeezing.
///
/// On wide desktop / tablet landscape viewports the canvas is capped to a
/// phone column and centered so UI does not stretch edge-to-edge.
class PortraitCanvas extends StatelessWidget {
  const PortraitCanvas({
    super.key,
    required this.builder,
    this.minHeight = 1800,
  });

  static const width = 1080.0;

  /// Above this viewport width, use a centered phone column instead of full bleed.
  static const wideBreakpoint = 700.0;

  /// Max logical width of the phone column on desktop / large web.
  static const phoneColumnMaxWidth = 420.0;

  /// Popups on desktop: slightly narrower than the home column so they feel
  /// like modals, not a second full phone screen.
  static const dialogColumnMaxWidth = 360.0;

  final double minHeight;

  /// Receives the canvas height in design units.
  final Widget Function(BuildContext context, double height) builder;

  /// Width used to scale the 1080 design canvas for [viewportWidth].
  static double columnWidthFor(double viewportWidth) {
    if (viewportWidth >= wideBreakpoint) {
      return min(phoneColumnMaxWidth, viewportWidth);
    }
    return viewportWidth;
  }

  /// Width used to scale dialogs / choosers (tighter on desktop web).
  static double dialogColumnWidthFor(double viewportWidth) {
    if (viewportWidth >= wideBreakpoint) {
      return min(dialogColumnMaxWidth, viewportWidth);
    }
    return viewportWidth;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DesignColors.pcInk,
    resizeToAvoidBottomInset: false,
    body: Stack(
      fit: StackFit.expand,
      children: [
        // Own layer: the animations above must not repaint the hall.
        const RepaintBoundary(
          child: CustomPaint(painter: PoolCityBackdropPainter()),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final columnW = columnWidthFor(c.maxWidth);
              final scale = columnW / width;
              final fit = c.maxHeight / scale;
              final height = max(minHeight, fit);
              final canvas = FittedBox(
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: builder(context, height),
                ),
              );
              final body = fit < minHeight
                  ? SingleChildScrollView(child: canvas)
                  : canvas;
              if (columnW >= c.maxWidth - 0.5) return body;
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: columnW,
                  height: c.maxHeight,
                  child: body,
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

ui.Image? _backdrop;
bool _backdropFailed = false;

/// Blue cloth, dark wine rails and chrome, like the table behind the
/// reference home.
const _backdropTable = TableStyle(
  cloth: Color(0xFF3B79B4),
  clothDark: Color(0xFF1C4A86),
  rail: Color(0xFF7A3F44),
  railDark: Color(0xFF3E1F26),
  metal: Color(0xFFD5D8DF),
  metalDark: Color(0xFF7D838E),
  sight: Color(0xFFFFFFFF),
);

/// The hall behind the home: purple light at the top with the brand
/// watermark, an out-of-focus pool table running off the bottom. Baked once
/// at half resolution and stretched.
ui.Image? _bakedBackdrop() {
  if (_backdropFailed) return null;
  final cached = _backdrop;
  if (cached != null) return cached;
  const size = Size(540, 1170);
  final rect = Offset.zero & size;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          DesignColors.pcInk,
          DesignColors.pcPlum,
          DesignColors.pcMagenta,
          DesignColors.pcViolet,
          Color(0xFF3A2A5C),
          DesignColors.pcNavyLow,
          DesignColors.pcNavyBottom,
        ],
        stops: [0, 0.16, 0.36, 0.5, 0.62, 0.82, 1],
      ).createShader(rect),
  );
  void glow(Offset c, double r, Color color) => canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );
  glow(
    const Offset(270, 330),
    300,
    DesignColors.pcRibbonDeep.withValues(alpha: 0.42),
  );
  glow(const Offset(70, 150), 170, const Color(0x443B6CFF));

  // --- out-of-focus table, seen from the near end, blurred in screen space
  canvas.saveLayer(
    const Rect.fromLTWH(-200, 480, 940, 700),
    Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
  );
  canvas.save();
  final m = Matrix4.identity()
    ..setEntry(3, 2, 0.0016)
    ..rotateX(-1.05)
    ..rotateZ(-0.22);
  canvas.translate(250, 930);
  canvas.transform(m.storage);
  canvas.scale(2.9);
  canvas.translate(-300, -175);
  paintProTable(canvas, const Size(600, 351), _backdropTable);
  for (final (x, y, n) in const [
    (410.0, 130.0, 1),
    (455.0, 165.0, 3),
    (380.0, 215.0, 8),
    (470.0, 230.0, 5),
    (330.0, 150.0, 12),
    (240.0, 240.0, 0),
  ]) {
    paintBall(canvas, Offset(x, y), 7.2, n);
  }
  canvas.restore();
  canvas.restore();

  // --- brand watermark where the reference shows its logo
  final mark = TextPainter(
    text: TextSpan(
      text: 'PikoPe',
      style: TextStyle(
        fontFamily: DesignTypography.poolCityFont,
        fontSize: 118,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.055),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  mark.paint(canvas, Offset(270 - mark.width / 2, 240 - mark.height / 2));
  paintCrown(
    canvas,
    const Rect.fromLTWH(200, 95, 140, 90),
    Colors.white.withValues(alpha: 0.05),
  );

  // Darken the edges so panels read clearly.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const RadialGradient(
        radius: 1.05,
        colors: [Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
        stops: [0, 0.5, 1],
      ).createShader(rect),
  );
  final picture = recorder.endRecording();
  try {
    final image = picture.toImageSync(size.width.toInt(), size.height.toInt());
    picture.dispose();
    return _backdrop = image;
  } catch (_) {
    picture.dispose();
    _backdropFailed = true;
    return null;
  }
}

class PoolCityBackdropPainter extends CustomPainter {
  const PoolCityBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final image = _bakedBackdrop();
    final dest = Offset.zero & size;
    if (image == null) {
      canvas.drawRect(dest, Paint()..color = DesignColors.pcInk);
      return;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dest,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(PoolCityBackdropPainter old) => false;
}

/// Five-point crown filling [r]; gold unless [color] is given.
void paintCrown(Canvas canvas, Rect r, [Color? color]) {
  final w = r.width, h = r.height;
  final crown = Path()
    ..moveTo(r.left + w * 0.12, r.bottom)
    ..lineTo(r.left + w * 0.02, r.top + h * 0.3)
    ..lineTo(r.left + w * 0.3, r.top + h * 0.55)
    ..lineTo(r.left + w * 0.5, r.top + h * 0.02)
    ..lineTo(r.left + w * 0.7, r.top + h * 0.55)
    ..lineTo(r.left + w * 0.98, r.top + h * 0.3)
    ..lineTo(r.left + w * 0.88, r.bottom)
    ..close();
  if (color != null) {
    canvas.drawPath(crown, Paint()..color = color);
    return;
  }
  canvas.drawPath(
    crown.shift(Offset(0, h * 0.08)),
    Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.06),
  );
  canvas.drawPath(
    crown,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFF0A8), Color(0xFFF5B942), Color(0xFFB8741A)],
      ).createShader(r),
  );
  canvas.drawPath(
    crown,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, h * 0.025)
      ..color = const Color(0xFF8A4A1E),
  );
  canvas.drawRect(
    Rect.fromLTWH(r.left + w * 0.12, r.top + h * 0.8, w * 0.76, h * 0.2),
    Paint()..color = const Color(0xFFD9A35A),
  );
  for (final x in [0.02, 0.5, 0.98]) {
    canvas.drawCircle(
      Offset(r.left + w * x, r.top + h * (x == 0.5 ? 0.02 : 0.3)),
      w * 0.045,
      Paint()..color = const Color(0xFFE53950),
    );
  }
}

/// Glass fill shared by the round / square shortcut buttons.
BoxDecoration _shortcutFill({
  BoxShape shape = BoxShape.circle,
  double radius = 18,
}) => BoxDecoration(
  shape: shape,
  borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(radius),
  gradient: const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF5A4A9C), Color(0xFF3A2A74)],
  ),
  border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 2),
  boxShadow: const [
    BoxShadow(color: Color(0x99000000), blurRadius: 14, offset: Offset(0, 6)),
  ],
);

// ----------------------------------------------------------------- top bar

/// Avatar with level star, the wallet bar, mail / bell / settings.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    super.key,
    required this.avatar,
    required this.registered,
    required this.level,
    required this.coins,
    required this.gems,
    required this.placeholder,
    required this.unread,
    required this.onProfile,
    required this.onWallet,
    required this.onMail,
    required this.onBell,
    required this.onSettings,
  });

  final String avatar;
  final bool registered;
  final int level;
  final int? coins;
  final int? gems;
  final String placeholder;
  final int unread;
  final VoidCallback onProfile;
  final VoidCallback onWallet;
  final VoidCallback onMail;
  final VoidCallback onBell;
  final VoidCallback onSettings;

  static const height = 150.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Row(
      children: [
        const SizedBox(width: 18),
        _AvatarButton(
          avatar: avatar,
          registered: registered,
          level: level,
          onTap: onProfile,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Center(
            child: HomeWalletBar(
              coins: coins,
              gems: gems,
              placeholder: placeholder,
              onAdd: onWallet,
            ),
          ),
        ),
        _TopIcon(Icons.email_rounded, onMail),
        _TopIcon(Icons.notifications_rounded, onBell, badge: unread),
        _TopIcon(Icons.settings_rounded, onSettings),
        const SizedBox(width: 10),
      ],
    ),
  );
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({
    required this.avatar,
    required this.registered,
    required this.level,
    required this.onTap,
  });

  final String avatar;
  final bool registered;
  final int level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.94,
    child: SizedBox(
      width: 122,
      height: 124,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 6,
            top: 10,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFD4FF), width: 3),
                color: const Color(0xFF2A1C5E),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA000000),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: registered
                    ? AvatarImage(avatar, size: 104)
                    : const ColoredBox(
                        color: Color(0xFF1A1240),
                        child: Icon(
                          Icons.person_rounded,
                          color: DesignColors.pcTextDim,
                          size: 72,
                        ),
                      ),
              ),
            ),
          ),
          if (registered)
            Positioned(
              left: -6,
              top: -4,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFF8A4A1E),
                      size: 58,
                    ),
                    const Icon(
                      Icons.star_rounded,
                      color: DesignColors.pcGold,
                      size: 50,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '$level',
                        style: pcText(
                          level >= 100 ? 16 : 22,
                          color: const Color(0xFF5A2E00),
                          shadow: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _TopIcon extends StatelessWidget {
  const _TopIcon(this.icon, this.onTap, {this.badge = 0});

  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.9,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            icon,
            color: const Color(0xFFF2F4FB),
            size: 66,
            shadows: const [
              Shadow(
                color: Color(0xAA000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          if (badge > 0)
            Positioned(right: -10, top: -8, child: _CountBadge(badge)),
        ],
      ),
    ),
  );
}

/// One dark bar holding the wallets: [gems] (premium chip) and [coins], each
/// with a green "+" that opens the shop. Signed out: a single sign-in cell.
class HomeWalletBar extends StatelessWidget {
  const HomeWalletBar({
    super.key,
    required this.coins,
    required this.gems,
    required this.placeholder,
    required this.onAdd,
  });

  final int? coins;
  final int? gems;
  final String placeholder;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onAdd,
    scale: 0.97,
    child: Container(
      height: 64,
      padding: const EdgeInsets.only(left: 40, right: 5),
      decoration: BoxDecoration(
        color: DesignColors.pcPill.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (gems != null) ...[
            _WalletCell(
              icon: const GemIcon(size: 74),
              text: formatCoins(gems!, compact: gems! >= 10000000),
            ),
            const SizedBox(width: 34),
          ],
          _WalletCell(
            icon: const PikoCoinIcon(size: 76),
            text: coins != null
                ? formatCoins(coins!, compact: coins! >= 10000000)
                : placeholder,
            small: coins == null,
          ),
        ],
      ),
    ),
  );
}

class _WalletCell extends StatelessWidget {
  const _WalletCell({
    required this.icon,
    required this.text,
    this.small = false,
  });

  final Widget icon;
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Transform.translate(offset: const Offset(-28, 0), child: icon),
      Transform.translate(
        offset: const Offset(-10, 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: small ? 0 : 120),
          child: Text(
            small ? titleCase(text) : text,
            textAlign: TextAlign.center,
            style: pcText(small ? 24 : 36),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF34C25A), Color(0xFF1C9A40)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 46),
      ),
    ],
  );
}

// ------------------------------------------------------------- shortcuts

/// Round shortcut with its label laid over the lower half of the disc
/// (right column: Match Boost / Daily Bonus in the reference).
class HomeRoundButton extends StatelessWidget {
  const HomeRoundButton({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.dot = false,
    this.count = 0,
    this.attention = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;
  final bool dot;
  final int count;
  final bool attention;

  static const size = 124.0;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    enabled: onTap != null,
    scale: 0.94,
    child: IdleAttentionScale(
      active: attention,
      child: SizedBox(
        width: 150,
        height: 150,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 0,
              child: Container(
                width: size,
                height: size,
                decoration: _shortcutFill(),
                alignment: const Alignment(0, -0.55),
                child: Icon(
                  icon,
                  size: 58,
                  color: iconColor,
                  shadows: const [
                    Shadow(
                      color: Color(0x99000000),
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: -10,
              right: -10,
              top: 76,
              child: Text(
                titleCase(label),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: pcText(28).copyWith(
                  height: 1.0,
                  shadows: const [
                    Shadow(
                      color: Color(0xE6000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                    Shadow(color: Color(0xCC000000), blurRadius: 10),
                  ],
                ),
              ),
            ),
            if (dot)
              Positioned(
                left: 14,
                top: 8,
                child: PulseBadge(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DuelColors.red,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                  ),
                ),
              ),
            if (count > 0)
              Positioned(right: 4, top: -2, child: _CountBadge(count)),
          ],
        ),
      ),
    ),
  );
}

/// Square icon-only shortcut (left column: the "NEW" clipboard and friends).
class HomeSquareButton extends StatelessWidget {
  const HomeSquareButton({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.tag,
    this.size = 100,
  });

  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final double size;

  /// Small red tag on the corner ("NEW").
  final String? tag;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.94,
    child: SizedBox(
      width: size + 16,
      height: size + 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 6,
            top: 8,
            child: Container(
              width: size,
              height: size,
              decoration: _shortcutFill(
                shape: BoxShape.rectangle,
                radius: size * 0.2,
              ),
              child: Icon(
                icon,
                size: size * 0.58,
                color: iconColor,
                shadows: const [
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
          if (tag != null)
            Positioned(
              right: -14,
              top: -4,
              child: Transform.rotate(
                angle: -0.2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF03A4E),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x88000000),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(tag!, style: pcText(22, shadow: false)),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => PulseBadge(
    minScale: 0.94,
    maxScale: 1.08,
    child: Container(
      constraints: const BoxConstraints(minWidth: 40),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF03A4E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x88000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: pcText(24, shadow: false),
      ),
    ),
  );
}

// ------------------------------------------------------------------- rank

/// Gem emblem, rank ribbon and the player's own row — the centre of the home.
class RankBlock extends StatelessWidget {
  const RankBlock({
    super.key,
    required this.registered,
    required this.tier,
    required this.rankName,
    required this.position,
    required this.avatar,
    required this.name,
    required this.coins,
    required this.onTap,
  });

  final bool registered;
  final int tier;
  final String rankName;

  /// Left cell of the row: level (the reference shows the ladder position).
  final String position;
  final String avatar;
  final String name;
  final String coins;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.98,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          height: 190,
          child: CustomPaint(
            painter: RankEmblemPainter(registered ? tier : -1),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -14),
          child: SizedBox(
            width: 650,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const CustomPaint(
                  size: Size(650, 92),
                  painter: _RibbonPainter(),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 10,
                    left: 90,
                    right: 90,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      titleCase(rankName),
                      style: pcText(60).copyWith(letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -14),
          child: Container(
            width: 520,
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  DesignColors.pcPanelLighter,
                  DesignColors.pcPanelLight,
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFB9A8FF).withValues(alpha: 0.6),
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(position, style: pcText(44)),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF9FE4FF),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: registered
                        ? AvatarImage(avatar, size: 54)
                        : const SizedBox(
                            width: 54,
                            height: 54,
                            child: ColoredBox(
                              color: Color(0xFF1A1240),
                              child: Icon(
                                Icons.person_rounded,
                                color: DesignColors.pcTextDim,
                                size: 40,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: pcText(34),
                  ),
                ),
                Text(coins, style: pcText(36)),
                const SizedBox(width: 8),
                const PikoCoinIcon(size: 50),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Faceted gem in the rank tier's colour, in a bronze bezel with a small
/// crown; -1 is the grey "not signed in" gem.
class RankEmblemPainter extends CustomPainter {
  const RankEmblemPainter(this.tier);

  final int tier;

  static const _metals = [
    [Color(0xFFE39A5B), Color(0xFF8A4A1E)], // bronze
    [Color(0xFFE6EAF2), Color(0xFF7D8696)], // silver
    [Color(0xFFFFD75A), Color(0xFFC77A0A)], // gold
    [Color(0xFF9FF3F0), Color(0xFF2C8C96)], // platinum
    [Color(0xFF4DF08A), Color(0xFF0E8A3A)], // diamond (reference: green gem)
  ];
  static const _grey = [Color(0xFF9EA3B8), Color(0xFF4A4F66)];

  @override
  void paint(Canvas canvas, Size size) {
    final metal = tier < 0 ? _grey : _metals[tier.clamp(0, _metals.length - 1)];
    final w = size.width, h = size.height;
    final c = Offset(w / 2, h * 0.56);
    final rx = w * 0.44, ry = h * 0.38;
    Path rhombus(double sx, double sy, [Offset shift = Offset.zero]) => Path()
      ..moveTo(c.dx + shift.dx, c.dy - ry * sy + shift.dy)
      ..lineTo(c.dx + rx * sx + shift.dx, c.dy + shift.dy)
      ..lineTo(c.dx + shift.dx, c.dy + ry * sy + shift.dy)
      ..lineTo(c.dx - rx * sx + shift.dx, c.dy + shift.dy)
      ..close();
    canvas.drawPath(
      rhombus(1.1, 1.1, const Offset(0, 8)),
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Bronze bezel with its own facets.
    final bezelRect = Rect.fromCenter(
      center: c,
      width: rx * 2.2,
      height: ry * 2.2,
    );
    canvas.drawPath(
      rhombus(1.1, 1.1),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF0C27A),
            Color(0xFFB87333),
            Color(0xFF6E3B14),
            Color(0xFFD9A35A),
          ],
          stops: [0, 0.35, 0.7, 1],
        ).createShader(bezelRect),
    );
    canvas.drawPath(
      rhombus(1.1, 1.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF4A2608),
    );
    // Gem face.
    final face = Rect.fromCenter(
      center: c,
      width: rx * 1.76,
      height: ry * 1.76,
    );
    canvas.drawPath(
      rhombus(0.88, 0.88),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(metal[0], Colors.white, 0.4)!,
            metal[0],
            metal[1],
          ],
          stops: const [0, 0.4, 1],
        ).createShader(face),
    );
    final gx = rx * 0.88, gy = ry * 0.88;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - gy)
        ..lineTo(c.dx - gx, c.dy)
        ..lineTo(c.dx, c.dy)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + gy)
        ..lineTo(c.dx + gx, c.dy)
        ..lineTo(c.dx, c.dy)
        ..close(),
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
    canvas.drawPath(
      rhombus(0.46, 0.46),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset(c.dx - gx * 0.32, c.dy - gy * 0.36),
      w * 0.05,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Crown sitting in the bezel's top point; a drop at the bottom point.
    paintCrown(
      canvas,
      Rect.fromCenter(
        center: Offset(c.dx, c.dy - gy * 0.62),
        width: w * 0.3,
        height: h * 0.14,
      ),
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + ry * 1.1)
        ..lineTo(c.dx + w * 0.05, c.dy + ry * 1.1 + h * 0.06)
        ..lineTo(c.dx, c.dy + ry * 1.1 + h * 0.12)
        ..lineTo(c.dx - w * 0.05, c.dy + ry * 1.1 + h * 0.06)
        ..close(),
      Paint()..color = const Color(0xFFB87333),
    );
  }

  @override
  bool shouldRepaint(RankEmblemPainter old) => old.tier != tier;
}

/// Pink banner with notched tails: 580 body, 35 tails, darker base band.
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const inset = 35.0;
    final body = Rect.fromLTRB(inset, 6, w - inset, h - 10);
    void tail(bool left) {
      final x0 = left ? 0.0 : w;
      final x1 = left ? inset + 10 : w - inset - 10;
      final notch = left ? 22.0 : w - 22.0;
      final p = Path()
        ..moveTo(x0, 22)
        ..lineTo(x1, 22)
        ..lineTo(x1, h)
        ..lineTo(x0, h)
        ..lineTo(notch, h / 2 + 11)
        ..close();
      canvas.drawPath(
        p.shift(const Offset(0, 4)),
        Paint()..color = const Color(0x77000000),
      );
      canvas.drawPath(p, Paint()..color = DesignColors.pcRibbonEdge);
      final fold = Path()
        ..moveTo(left ? inset : w - inset, h - 10)
        ..lineTo(left ? inset + 10 : w - inset - 10, h - 2)
        ..lineTo(left ? inset + 10 : w - inset - 10, h - 10)
        ..close();
      canvas.drawPath(fold, Paint()..color = const Color(0xFF5A0330));
    }

    tail(true);
    tail(false);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        body.shift(const Offset(0, 6)),
        const Radius.circular(4),
      ),
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFEA4A9B),
            DesignColors.pcRibbon,
            DesignColors.pcRibbonDeep,
          ],
          stops: [0, 0.3, 1],
        ).createShader(body),
    );
    // Darker base band and a light top edge.
    canvas.drawRect(
      Rect.fromLTRB(body.left, body.bottom - 12, body.right, body.bottom),
      Paint()..color = const Color(0xFFA5125F),
    );
    canvas.drawLine(
      Offset(body.left + 4, body.top + 2),
      Offset(body.right - 4, body.top + 2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => false;
}

// ------------------------------------------------------------------ tiles

/// Big game tile: a rectangle whose inner edge leans 32px (the two tiles
/// share one slanted gap), art on top, the label along the bottom.
class HeroTile extends StatelessWidget {
  const HeroTile({
    super.key,
    required this.width,
    required this.height,
    required this.colors,
    required this.label,
    required this.art,
    required this.onTap,
    required this.slantRight,
    this.crown = false,
    this.artInsets = const EdgeInsets.fromLTRB(30, 0, 60, 80),
  });

  final double width;
  final double height;
  final List<Color> colors;
  final String label;
  final Widget art;
  final VoidCallback onTap;

  /// true: the right edge leans (left tile); false: the left edge leans.
  final bool slantRight;
  final bool crown;
  final EdgeInsets artInsets;

  static const slant = 32.0;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.97,
    child: SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _TrapezoidTilePainter(colors, slantRight),
            ),
          ),
          Positioned(
            left: artInsets.left + (slantRight ? 0 : slant),
            right: artInsets.right + (slantRight ? slant : 0),
            top: artInsets.top,
            bottom: artInsets.bottom,
            child: art,
          ),
          Positioned(
            left: slantRight ? 50 : 50 + slant * 0.5,
            right: 30,
            bottom: 20,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  titleCase(label),
                  style: pcText(66).copyWith(
                    shadows: const [
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                      Shadow(
                        color: Color(0x88000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (crown)
            Positioned(
              right: 110,
              top: -58,
              child: SizedBox(
                width: 160,
                height: 96,
                child: CustomPaint(painter: _CrownWidgetPainter()),
              ),
            ),
        ],
      ),
    ),
  );
}

class _TrapezoidTilePainter extends CustomPainter {
  const _TrapezoidTilePainter(this.colors, this.slantRight);

  final List<Color> colors;
  final bool slantRight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const s = HeroTile.slant;
    final shape = slantRight
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(w, 0)
            ..lineTo(w - s, h)
            ..lineTo(0, h)
            ..close())
        : (Path()
            ..moveTo(s, 0)
            ..lineTo(w, 0)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close());
    canvas.drawPath(
      shape.shift(const Offset(0, 14)),
      Paint()
        ..color = const Color(0xBB000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    final rect = Offset.zero & size;
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(colors[0], Colors.white, 0.1)!,
            colors[0],
            colors[1],
          ],
          stops: const [0, 0.4, 1],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipPath(shape);
    // Diagonal halftone like the reference art.
    final dot = Paint()..color = Colors.black.withValues(alpha: 0.09);
    var row = 0;
    for (var y = 16.0; y < h; y += 15, row++) {
      final shift = row.isEven ? 0.0 : 7.5;
      final rr = (1.2 + 1.6 * (y / h)).clamp(0.6, 3.0);
      for (var x = 0.0; x < w; x += 15) {
        canvas.drawCircle(Offset(x + shift, y), rr, dot);
      }
    }
    // Light sweep across the upper-left.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.26),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0, 0.55],
        ).createShader(rect),
    );
    canvas.restore();
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.42),
    );
  }

  @override
  bool shouldRepaint(_TrapezoidTilePainter old) =>
      old.colors != colors || old.slantRight != slantRight;
}

class _CrownWidgetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      paintCrown(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_CrownWidgetPainter old) => false;
}

/// Rack of fifteen balls in a wooden triangle, tilted like the reference.
class RackArt extends StatelessWidget {
  const RackArt({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _RackArtPainter());
}

class _RackArtPainter extends CustomPainter {
  const _RackArtPainter();

  static const _order = [7, 10, 4, 2, 8, 14, 11, 5, 15, 6, 3, 12, 13, 1, 9];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.translate(w / 2, h / 2 + h * 0.02);
    canvas.rotate(0.3);
    canvas.scale(1, 0.9);
    final r = min(w / 12.8, h / 10.2);
    final apex = Offset(0, -r * 3.5);
    final tri = Path()
      ..moveTo(apex.dx, apex.dy - r * 2.1)
      ..lineTo(apex.dx + r * 6.9, apex.dy + r * 8.4)
      ..lineTo(apex.dx - r * 6.9, apex.dy + r * 8.4)
      ..close();
    canvas.drawPath(
      tri.shift(Offset(0, r * 0.7)),
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
    );
    canvas.drawPath(
      tri,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD9A35A), Color(0xFFA86A2A), Color(0xFF6E3E14)],
        ).createShader(tri.getBounds()),
    );
    canvas.drawPath(
      tri,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.22
        ..color = const Color(0xFFE9C98F).withValues(alpha: 0.7),
    );
    var k = 0;
    for (var row = 0; row < 5; row++) {
      for (var i = 0; i <= row; i++) {
        final x = apex.dx + (i - row / 2) * r * 2.08;
        final y = apex.dy + row * r * 1.8;
        paintBall(canvas, Offset(x, y), r * 0.98, _order[k++]);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RackArtPainter old) => false;
}

/// Ludo hero art: a tilted board behind a big white die and two pawns,
/// drawn with 3D shading like the reference's balls.
class LudoHeroArt extends StatelessWidget {
  const LudoHeroArt({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _LudoHeroPainter());
}

class _LudoHeroPainter extends CustomPainter {
  const _LudoHeroPainter();

  static const _cols = [
    Color(0xFFE0333B),
    Color(0xFF2FA84F),
    Color(0xFFE8B91C),
    Color(0xFF2F6BDC),
  ];

  void _pawn(Canvas canvas, Offset base, double h, Color color) {
    final r = h * 0.22;
    final dark = Color.lerp(color, Colors.black, 0.45)!;
    final light = Color.lerp(color, Colors.white, 0.45)!;
    // Shadow on the board.
    canvas.drawOval(
      Rect.fromCenter(
        center: base + Offset(h * 0.06, h * 0.04),
        width: r * 2.6,
        height: r * 1.1,
      ),
      Paint()
        ..color = const Color(0x77000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4),
    );
    // Base disc, body, head.
    canvas.drawOval(
      Rect.fromCenter(center: base, width: r * 2.4, height: r),
      Paint()..color = dark,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: base - Offset(0, r * 0.12),
        width: r * 2.4,
        height: r,
      ),
      Paint()
        ..shader = LinearGradient(colors: [light, color, dark]).createShader(
          Rect.fromCenter(center: base, width: r * 2.4, height: r),
        ),
    );
    final body = Path()
      ..moveTo(base.dx - r * 1.0, base.dy - r * 0.1)
      ..quadraticBezierTo(
        base.dx - r * 0.25,
        base.dy - h * 0.45,
        base.dx - r * 0.42,
        base.dy - h * 0.62,
      )
      ..lineTo(base.dx + r * 0.42, base.dy - h * 0.62)
      ..quadraticBezierTo(
        base.dx + r * 0.25,
        base.dy - h * 0.45,
        base.dx + r * 1.0,
        base.dy - r * 0.1,
      )
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [light, color, dark],
          stops: const [0, 0.45, 1],
        ).createShader(body.getBounds()),
    );
    final head = Offset(base.dx, base.dy - h * 0.78);
    canvas.drawCircle(
      head,
      r * 0.95,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [light, color, dark],
        ).createShader(Rect.fromCircle(center: head, radius: r * 0.95)),
    );
    canvas.drawCircle(
      head + Offset(-r * 0.3, -r * 0.35),
      r * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  void _die(Canvas canvas, Offset c, double s) {
    final d = s * 0.42;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    // Shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(s * 0.08, s * 0.62),
          width: s * 1.2,
          height: s * 0.5,
        ),
        Radius.circular(s * 0.2),
      ),
      Paint()
        ..color = const Color(0x88000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.12),
    );
    // Side face (right, darker), top face (lighter), front face.
    final side = Path()
      ..moveTo(d, -d)
      ..lineTo(d + s * 0.36, -d - s * 0.3)
      ..lineTo(d + s * 0.36, d - s * 0.3)
      ..lineTo(d, d)
      ..close();
    canvas.drawPath(
      side,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFC9CCD8), Color(0xFF8E93A6)],
        ).createShader(side.getBounds()),
    );
    final top = Path()
      ..moveTo(-d, -d)
      ..lineTo(-d + s * 0.36, -d - s * 0.3)
      ..lineTo(d + s * 0.36, -d - s * 0.3)
      ..lineTo(d, -d)
      ..close();
    canvas.drawPath(
      top,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Color(0xFFE4E6EE)],
        ).createShader(top.getBounds()),
    );
    final front = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: d * 2, height: d * 2),
      Radius.circular(s * 0.08),
    );
    canvas.drawRRect(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFDDE0EA)],
        ).createShader(front.outerRect),
    );
    canvas.drawRRect(
      front,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012
        ..color = const Color(0xFF9A9FB3),
    );
    // Pips: five on the front, three on top, two on the side.
    final pip = Paint()..color = const Color(0xFF1B1B22);
    final pr = s * 0.065;
    for (final p in [
      const Offset(-0.5, -0.5),
      const Offset(0.5, -0.5),
      Offset.zero,
      const Offset(-0.5, 0.5),
      const Offset(0.5, 0.5),
    ]) {
      canvas.drawCircle(Offset(p.dx * d, p.dy * d), pr, pip);
      canvas.drawCircle(
        Offset(p.dx * d - pr * 0.3, p.dy * d - pr * 0.3),
        pr * 0.3,
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );
    }
    for (final k in [-0.5, 0.0, 0.5]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(k * d + s * 0.18, -d - s * 0.15 + k * d * 0.0),
          width: pr * 2.2,
          height: pr * 1.3,
        ),
        pip,
      );
    }
    for (final k in [-0.45, 0.45]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(d + s * 0.18, k * d - s * 0.15),
          width: pr * 1.3,
          height: pr * 2.0,
        ),
        pip,
      );
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Tilted board in the back.
    canvas.save();
    canvas.translate(w * 0.5, h * 0.52);
    canvas.rotate(-0.18);
    canvas.scale(1, 0.72);
    final b = min(w, h) * 0.98;
    final board = Rect.fromCenter(center: Offset.zero, width: b, height: b);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        board.shift(Offset(0, b * 0.06)),
        Radius.circular(b * 0.05),
      ),
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, b * 0.05),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(board, Radius.circular(b * 0.05)),
      Paint()..color = const Color(0xFFF2F4FA),
    );
    final s = b / 15;
    final yards = [
      [0.0, 9.0],
      [0.0, 0.0],
      [9.0, 0.0],
      [9.0, 9.0],
    ];
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromLTWH(
        board.left + yards[i][0] * s,
        board.top + yards[i][1] * s,
        6 * s,
        6 * s,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(s)),
        Paint()..color = _cols[i],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(s), Radius.circular(s * 0.6)),
        Paint()..color = Colors.white,
      );
    }
    final mid = board.center;
    final c = [
      Offset(mid.dx - 1.5 * s, mid.dy - 1.5 * s),
      Offset(mid.dx + 1.5 * s, mid.dy - 1.5 * s),
      Offset(mid.dx + 1.5 * s, mid.dy + 1.5 * s),
      Offset(mid.dx - 1.5 * s, mid.dy + 1.5 * s),
    ];
    void tri(Offset a, Offset b2, Color col) => canvas.drawPath(
      Path()
        ..moveTo(mid.dx, mid.dy)
        ..lineTo(a.dx, a.dy)
        ..lineTo(b2.dx, b2.dy)
        ..close(),
      Paint()..color = col,
    );
    tri(c[0], c[1], _cols[2]);
    tri(c[1], c[2], _cols[3]);
    tri(c[2], c[3], _cols[0]);
    tri(c[3], c[0], _cols[1]);
    for (final k in [1.5, 7.5, 13.5]) {
      canvas.drawLine(
        Offset(board.left + 6 * s, board.top + k * s),
        Offset(board.right - 6 * s, board.top + k * s),
        Paint()
          ..color = const Color(0xFFBFC6D8)
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
    // Pawns and the die in front.
    _pawn(canvas, Offset(w * 0.2, h * 0.86), h * 0.5, _cols[0]);
    _pawn(canvas, Offset(w * 0.8, h * 0.84), h * 0.46, _cols[3]);
    _die(canvas, Offset(w * 0.5, h * 0.5), min(w, h) * 0.52);
  }

  @override
  bool shouldRepaint(_LudoHeroPainter old) => false;
}

/// Pointing hand that taps the tile every couple of seconds, with a ripple
/// at the fingertip — the reference's "tap here" hint.
class TapHandHint extends StatefulWidget {
  const TapHandHint({super.key, this.size = 190});

  final double size;

  @override
  State<TapHandHint> createState() => _TapHandHintState();
}

class _TapHandHintState extends State<TapHandHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size * 1.15,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // Press from 0.15→0.4, hold, lift 0.6→0.85.
        final press = t < 0.15
            ? 0.0
            : t < 0.4
            ? Curves.easeIn.transform((t - 0.15) / 0.25)
            : t < 0.6
            ? 1.0
            : t < 0.85
            ? 1 - Curves.easeOut.transform((t - 0.6) / 0.25)
            : 0.0;
        final ripple = t < 0.38 || t > 0.95
            ? 0.0
            : ((t - 0.38) / 0.57).clamp(0.0, 1.0);
        return CustomPaint(painter: _HandPainter(press, ripple));
      },
    ),
  );
}

class _HandPainter extends CustomPainter {
  const _HandPainter(this.press, this.ripple);

  final double press;
  final double ripple;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // Fingertip at the upper-left; the hand moves toward it when pressing.
    final tip = Offset(w * 0.28, size.height * 0.2);
    if (ripple > 0) {
      final r = w * (0.12 + 0.3 * ripple);
      canvas.drawCircle(
        tip,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.035 * (1 - ripple * 0.6)
          ..color = Colors.white.withValues(alpha: (1 - ripple) * 0.9),
      );
    }
    canvas.save();
    // The fingertip sits on [tip]; the whole hand moves toward it when pressing.
    canvas.translate(tip.dx - press * w * 0.04, tip.dy + press * w * 0.1);
    canvas.rotate(-0.5);
    final glove = Paint()..color = Colors.white;
    final shade = Paint()..color = const Color(0xFFD4D8EA);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..color = const Color(0xFF8F95B5);
    final u = w * 0.105;
    RRect capsule(Rect r) =>
        RRect.fromRectAndRadius(r, Radius.circular(r.width / 2));
    // Index finger (tip at the origin), fist below it, thumb on the left, cuff.
    final finger = capsule(Rect.fromLTWH(-u * 0.7, 0, u * 1.4, u * 5.6));
    final fist = RRect.fromRectAndRadius(
      Rect.fromLTWH(-u * 1.9, u * 3.9, u * 4.6, u * 4.0),
      Radius.circular(u * 1.4),
    );
    final thumb = capsule(Rect.fromLTWH(-u * 2.9, u * 3.4, u * 1.3, u * 3.2));
    final cuff = RRect.fromRectAndRadius(
      Rect.fromLTWH(-u * 1.7, u * 7.4, u * 4.2, u * 1.3),
      Radius.circular(u * 0.4),
    );
    canvas.drawRRect(
      fist.shift(Offset(u * 0.3, u * 0.5)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.6),
    );
    canvas.drawRRect(thumb, shade);
    canvas.drawRRect(thumb, outline);
    canvas.drawRRect(fist, glove);
    canvas.drawRRect(fist, outline);
    for (var i = 0; i < 3; i++) {
      final knuckle = capsule(
        Rect.fromLTWH(-u * 0.6 + i * u * 1.0, u * 3.6, u * 0.95, u * 2.0),
      );
      canvas.drawRRect(knuckle, i == 0 ? glove : shade);
      canvas.drawRRect(knuckle, outline);
    }
    canvas.drawRRect(finger, glove);
    canvas.drawRRect(finger, outline);
    canvas.drawRRect(cuff, shade);
    canvas.drawRRect(cuff, outline);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HandPainter old) =>
      old.press != press || old.ripple != ripple;
}

/// Gentle vertical float for tile art (the reference's balls bob).
class FloatBob extends StatefulWidget {
  const FloatBob({
    super.key,
    required this.child,
    this.amplitude = 9,
    this.period = const Duration(milliseconds: 2600),
  });

  final Widget child;
  final double amplitude;
  final Duration period;

  @override
  State<FloatBob> createState() => _FloatBobState();
}

class _FloatBobState extends State<FloatBob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) => Transform.translate(
      offset: Offset(0, sin(_c.value * 2 * pi) * widget.amplitude),
      child: child,
    ),
    child: widget.child,
  );
}

/// Small gradient tile with an icon or art and a label (Room / Minigames /
/// Friends in the reference).
class SmallTile extends StatelessWidget {
  const SmallTile({
    super.key,
    required this.width,
    required this.height,
    required this.colors,
    required this.label,
    required this.child,
    required this.onTap,
    this.count = 0,
  });

  final double width;
  final double height;
  final List<Color> colors;
  final String label;
  final Widget child;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.96,
    child: SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(colors[0], Colors.white, 0.08)!,
                    colors[0],
                    colors[1],
                  ],
                  stops: const [0, 0.35, 1],
                ),
                border: Border.all(
                  color: const Color(0xFFBDEFFF).withValues(alpha: 0.75),
                  width: 2.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA000000),
                    blurRadius: 14,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Positioned(
                      left: 14,
                      right: 14,
                      top: 12,
                      bottom: 78,
                      child: child,
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 16,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(titleCase(label), style: pcText(56)),
                      ),
                    ),
                    const DuelGloss(radius: 10, strength: 0.16),
                  ],
                ),
              ),
            ),
          ),
          if (count > 0)
            Positioned(left: -8, top: -10, child: _CountBadge(count)),
        ],
      ),
    ),
  );
}

// ----------------------------------------------------------------- panels

/// The reference's season-pass panel: header tab with icon, title and a
/// timer; three reward boxes with captions; a gold progress bar.
class LadderPanel extends StatelessWidget {
  const LadderPanel({
    super.key,
    required this.width,
    required this.title,
    required this.timer,
    required this.boxes,
    required this.progress,
    required this.onTap,
    this.footnote,
  });

  final double width;
  final String title;
  final Widget timer;
  final List<LadderBox> boxes;

  /// 0..1 along the bar.
  final double progress;
  final VoidCallback onTap;
  final String? footnote;

  static const height = 230.0;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.98,
    child: SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 36,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [DesignColors.pcSeason, DesignColors.pcSeasonDeep],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A1C5E), width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA000000),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
          // Header tab.
          Positioned(
            left: 0,
            top: 0,
            child: ClipPath(
              clipper: _TabClipper(),
              child: Container(
                height: 60,
                padding: const EdgeInsets.fromLTRB(16, 0, 44, 0),
                color: const Color(0xFF5A48B8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.hexagon_rounded,
                      color: Color(0xFF5DD6FF),
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Text(titleCase(title), style: pcText(30)),
                    const SizedBox(width: 16),
                    timer,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 6,
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFF2A1C5E),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.04, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [DesignColors.pcGold, DesignColors.pcGoldDeep],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 40,
            right: 40,
            top: 62,
            child: Row(
              children: [
                for (var i = 0; i < boxes.length; i++) ...[
                  if (i > 0) const Spacer(),
                  boxes[i],
                ],
              ],
            ),
          ),
          if (footnote != null)
            Positioned(
              right: 24,
              top: 40,
              child: Text(
                footnote!,
                style: pcText(
                  20,
                  color: DesignColors.pcTextDim,
                  weight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _TabClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width - 30, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_TabClipper old) => false;
}

/// One reward box of the [LadderPanel]: art, count inside, caption below.
class LadderBox extends StatelessWidget {
  const LadderBox({
    super.key,
    required this.art,
    required this.count,
    required this.caption,
    this.highlight = false,
    this.done = false,
  });

  final Widget art;
  final String count;
  final String caption;
  final bool highlight;
  final bool done;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 120,
        height: 108,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: highlight
                ? const [Color(0xFF8E4CF0), Color(0xFF4B1FA8)]
                : const [Color(0xFF3D7BE8), Color(0xFF1E3FA8)],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: highlight
                ? const Color(0xFFD59CFF)
                : const Color(0xFF7FB6FF),
            width: 2.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 8,
              child: Opacity(opacity: done ? 0.45 : 1, child: art),
            ),
            Positioned(bottom: 4, child: Text(count, style: pcText(26))),
            if (done)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF4DF08A),
                size: 44,
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Text(caption, style: pcText(26)),
    ],
  );
}

/// Wide purple panel (used for "rejoin your match").
class HomeWideBanner extends StatelessWidget {
  const HomeWideBanner({
    super.key,
    required this.width,
    required this.height,
    required this.title,
    required this.icon,
    required this.child,
    required this.onTap,
    this.trailing,
    this.rim = DesignColors.pcPanelRim,
    this.glow = false,
  });

  final double width;
  final double height;
  final String title;
  final Widget icon;
  final Widget child;
  final Widget? trailing;
  final VoidCallback onTap;
  final Color rim;
  final bool glow;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.98,
    child: Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [DesignColors.pcSeason, DesignColors.pcSeasonDeep],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rim, width: 2),
        boxShadow: [
          const BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
          if (glow)
            BoxShadow(
              color: rim.withValues(alpha: 0.55),
              blurRadius: 28,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titleCase(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pcText(30),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------- bottom nav

class HomeNavItem {
  const HomeNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badge = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool badge;
}

/// Five-tab bar; the active tab is a raised blue cell.
class HomeBottomNav extends StatelessWidget {
  const HomeBottomNav({super.key, required this.items});

  final List<HomeNavItem> items;

  static const height = 220.0;
  static const raise = 20.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: raise,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF3A2B78), DesignColors.pcNav],
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 2,
                ),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xCC000000),
                  blurRadius: 24,
                  offset: Offset(0, -6),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _NavCell(
                  items[i],
                  divider: i < items.length - 1 && !items[i + 1].active,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _NavCell extends StatelessWidget {
  const _NavCell(this.item, {required this.divider});

  final HomeNavItem item;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final color = item.active ? Colors.white : DesignColors.pcNavText;
    return PressScale(
      onTap: item.onTap,
      scale: 0.95,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: item.active ? 0 : HomeBottomNav.raise,
            child: Container(
              decoration: item.active
                  ? BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF6A95DC),
                          Color(0xFF4C63D8),
                          DesignColors.pcNavActiveDeep,
                        ],
                        stops: [0, 0.35, 1],
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 2,
                        ),
                        left: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 2,
                        ),
                        right: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0x663B6CFF), blurRadius: 18),
                      ],
                    )
                  : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    size: 96,
                    color: color,
                    shadows: const [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        titleCase(item.label),
                        maxLines: 1,
                        style: pcText(36, color: color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (divider && !item.active)
            Positioned(
              right: 0,
              top: HomeBottomNav.raise + 50,
              bottom: 50,
              child: Container(
                width: 2,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
          if (item.badge)
            Positioned(
              right: 30,
              top: HomeBottomNav.raise + 18,
              child: PulseBadge(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF03A4E),
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
