import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../data/match_bet.dart';
import 'duel_chrome.dart';
import 'history_screen.dart';
import '../../l10n/strings.dart';
import 'lobby_data.dart';

/// Billiard 1v1: shows which game the draw picked - the 8, 9 and 10 balls
/// flicker in turn and the chosen one stays lit.
class GameRevealOverlay extends ConsumerStatefulWidget {
  const GameRevealOverlay({super.key, required this.ball, required this.onDone});

  /// 8, 9 or 10: the game about to be played.
  final int ball;
  final VoidCallback onDone;

  @override
  ConsumerState<GameRevealOverlay> createState() => _GameRevealOverlayState();
}

class _GameRevealOverlayState extends ConsumerState<GameRevealOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    })
    ..forward();
  int _lit = -1;

  static const _balls = [8, 9, 10];

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      // Fast at first, slowing to a stop on the drawn ball at 60%.
      final t = (_c.value / 0.6).clamp(0.0, 1.0);
      final steps = (Curves.easeOutCubic.transform(t) * (9 + _balls.indexOf(widget.ball))).floor();
      final lit = t >= 1 ? _balls.indexOf(widget.ball) : steps % 3;
      if (lit != _lit) {
        _lit = lit;
        AudioService.instance?.play(t >= 1 ? Sfx.success : Sfx.tick, volume: t >= 1 ? 1 : 0.6);
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final settled = _c.value >= 0.6;
    return Positioned.fill(
      child: AbsorbPointer(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _c, curve: const Interval(0.9, 1, curve: Curves.easeIn)).drive(Tween(begin: 1.0, end: 0.0)),
          child: Container(
            color: const Color(0x8C000000),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(settled ? t.nBallLabel(widget.ball) : t.drawingTheGame,
                    style: AppText.label(46, color: settled ? DuelColors.gold : Colors.white, weight: FontWeight.w900)
                        .copyWith(shadows: const [Shadow(color: Colors.black, blurRadius: 12)])),
                const SizedBox(height: 30),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      AnimatedScale(
                        scale: i == _lit ? (settled ? 1.3 : 1.12) : 0.92,
                        duration: const Duration(milliseconds: 110),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              if (i == _lit) BoxShadow(color: DuelColors.gold.withValues(alpha: settled ? 0.9 : 0.5), blurRadius: settled ? 60 : 30, spreadRadius: 4),
                            ],
                          ),
                          child: BallIcon(_balls[i], size: 170, opacity: i == _lit || !settled ? 1 : 0.45),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Billiard Poker: the jackpot wheel spins and stops on this match's prize.
class JackpotWheelOverlay extends ConsumerStatefulWidget {
  const JackpotWheelOverlay({super.key, required this.bet, required this.onDone});

  final MatchBet bet;
  final VoidCallback onDone;

  @override
  ConsumerState<JackpotWheelOverlay> createState() => _JackpotWheelOverlayState();
}

class _JackpotWheelOverlayState extends ConsumerState<JackpotWheelOverlay> with SingleTickerProviderStateMixin {
  static const _fallback = [3, 4, 8, 12, 100, 1000, 2500, 10000];
  late final List<int> _prizes;
  late final int _target;
  late final double _turns;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 6800))
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    })
    ..forward();
  int _lastSlice = -1;
  bool _landed = false;

  // Spin until 68% of the time, hold the result, fade out at the end.
  static const _spinEnd = 0.68;

  @override
  void initState() {
    super.initState();
    final xs = ref.read(lobbyProvider).valueOrNull?.jackpot ?? _fallback;
    // Small and large prizes alternate round the wheel, as on a real one.
    final sorted = [...xs]..sort();
    final order = <int>[];
    for (var lo = 0, hi = sorted.length - 1; lo <= hi; lo++, hi--) {
      order.add(sorted[lo]);
      if (hi != lo) order.add(sorted[hi]);
    }
    _prizes = [for (final x in order) x * widget.bet.stake];
    final at = _prizes.indexOf(widget.bet.prize);
    _target = at < 0 ? 0 : at;
    final slice = 2 * pi / _prizes.length;
    // The pointer is at the top: bring the middle of the winning slice there,
    // a little off-centre so it does not look staged.
    _turns = 6 * 2 * pi - (_target + 0.5) * slice + (Random().nextDouble() - 0.5) * slice * 0.5;
    _c.addListener(_tick);
  }

  double get _angle => _turns * Curves.easeOutQuart.transform((_c.value / _spinEnd).clamp(0.0, 1.0));

  void _tick() {
    final slice = 2 * pi / _prizes.length;
    final passing = (_angle / slice).floor();
    if (passing != _lastSlice && !_landed) {
      _lastSlice = passing;
      AudioService.instance?.play(Sfx.tick, volume: 0.7);
    }
    if (!_landed && _c.value >= _spinEnd) {
      _landed = true;
      AudioService.instance?.play(widget.bet.multiplier != null && widget.bet.multiplier! >= 8 ? Sfx.win : Sfx.success);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return Positioned.fill(
        child: AbsorbPointer(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _c, curve: const Interval(0.94, 1, curve: Curves.easeIn)).drive(Tween(begin: 1.0, end: 0.0)),
            child: Container(
              color: const Color(0xA6000000),
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => CustomPaint(
                      size: const Size.square(640),
                      painter: _WheelPainter(_prizes, _angle, _landed ? _target : -1, _c.value),
                    ),
                  ),
                  if (_landed)
                    Positioned(
                      bottom: 60,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
                        decoration: duelPanel(radius: 22, rim: DuelColors.gold, glow: true, fill: const Color(0xF2101426)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.prizePoolMult('${widget.bet.multiplier ?? '-'}'), style: AppText.label(22, color: DuelColors.silver, weight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const PikoCoinIcon(size: 56),
                                const SizedBox(width: 14),
                                Text(formatCoins(widget.bet.prize), style: AppText.label(64, color: DuelColors.gold, weight: FontWeight.w900)),
                              ],
                            ),
                          ],
                        ),
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

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.prizes, this.angle, this.won, this.t);

  final List<int> prizes;
  final double angle;

  /// Index of the slice to light up once the wheel has stopped, or -1.
  final int won;
  final double t;

  static const _colors = [Color(0xFFD92B3A), Color(0xFF2E9E4F), Color(0xFF7A3FD1), Color(0xFFE2A616), Color(0xFF1F73D6), Color(0xFFD9532B), Color(0xFF1FA6A0), Color(0xFFB7308F)];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.46;
    final n = prizes.length;
    final slice = 2 * pi / n;
    canvas.drawCircle(c, r + 26, Paint()..color = const Color(0x99000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    // Slice 0 starts at the pointer (top) and the wheel turns clockwise.
    canvas.rotate(-pi / 2 + angle);
    final bounds = Rect.fromCircle(center: Offset.zero, radius: r);
    for (var i = 0; i < n; i++) {
      final color = _colors[i % _colors.length];
      final lit = i == won;
      canvas.drawArc(
        bounds,
        i * slice,
        slice,
        true,
        Paint()
          ..shader = RadialGradient(colors: [
            Color.lerp(color, Colors.black, 0.45)!,
            lit ? Color.lerp(color, Colors.white, 0.35)! : color,
          ], stops: const [0.2, 1]).createShader(bounds),
      );
      canvas.drawLine(
          Offset.zero,
          Offset(cos(i * slice), sin(i * slice)) * r,
          Paint()
            ..color = const Color(0xFFFFE9A6)
            ..strokeWidth = 3);
      // Prize, written outwards along the slice.
      canvas.save();
      canvas.rotate((i + 0.5) * slice);
      final tp = TextPainter(
        text: TextSpan(
          text: formatCoins(prizes[i], compact: true),
          style: AppText.label(prizes[i] >= 1000000 ? 30 : 34, color: Colors.white, weight: FontWeight.w900).copyWith(
            shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(r * 0.93 - tp.width, -tp.height / 2));
      canvas.restore();
    }
    canvas.restore();
    // Rim with running lights.
    canvas.drawCircle(
        c,
        r + 10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22
          ..shader = const SweepGradient(colors: [Color(0xFFFFD75A), Color(0xFFB8750D), Color(0xFFFFE9A6), Color(0xFFB8750D), Color(0xFFFFD75A)])
              .createShader(Rect.fromCircle(center: c, radius: r + 10)));
    const bulbs = 24;
    for (var i = 0; i < bulbs; i++) {
      final a = i * 2 * pi / bulbs;
      final on = ((t * 40).floor() + i).isEven;
      canvas.drawCircle(c + Offset(cos(a), sin(a)) * (r + 10), 6,
          Paint()..color = on ? const Color(0xFFFFFFFF) : [const Color(0xFFFF5A6E), const Color(0xFF5AD1FF), const Color(0xFF7CFF8A)][i % 3]);
    }
    // Hub.
    canvas.drawCircle(c, r * 0.2, Paint()..shader = const RadialGradient(colors: [Color(0xFFFF7A4A), Color(0xFFB3141F)]).createShader(Rect.fromCircle(center: c, radius: r * 0.2)));
    canvas.drawCircle(
        c,
        r * 0.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(0xFFFFD75A));
    final hub = TextPainter(
      text: TextSpan(text: 'JACKPOT', style: AppText.label(r * 0.075, color: const Color(0xFFFFE9A6), weight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    hub.paint(canvas, c - Offset(hub.width / 2, hub.height / 2));
    // Pointer.
    final tip = c + Offset(0, -r + 26);
    final pointer = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 26, tip.dy - 58)
      ..lineTo(tip.dx, tip.dy - 44)
      ..lineTo(tip.dx + 26, tip.dy - 58)
      ..close();
    canvas.drawPath(pointer.shift(const Offset(0, 4)), Paint()..color = const Color(0x99000000));
    canvas.drawPath(pointer, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE9A6), Color(0xFFE08A0B)]).createShader(pointer.getBounds()));
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.angle != angle || old.won != won || old.t != t;
}

/// One player on the result screen.
class ResultPlayer {
  const ResultPlayer({required this.name, required this.avatar, required this.won, this.me = false});

  final String name;
  final String avatar;
  final bool won;
  final bool me;
}

/// End of an online match: who won, what they won, BACK and DATA.
class DuelResultOverlay extends ConsumerStatefulWidget {
  const DuelResultOverlay({super.key, required this.players, required this.bet, required this.reason, required this.onBack});

  final List<ResultPlayer> players;
  final MatchBet bet;

  /// How the match ended ("9-BALL POCKETED" ...), if worth saying.
  final String? reason;
  final VoidCallback onBack;

  @override
  ConsumerState<DuelResultOverlay> createState() => _DuelResultOverlayState();
}

class _FlyCoin {
  const _FlyCoin(this.delay, this.from, this.size, this.spin);

  final double delay;
  final Offset from;
  final double size;
  final double spin;
}

class _DuelResultOverlayState extends ConsumerState<DuelResultOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _coins = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  late final List<_FlyCoin> _fly = _scatter();
  int _soundStep = -1;

  static List<_FlyCoin> _scatter() {
    final rng = Random();
    return [
      for (var i = 0; i < 18; i++)
        _FlyCoin(
          i * 0.028,
          Offset(180 + rng.nextDouble() * 1240, 620 + rng.nextDouble() * 260),
          34 + rng.nextDouble() * 30,
          (rng.nextDouble() - 0.5) * 8,
        ),
    ];
  }

  bool get _iWon => widget.players.any((p) => p.me && p.won);

  @override
  void initState() {
    super.initState();
    _coins.addListener(_coinSound);
    _coins.forward();
  }

  /// One win sting, then a few coin hits as the pieces land on the winner.
  void _coinSound() {
    if (!_iWon) return;
    final step = (_coins.value * 6).floor();
    if (step == _soundStep || step > 5) return;
    _soundStep = step;
    AudioService.instance?.play(step == 0 ? Sfx.win : Sfx.success, volume: step == 0 ? 1 : 0.72);
  }

  @override
  void dispose() {
    _coins.dispose();
    super.dispose();
  }

  Offset _winnerSpot(int count, double tile) {
    final vs = count > 2 ? 96.0 : 120.0;
    var total = tile;
    if (count > 1) total += vs + tile;
    for (var i = 2; i < count; i++) {
      total += 34 + tile;
    }
    return Offset((1600 - total) / 2 + tile / 2, 340 + tile / 2);
  }

  static const _gray = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final players = widget.players;
    final bet = widget.bet;
    final reason = widget.reason;
    final winner = players.firstWhere((p) => p.won);
    final me = players.firstWhere((p) => p.me, orElse: () => players.first);
    final settings = ref.watch(settingsProvider);
    final four = players.length > 2;
    final tile = four ? 230.0 : 260.0;
    // Winner first, as in the mockup.
    final ordered = [winner, for (final p in players) if (!identical(p, winner)) p];
    final spot = _winnerSpot(ordered.length, tile);
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Color(0xF205070F), spreadRadius: 900)],
          gradient: RadialGradient(center: Alignment(0, -0.3), radius: 1.1, colors: [Color(0xFF16205A), Color(0xFF0A0E26), Color(0xFF05070F)]),
        ),
        child: Stack(
          children: [
            const Positioned(left: 40, top: 20, child: DuelLogo()),
            Positioned(
              right: 40,
              top: 22,
              child: Row(
                children: [
                  CurrencyPill(icon: const PikoCoinIcon(size: 76), amount: settings.coins),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 150,
              child: DuelTitle(
                t.playerWins(winner.name),
                size: 70,
                sub: bet.staked ? t.winningPrize(formatPicoCoins(bet.prize)) : (reason ?? t.practiceFriendlyNoCoin),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 340,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < ordered.length; i++) ...[
                    if (i == 1)
                      SizedBox(
                        width: four ? 96 : 120,
                        height: tile,
                        child: OverflowBox(
                          maxWidth: 220,
                          child: Text(t.vs,
                              style: AppText.label(four ? 60 : 96, color: DuelColors.gold, weight: FontWeight.w900).copyWith(shadows: const [
                                Shadow(color: Color(0xFF7A4A00), offset: Offset(0, 5)),
                                Shadow(color: Color(0xCC000000), blurRadius: 14, offset: Offset(0, 8)),
                              ])),
                        ),
                      )
                    else if (i > 1)
                      const SizedBox(width: 34),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: tile,
                              height: tile,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: ordered[i].won ? const Color(0xFFFFE21A) : const Color(0xFF4A4973),
                                borderRadius: BorderRadius.circular(tile * 0.14),
                                boxShadow: [
                                  if (ordered[i].won) const BoxShadow(color: Color(0x99FFD21A), blurRadius: 40),
                                  const BoxShadow(color: Color(0xB3000000), blurRadius: 18, offset: Offset(0, 8)),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(tile * 0.1),
                                child: ordered[i].won
                                    ? AvatarImage(ordered[i].avatar, size: tile - 16)
                                    : ColorFiltered(colorFilter: _gray, child: AvatarImage(ordered[i].avatar, size: tile - 16)),
                              ),
                            ),
                            if (ordered[i].won)
                              Positioned(
                                left: -46,
                                top: -40,
                                child: Transform.rotate(
                                  angle: -0.2,
                                  child: Text(t.winBadge,
                                      style: AppText.label(64, color: const Color(0xFFFFC21A), weight: FontWeight.w900).copyWith(shadows: const [
                                        Shadow(color: Color(0xFFB85A00), offset: Offset(0, 5)),
                                        Shadow(color: Color(0xCC000000), blurRadius: 10, offset: Offset(0, 8)),
                                      ])),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: tile + 30,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(ordered[i].name.toUpperCase(),
                                maxLines: 1,
                              style: AppText.label(30, color: ordered[i].me ? DuelColors.gold : DuelColors.silver, weight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (bet.staked)
              Positioned(
                left: 0,
                right: 0,
                top: 730,
                child: Center(
                  child: Text(
                    me.won ? t.youWonAmount(formatPicoCoins(bet.prize)) : t.betterLuckNext,
                    style: AppText.label(26, color: me.won ? DuelColors.green : DuelColors.dim, weight: FontWeight.w900),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _coins,
                  builder: (context, _) => Stack(
                    children: [
                      for (final coin in _fly) _flyingCoin(coin, spot),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(left: 44, bottom: 34, child: NavTile(icon: Icons.reply_rounded, label: t.back, onTap: widget.onBack)),
            Positioned(
              right: 44,
              bottom: 34,
              child: NavTile(icon: Icons.query_stats_rounded, label: t.navData, onTap: () => pushScreen(context, const HistoryScreen())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flyingCoin(_FlyCoin coin, Offset spot) {
    final span = (1 - coin.delay).clamp(0.35, 1.0);
    final raw = ((_coins.value - coin.delay) / span).clamp(0.0, 1.0);
    if (raw <= 0) return const SizedBox.shrink();
    final travel = Curves.easeIn.transform(raw);
    final arc = sin(raw * pi) * 90;
    final pos = Offset.lerp(coin.from, spot, travel)! + Offset(0, -arc);
    final fade = raw < 0.12 ? raw / 0.12 : (raw > 0.82 ? (1 - raw) / 0.18 : 1.0);
    return Positioned(
      left: pos.dx - coin.size / 2,
      top: pos.dy - coin.size / 2,
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: coin.spin * raw,
          child: Transform.scale(
            scale: 0.55 + sin(raw * pi) * 0.7,
            child: PikoCoinIcon(size: coin.size),
          ),
        ),
      ),
    );
  }
}
