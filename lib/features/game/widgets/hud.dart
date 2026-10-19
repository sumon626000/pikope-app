import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/strings.dart';

import '../../../core/app_theme.dart';
import '../../../core/audio_service.dart';
import '../../../core/turn_life_dots.dart';
import '../../../core/widgets.dart';
import '../../../game/models/match_state.dart';
import '../../../game/models/player_state.dart';
import '../../../game/physics/vec2.dart';
import '../../../game/rules/rules_engine.dart';
import '../game_controller.dart';
import 'ball_painter.dart';
import 'card_view.dart';

/// Positions on the 1950x900 match canvas, per seat slot
/// (0 bottom = the viewer, 1 left, 2 top, 3 right). The table takes the
/// middle of the screen; hands sit in the margins around it.
class SeatLayout {
  static const tableRect = Rect.fromLTWH(420, 96, 1180, 690);

  static const avatarSizes = [92.0, 96.0, 84.0, 96.0];
  static const nameSides = [NameSide.hidden, NameSide.below, NameSide.right, NameSide.below];
  static const avatar = [Offset(436, 798), Offset(262, 104), Offset(1140, 6), Offset(1632, 470)];

  /// The viewer's cards are large and tappable; opponents' are compact.
  static const cardWidths = [72.0, 54.0, 50.0, 54.0];
  static const handStart = [Offset(548, 792), Offset(270, 250), Offset(770, 10), Offset(1640, 110)];
  static const handAxis = [Offset(1, 0), Offset(0, 1), Offset(1, 0), Offset(0, 1)];
  static const handExtent = [520.0, 300.0, 310.0, 300.0];
  static const handMaxStep = [76.0, 42.0, 46.0, 42.0];
  static const raiseDir = [Offset(0, -1), Offset(1, 0), Offset(0, 1), Offset(-1, 0)];
  static const quarterTurns = [0, 1, 0, 3];
  static const breakCard = [Offset(560, 650), Offset(264, 250), Offset(1040, 2), Offset(1640, 300)];
  static const doneChips = [Offset(0, 0), Offset(262, 628), Offset(1240, 56), Offset(1632, 628)];
}

enum NameSide { below, right, hidden }

const _ordinals = ['1ST', '2ND', '3RD', '4TH'];

/// Centre of the table on the design canvas: where dealt cards come from.
const _dealOrigin = Offset(974, 390);

// ----------------------------------------------------------------- seat

class SeatView extends ConsumerWidget {
  const SeatView({super.key, required this.controller, required this.playerIndex});

  final GameController controller;
  final int playerIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final c = controller;
    final p = c.players[playerIndex];
    final phase = c.state.phase;
    final isCurrent = c.orderKnown &&
        c.state.currentIndex == playerIndex &&
        !c.dealing &&
        !c.presenting &&
        (phase == GamePhase.playerTurn ||
            phase == GamePhase.shooting ||
            phase == GamePhase.declarePhase);
    final isWinner = c.state.winner == playerIndex;
    return AvatarSeat(
      name: p.name,
      avatar: p.avatar,
      isCurrent: isCurrent,
      isWinner: isWinner,
      tag: p.readyToDeclare && !isWinner ? t.readyShort : null,
      winnerLabel: t.winner,
      clock: c.clock,
      shotSeconds: c.config.shotSeconds,
      size: SeatLayout.avatarSizes[c.slotOf(playerIndex)],
      nameSide: SeatLayout.nameSides[c.slotOf(playerIndex)],
    );
  }
}

/// Avatar tile with name, shot-clock ring while it is this player's turn,
/// and an optional tag under it. Shared by every game mode.
class AvatarSeat extends StatelessWidget {
  const AvatarSeat({
    super.key,
    required this.name,
    required this.avatar,
    required this.isCurrent,
    required this.isWinner,
    required this.clock,
    required this.shotSeconds,
    this.tag,
    this.turnMisses,
    this.winnerLabel = 'WINNER',
    this.size = 96,
    this.nameSide = NameSide.below,
  });

  final double size;
  final NameSide nameSide;
  final String name;
  final String avatar;
  final bool isCurrent;
  final bool isWinner;
  final ValueNotifier<double> clock;
  final int shotSeconds;
  final String? tag;
  final int? turnMisses;
  final String winnerLabel;

  @override
  Widget build(BuildContext context) {
    final tile = SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                FramedTile(
                  size: size,
                  frameColor: isWinner
                      ? AppColors.gold
                      : isCurrent
                          ? const Color(0xFF1F4D2A)
                          : AppColors.frame,
                  glow: isCurrent || isWinner,
                  child: AvatarImage(avatar, size: size),
                ),
                // The clock changes every frame: keep its repaints in their
                // own layers so the rest of the HUD is not redrawn with it.
                if (isCurrent)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<double>(
                        valueListenable: clock,
                        builder: (_, left, _) => CustomPaint(
                          painter: _TimerRingPainter(
                            (left / shotSeconds).clamp(0.0, 1.0),
                            left <= 10 ? AppColors.danger : AppColors.active,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isCurrent)
                  Positioned(
                    right: -10,
                    top: -10,
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<double>(
                        valueListenable: clock,
                        builder: (_, left, _) => _Badge(
                          '${left.ceil()}',
                          left <= 10 ? AppColors.danger : AppColors.active,
                        ),
                      ),
                    ),
                  ),
                if (isWinner)
                  Positioned(left: -14, bottom: -6, right: -14, child: _Badge(winnerLabel, AppColors.gold))
                else if (tag != null)
                  Positioned(left: -14, bottom: -6, right: -14, child: _Badge(tag!, AppColors.gold)),
                if (turnMisses != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: -14,
                    child: Center(child: TurnLifeDots(missed: turnMisses!, size: size * 0.11)),
                  ),
              ],
            ),
          );
    final label = Text(name.toUpperCase(), maxLines: 1, style: AppText.label(size * 0.19));
    switch (nameSide) {
      case NameSide.hidden:
        return Padding(
          padding: EdgeInsets.fromLTRB(30, 0, 30, turnMisses != null ? 10 : 0),
          child: tile,
        );
      case NameSide.right:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [const SizedBox(width: 30), tile, const SizedBox(width: 14), label],
        );
      case NameSide.below:
        return SizedBox(
          width: size + 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile,
              const SizedBox(height: 8),
              FittedBox(fit: BoxFit.scaleDown, child: label),
            ],
          ),
        );
    }
  }
}

/// One-line instruction shown above the table.
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.center,
      decoration: panelDecoration(),
      child: Text(
        text,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: AppText.label(16),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
          ),
          child: Text(text, style: AppText.label(15, color: Colors.black, weight: FontWeight.w900)),
        ),
      );
}

class _TimerRingPainter extends CustomPainter {
  _TimerRingPainter(this.fraction, this.color);

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.065;
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(stroke / 2),
      Radius.circular(size.width * 0.2 - stroke / 2),
    );
    final metric = (Path()..addRRect(rrect)).computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * fraction),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_TimerRingPainter old) => old.fraction != fraction || old.color != color;
}

// ---------------------------------------------------------------- hands

/// Builds the positioned cards of one player's hand for the design canvas.
List<Widget> buildHand(GameController c, int playerIndex) {
  final slot = c.slotOf(playerIndex);
  final p = c.players[playerIndex];
  final orderPos = c.state.turnOrder.indexOf(playerIndex);
  final visible = c.dealing
      ? ((c.dealtCards - orderPos + 3) ~/ 4).clamp(0, p.hand.length)
      : p.hand.length;
  final n = p.hand.length;
  final step = n <= 1
      ? 0.0
      : min(SeatLayout.handMaxStep[slot], SeatLayout.handExtent[slot] / (n - 1));
  final isViewer = slot == 0 && !p.isBot;
  final myTurn = c.canAim && c.state.currentIndex == playerIndex && !c.state.isBreakShot;
  final turns = SeatLayout.quarterTurns[slot];
  final cardW = SeatLayout.cardWidths[slot];
  final cardH = cardW * CardFace.aspect;

  return [
    for (var i = 0; i < visible; i++)
      () {
        final hc = p.hand[i];
        final selected = identical(c.state.selectedCard, hc);
        final shown = c.raisedCards.contains(hc);
        final raise = shown ? cardH / 2 : (selected ? cardH * 0.28 : 0.0);
        final pos = SeatLayout.handStart[slot] +
            SeatLayout.handAxis[slot] * (step * i) +
            SeatLayout.raiseDir[slot] * raise;
        final faceUp = (isViewer && !c.handoffPending) || hc.revealed || selected || shown;
        final selectable = isViewer && myTurn && !hc.completed && p.pendingBalls.contains(hc.card.ball);
        final face = CardFace(
          card: hc.card,
          width: cardW,
          completed: hc.completed,
          penalty: hc.isPenalty,
          selected: selected,
          disabled: isViewer && !hc.completed && !p.pendingBalls.contains(hc.card.ball),
        );
        return AnimatedPositioned(
          key: ValueKey('hand-$playerIndex-${hc.key}'),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            onTap: selectable ? () => c.selectCard(hc) : null,
            // Cards fly in from the table. Translation only: animating the
            // scale of text forces it to be re-rasterised every frame.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (_, t, child) =>
                  Transform.translate(offset: (_dealOrigin - pos) * (t * 0.6), child: child),
              child: RotatedBox(
                quarterTurns: turns,
                child: isViewer
                    ? (faceUp ? face : CardBack(width: cardW, completed: hc.completed))
                    : FlipCard(
                        faceUp: faceUp,
                        front: face,
                        back: CardBack(width: cardW, completed: hc.completed),
                      ),
              ),
            ),
          ),
        );
      }(),
  ];
}

/// Balls an opponent has already completed (public knowledge).
class DoneChips extends StatelessWidget {
  const DoneChips({super.key, required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final done = player.completedBalls.toList()..sort();
    if (done.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: AppColors.active, size: 20),
        const SizedBox(width: 4),
        for (final b in done.take(7))
          Padding(padding: const EdgeInsets.only(right: 3), child: BallIcon(b, size: 24)),
      ],
    );
  }
}

// ----------------------------------------------------------- objectives

/// The viewer's unique objectives (not cards) plus the free-ball selectors.
class ObjectivePanel extends ConsumerWidget {
  const ObjectivePanel({super.key, required this.controller, required this.player});

  final GameController controller;
  final PlayerState player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final c = controller;
    final required = player.requiredBalls.toList()..sort();
    final penalty = player.penaltyBalls;
    final canPick = c.canAim && identical(c.current, player) && !c.state.isBreakShot;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(t.yourBallsCount(player.completedBalls.length, required.length),
                  style: AppText.label(14, color: AppColors.textDim)),
              const Spacer(),
              Text(t.freeBall, style: AppText.label(14, color: AppColors.gold)),
              const SizedBox(width: 34),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      for (final b in required)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _ObjectiveChip(
                            ball: b,
                            done: player.completedBalls.contains(b),
                            penalty: penalty.contains(b),
                            target: c.state.targetBall == b && identical(c.current, player),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              for (final b in RulesEngine.freeBalls)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: canPick ? () => c.selectFreeBall(b) : null,
                    child: _ObjectiveChip(
                      ball: b,
                      done: false,
                      penalty: false,
                      dim: !canPick,
                      target: c.state.selectedFreeBall == b && identical(c.current, player),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ObjectiveChip extends StatelessWidget {
  const _ObjectiveChip({
    required this.ball,
    required this.done,
    required this.penalty,
    required this.target,
    this.dim = false,
  });

  final int ball;
  final bool done;
  final bool penalty;
  final bool target;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final ring = target
        ? AppColors.gold
        : penalty
            ? AppColors.danger
            : Colors.transparent;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 3)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          BallIcon(ball, size: 40, opacity: done ? 0.35 : (dim ? 0.5 : 1)),
          if (done) const Icon(Icons.check_rounded, color: AppColors.active, size: 36),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- controls

class PowerBar extends StatelessWidget {
  const PowerBar({super.key, required this.controller});

  final ShotTable controller;
  static const size = Size(58, 456);

  /// Invisible margin around the bar that still catches the finger: the bar
  /// itself is only a few millimetres wide on a phone.
  static const touchPad = EdgeInsets.fromLTRB(47, 40, 60, 30);

  @override
  Widget build(BuildContext context) {
    final c = controller;
    void set(Offset local) =>
        c.setPower((local.dy - touchPad.top - 30) / (size.height - 60));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (d) => set(d.localPosition),
      onVerticalDragUpdate: (d) => set(d.localPosition),
      onVerticalDragEnd: (_) => c.releaseShot(),
      onVerticalDragCancel: c.releaseShot,
      child: Padding(
        padding: touchPad,
        child: RepaintBoundary(child: CustomPaint(size: size, painter: _PowerBarPainter(c))),
      ),
    );
  }
}

/// "Pull to shoot" prompt shown next to the bar whenever a shot is possible.
class ShootHint extends ConsumerWidget {
  const ShootHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    if (!t.isBn) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.pull, style: AppText.label(17, color: AppColors.gold, weight: FontWeight.w900)),
          Text(t.down, style: AppText.label(17, color: AppColors.gold, weight: FontWeight.w900)),
          const Icon(Icons.keyboard_double_arrow_down_rounded, color: AppColors.gold, size: 44),
          Text(t.toShoot, style: AppText.label(15, color: AppColors.text)),
          Text(t.shootLabel, style: AppText.label(15, color: AppColors.text)),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t.pullDownToShoot, textAlign: TextAlign.center, style: AppText.label(15, color: AppColors.gold, weight: FontWeight.w900)),
        const Icon(Icons.keyboard_double_arrow_down_rounded, color: AppColors.gold, size: 44),
      ],
    );
  }
}

class _PowerBarPainter extends CustomPainter {
  _PowerBarPainter(this.c) : super(repaint: c.frame);

  final ShotTable c;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    if (c.canShoot && c.power == 0) {
      // Breathing gold halo: "this is what you pull".
      final pulse = 0.5 + 0.5 * sin(c.frame.value / 11);
      canvas.drawRRect(
        outer.inflate(3 + pulse * 4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = AppColors.gold.withValues(alpha: 0.35 + 0.5 * pulse),
      );
    }
    canvas.drawRRect(outer, Paint()..color = AppColors.frame);
    final inner = outer.deflate(5);
    canvas.drawRRect(inner, Paint()..color = const Color(0xFF101014));
    canvas.save();
    canvas.clipRRect(inner);
    final power = c.power;
    if (power > 0) {
      final h = (size.height - 10) * power;
      canvas.drawRect(
        Rect.fromLTWH(5, 5, size.width - 10, h),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x332EE84F), Color(0x99FFC928), Color(0xCCFF4D4D)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }
    // The cue slides down as power builds.
    final top = 14 + (size.height - 60) * power;
    final cx = size.width / 2;
    final cue = Path()
      ..moveTo(cx - 3, top + 8)
      ..lineTo(cx + 3, top + 8)
      ..lineTo(cx + 8, top + size.height - 30)
      ..lineTo(cx - 8, top + size.height - 30)
      ..close();
    canvas.drawPath(
      cue,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFB9772E), Color(0xFFF5C777), Color(0xFF8A4F1A)],
        ).createShader(Rect.fromLTWH(cx - 8, 0, 16, size.height)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 3.5, top, 7, 9), const Radius.circular(3)),
      Paint()..color = const Color(0xFFE8E8EE),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PowerBarPainter old) => false;
}

/// Cue-ball spin selector: the red dot is where the tip strikes.
class SpinControl extends StatelessWidget {
  const SpinControl({super.key, required this.controller});

  final ShotTable controller;
  static const diameter = 96.0;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    const r = diameter / 2;
    void set(Offset local) => c.setSpin(Vec2((local.dx - r) / (r * 0.75), -(local.dy - r) / (r * 0.75)));
    return GestureDetector(
      onPanStart: (d) => set(d.localPosition),
      onPanUpdate: (d) => set(d.localPosition),
      onDoubleTap: () => c.setSpin(Vec2.zero),
      child: Container(
        width: diameter,
        height: diameter,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-0.3, -0.35),
            colors: [Colors.white, Color(0xFFE4E4DC), Color(0xFFB9B9B0)],
            stops: [0, 0.7, 1],
          ),
          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Align(
          alignment: Alignment(c.spin.x * 0.75, -c.spin.y * 0.75),
          child: Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(color: Color(0xFFE0261B), shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class MenuTile extends ConsumerWidget {
  const MenuTile({super.key, required this.onTap, this.size = 84});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: panelDecoration(radius: size * 0.2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grid_view_rounded, color: const Color(0xFFB5B5C0), size: size * 0.46),
            Text(t.menu, style: AppText.label(size * 0.15, color: const Color(0xFFB5B5C0))),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- banner

class BannerView extends ConsumerWidget {
  const BannerView({super.key, required this.banner});

  final GameBanner banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final color = switch (banner.tone) {
      BannerTone.info => AppColors.text,
      BannerTone.good => AppColors.active,
      BannerTone.bad => AppColors.danger,
      BannerTone.gold => AppColors.gold,
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 26 * (1 - t)), child: child),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xE6101014),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color, width: 3),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 30)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < banner.lines.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    s.bannerLine(banner.lines[i]),
                    textAlign: TextAlign.center,
                    style: AppText.label(i == 0 ? 38 : 22,
                        color: i == 0 ? color : AppColors.text, weight: FontWeight.w900),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- break draw

/// Face-down spread on the cloth: 3 rows of 10, as in the mockup.
List<Widget> buildBreakSpread(GameController c) {
  const origin = Offset(540, 205);
  const cardW = 80.0;
  final picker = c.breakPicker;
  return [
    for (var i = 0; i < c.breakSpread.length; i++)
      if (c.breakSpread[i] != null)
        Positioned(
          left: origin.dx + (i % 10) * 96.0,
          top: origin.dy + (i ~/ 10) * 150.0,
          child: GestureDetector(
            onTap: picker != null ? () => c.pickBreakCard(i) : null,
            child: const CardBack(width: cardW),
          ),
        ),
  ];
}

List<Widget> buildBreakCards(GameController c) {
  return [
    for (var i = 0; i < c.players.length; i++)
      if (c.players[i].breakCard != null)
        () {
          final card = c.players[i].breakCard!;
          final pos = SeatLayout.breakCard[c.slotOf(i)];
          final rank = c.orderKnown ? c.state.turnOrder.indexOf(i) : -1;
          return AnimatedPositioned(
            key: ValueKey('break-$i'),
            duration: const Duration(milliseconds: 350),
            left: pos.dx,
            top: pos.dy,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlipCard(
                  faceUp: c.breakRevealed,
                  front: CardFace(card: card, selected: rank == 0),
                  back: CardBack(highlighted: !c.players[i].isBot),
                ),
                if (rank >= 0) ...[
                  const SizedBox(height: 4),
                  _Badge(_ordinals[rank], rank == 0 ? AppColors.gold : AppColors.text),
                ],
              ],
            ),
          );
        }(),
  ];
}

