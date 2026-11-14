import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/turn_life_dots.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../game/carrom/carrom_physics.dart';
import '../../game/physics/vec2.dart';
import '../duel/match_overlays.dart';
import '../game/widgets/overlays.dart';
import '../misc/how_to_play_screen.dart';
import '../online/game_link.dart';
import '../online/opponent_presence.dart';
import '../online/session.dart';
import 'carrom_board.dart';
import '../../l10n/strings.dart';
import '../game/match_chat_dialog.dart';
import 'carrom_chat.dart';
import 'carrom_controller.dart';
import 'carrom_skins.dart';

/// One carrom match, laid out like Carrom Pool: the board in the middle, a
/// player card on each side, the striker slider under the board.
class CarromScreen extends ConsumerStatefulWidget {
  const CarromScreen({super.key, required this.config, this.driver});

  final CarromMatchConfig config;
  final OnlineGameDriver? driver;

  @override
  ConsumerState<CarromScreen> createState() => _CarromScreenState();
}

class _CarromScreenState extends ConsumerState<CarromScreen> with SingleTickerProviderStateMixin {
  late final CarromController _c;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;
  bool _resultBooked = false;

  // Portrait canvas (1080 wide): board across the width, slider under it.
  static const _canvasW = PortraitGameCanvas.width;
  static const _boardSize = 1040.0;
  static const _boardLeft = (_canvasW - _boardSize) / 2;
  static const _sliderW = 720.0;
  static const _sliderH = 60.0;
  static const _sliderLeft = (_canvasW - _sliderW) / 2;

  @override
  void initState() {
    super.initState();
    ref.read(audioProvider).playGameplayMusic();
    _c = CarromController(widget.config, ref.read(audioProvider), link: widget.driver)..addListener(_onChanged);
    final driver = widget.driver;
    if (driver != null) {
      driver
        ..onState = _c.applyRemote
        ..onPresence = _c.applyPresence
        ..onAim = _c.applyRemoteAim
        ..onChat = _c.showChat
        ..onChatText = _c.showChatText
        ..onError = _onNetError
        ..start();
    }
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      // Offline play stops while the pause menu is open; online the server runs on.
      if (!_paused || _c.online) _c.tick(min(dt, 0.1));
    })
      ..start();
  }

  void _onChanged() {
    if (_c.over && !_resultBooked) {
      _resultBooked = true;
      if (widget.driver != null) {
        ref.read(sessionProvider.notifier).refresh().catchError((_) {});
      } else {
        // Practice: a little experience, no coins (the server cannot verify it).
        final api = ref.read(apiProvider);
        final won = _c.state.winner == 0;
        api?.post('/matches/bot', {'game': 'carrom', 'won': won}).then((j) {
          final u = j['user'];
          if (u is Map<String, dynamic>) ref.read(sessionProvider.notifier).adopt(u);
        }).catchError((_) {});
      }
    }
    if (mounted) setState(() {});
  }

  void _onNetError(ApiException e) {
    if (e.code != 'network') _c.onActionRejected();
  }

  Future<void> _quit() async {
    final driver = widget.driver;
    final navigator = Navigator.of(context);
    if (driver != null && !_c.over) {
      driver.send({'type': 'leave'});
      await driver.idle;
    }
    navigator.pop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _c.removeListener(_onChanged);
    _c.dispose();
    ref.read(audioProvider).playMenuMusic();
    super.dispose();
  }

  // ---- board gestures -------------------------------------------------------

  Vec2? _pullFrom;

  void _panStart(Offset local, Size size) {
    if (!_c.canAim) return;
    _pullFrom = CarromBoard.toBoard(local, size, _c.viewRotated);
  }

  void _panUpdate(Offset local, Size size) {
    final from = _pullFrom;
    if (from == null || !_c.canAim) return;
    final now = CarromBoard.toBoard(local, size, _c.viewRotated);
    _c.updateAim(now - from);
  }

  void _panEnd() {
    if (_pullFrom == null) return;
    _pullFrom = null;
    _c.releaseShot();
  }

  // ---- striker slider --------------------------------------------------------

  void _slideTo(double localX) {
    if (!_c.canAim) return;
    final k = (localX / _sliderW).clamp(0.0, 1.0);
    final x = CarromWorld.baseMinX + (CarromWorld.baseMaxX - CarromWorld.baseMinX) * (_c.viewRotated ? 1 - k : k);
    _c.setStrikerX(x);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _paused = !_paused);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF2B0B0B),
        body: _CarromBackground(
          child: PortraitGameCanvas(builder: (context, height) => _table(context, height, settings)),
        ),
      ),
    );
  }

  /// Portrait table as in Carrom Pool: the opponent above the board, the
  /// striker slider and this player's card below it.
  Widget _table(BuildContext context, double height, AppSettings settings) {
    final boardTop = (height - _boardSize) / 2 - 40;
    final boardBottom = boardTop + _boardSize;
    final sliderTop = boardBottom + 16;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(left: 30, top: 0, child: _MenuTab(onTap: () => setState(() => _paused = true))),
        if (widget.config.bet.staked)
          Positioned(
            right: 40,
            top: boardTop - 24 - MatchPrizeTile.size - 60,
            child: MatchPrizeTile(prize: widget.config.bet.prize),
          ),
        // The board.
        Positioned(
          left: _boardLeft,
          top: boardTop,
          width: _boardSize,
          height: _boardSize,
          child: RepaintBoundary(
            child: CarromBoard(controller: _c, onPanStart: _panStart, onPanUpdate: _panUpdate, onPanEnd: _panEnd),
          ),
        ),
        // Striker slider under the board.
        Positioned(
          left: _sliderLeft,
          top: sliderTop,
          width: _sliderW,
          height: _sliderH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _slideTo(d.localPosition.dx),
            onHorizontalDragStart: (d) => _slideTo(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => _slideTo(d.localPosition.dx),
            child: _StrikerSlider(controller: _c),
          ),
        ),
        ..._seatPanels(boardTop, sliderTop + _sliderH),
        Positioned(
          left: 60,
          top: sliderTop + _sliderH + 60,
          child: Transform.scale(scale: 1.5, alignment: Alignment.topLeft, child: _ChatButton(onTap: _openChat)),
        ),
        // What to do now.
        Positioned(
          left: _canvasW / 2 + _SeatPanel.width / 2 + 10,
          right: 30,
          top: sliderTop + _sliderH + 70,
          child: Text(
            _c.hint,
            textAlign: TextAlign.center,
            style: AppText.label(28, color: _c.canAim ? DesignGameplay.hintActive : DesignGameplay.hintIdle, weight: FontWeight.w900)
                .copyWith(shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 2))]),
          ),
        ),
        // Messages over the board.
        Positioned(
          left: _boardLeft,
          width: _boardSize,
          top: boardTop + _boardSize / 2 - 60,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _c.toast == null
                    ? const SizedBox.shrink()
                    : Transform.scale(
                        key: ValueKey(_c.toast),
                        scale: 1.3,
                        child: GameplayToastBanner(lines: _c.toast!.lines, good: _c.toast!.good),
                      ),
              ),
            ),
          ),
        ),
        if (widget.driver != null) ...[
          OpponentDisconnectBanner(
            presence: _c.opponentPresence,
            serverOffsetMs: _c.serverOffsetMs,
            opponentName: widget.config.seats[1 - widget.driver!.seat].name,
          ),
          ConnectionStatusLayer(
            offline: widget.driver!.offline,
            onLeave: () => Navigator.of(context).pop(),
            scale: 1.35,
          ),
        ],
        if (_c.over) _result(),
        if (_paused)
          PauseOverlay(
            scale: 1.6,
            soundOn: settings.soundOn,
            onResume: () => setState(() => _paused = false),
            onToggleSound: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(soundOn: !s.soundOn)),
            onRules: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen())),
            onQuit: _quit,
          ),
      ],
    );
  }

  List<Widget> _seatPanels(double boardTop, double belowSlider) {
    final state = _c.state;
    final session = ref.watch(sessionProvider);
    final myCoins = ref.watch(settingsProvider).coins;
    return [
      for (var seat = 0; seat < 2; seat++)
        Builder(builder: (context) {
          final p = state.players[seat];
          final you = seat == _c.mySeat;
          // HUD only — IgnorePointer so the 420-tall card cannot steal
          // aim/pan hits from the board (portrait overlap above the frame).
          return Positioned(
            left: (_canvasW - _SeatPanel.width) / 2,
            // Opponent: avatar, name and score end just above the board.
            top: you ? belowSlider + 24 : boardTop - 296,
            child: IgnorePointer(
              child: _SeatPanel(
                name: p.name,
                avatar: p.avatar,
                colour: p.colour,
                pocketed: p.pocketed,
                hasQueen: p.hasQueen,
                active: _c.turn == seat && !_c.over,
                out: p.out,
                you: you,
                coins: you ? myCoins : null,
                level: you ? session.level : null,
                right: !you,
                clock: _c.clock,
                shotSeconds: state.shotSeconds,
                pieces: _c.pieceSkin,
                chat: _c.chatTextOf(seat),
                missed: widget.driver != null ? p.missed : null,
              ),
            ),
          );
        }),
    ];
  }

  void _openChat() {
    final t = ref.read(stringsProvider);
    showMatchChatDialog(
      context: context,
      t: t,
      maxCustomLength: CarromChat.maxCustomLength,
      phrases: CarromChat.phrases,
      emojis: CarromChat.emojis,
      onPreset: _c.sayChat,
      onCustom: _c.sayCustomChat,
    );
  }

  Widget _result() {
    final state = _c.state;
    final w = state.winner!;
    return DuelResultOverlay(
      players: [
        for (var i = 0; i < 2; i++)
          ResultPlayer(name: state.players[i].name, avatar: state.players[i].avatar, won: i == w, me: i == _c.mySeat),
      ],
      bet: widget.config.bet,
      reason: ref.read(stringsProvider).formatMatchWinReason(state.winReason),
      onBack: () => Navigator.of(context).pop(),
    );
  }
}

/// Player card as in Carrom Pool: a square avatar with a coloured frame
/// (blue for you, orange for the opponent), the name, and the score next to
/// a piece of the player's colour. The turn clock runs round the avatar.
class _SeatPanel extends StatelessWidget {
  const _SeatPanel({
    required this.name,
    required this.avatar,
    required this.colour,
    required this.pocketed,
    required this.hasQueen,
    required this.active,
    required this.out,
    required this.you,
    this.coins,
    this.level,
    required this.right,
    required this.clock,
    required this.shotSeconds,
    required this.pieces,
    this.missed,
    this.chat,
  });

  static const width = 300.0;
  static const _box = 150.0;

  final String name;
  final String avatar;
  final int colour;
  final int pocketed;
  final bool hasQueen;
  final bool active;
  final bool out;
  final bool you;
  final int? coins;
  final int? level;
  final bool right;
  final ValueListenable<double> clock;
  final int shotSeconds;
  final PieceSkin pieces;
  final int? missed;
  final String? chat;

  static const _shadow = [Shadow(color: Color(0xCC000000), blurRadius: 3, offset: Offset(0, 1.5))];

  @override
  Widget build(BuildContext context) {
    final frameColor = right ? const Color(0xFFF2821A) : const Color(0xFF2E8BE8);
    return Opacity(
      opacity: out ? 0.5 : 1,
      child: SizedBox(
        width: width,
        height: 420,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Avatar in a coloured frame, with the turn ring when active.
            Positioned(
              top: 0,
              child: SizedBox(
                width: _box + 20,
                height: _box + 20,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (active)
                      ValueListenableBuilder<double>(
                        valueListenable: clock,
                        builder: (_, left, _) => CustomPaint(
                          size: const Size(_box + 20, _box + 20),
                          painter: _TurnRingPainter(shotSeconds <= 0 ? 1 : (left / shotSeconds).clamp(0.0, 1.0)),
                        ),
                      ),
                    Container(
                      width: _box,
                      height: _box,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(frameColor, Colors.white, 0.35)!, frameColor]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          if (active) BoxShadow(color: frameColor.withValues(alpha: 0.7), blurRadius: 18, spreadRadius: 1),
                          const BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 3)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: FittedBox(fit: BoxFit.cover, child: AvatarImage(avatar, size: 140)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (missed != null)
              Positioned(
                top: _box + 8,
                left: 0,
                right: 0,
                child: Center(child: TurnLifeDots(missed: missed!, size: 11)),
              ),
            Positioned(
              top: _box + 26,
              child: SizedBox(
                width: width,
                child: Text(
                  name,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(30, color: Colors.white, weight: FontWeight.w900).copyWith(shadows: _shadow),
                ),
              ),
            ),
            // Score: count beside a piece of this player's colour (+ the queen when won).
            Positioned(
              top: _box + 74,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!right) ...[
                    Text('$pocketed', style: AppText.label(40, color: Colors.white, weight: FontWeight.w900).copyWith(shadows: _shadow)),
                    const SizedBox(width: 10),
                  ],
                  CustomPaint(size: const Size(42, 42), painter: _PieceIconPainter(colour == 0 ? DiscKind.light : DiscKind.dark, pieces)),
                  if (hasQueen) ...[const SizedBox(width: 6), CustomPaint(size: const Size(30, 30), painter: _PieceIconPainter(DiscKind.queen, pieces))],
                  if (right) ...[
                    const SizedBox(width: 10),
                    Text('$pocketed', style: AppText.label(40, color: Colors.white, weight: FontWeight.w900).copyWith(shadows: _shadow)),
                  ],
                ],
              ),
            ),
            if (you && coins != null)
              Positioned(
                top: _box + 134,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CustomPaint(size: Size(34, 28), painter: _CoinStackPainter()),
                    const SizedBox(width: 6),
                    Text(
                      formatCoins(coins!),
                      style: AppText.label(22, color: Colors.white, weight: FontWeight.w900).copyWith(shadows: _shadow),
                    ),
                    if (level != null) ...[
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xAA000000),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFF2C230), width: 2),
                        ),
                        child: Text(
                          'LVL $level',
                          style: AppText.label(16, color: const Color(0xFFFFE27A), weight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (chat != null)
              Positioned(
                top: -58,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)]),
                  child: Text(
                    chat!,
                    style: TextStyle(
                      fontSize: chat!.runes.length <= 4 ? 26 : 16,
                      height: 1.1,
                      color: const Color(0xFF1B1F2A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Depleting ring round the active avatar (green -> amber -> red).
class _TurnRingPainter extends CustomPainter {
  _TurnRingPainter(this.left);

  final double left;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius((Offset.zero & size).deflate(3), const Radius.circular(18));
    canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = const Color(0x66000000));
    final metric = (Path()..addRRect(rr)).computeMetrics().first;
    final colour = left > 0.5 ? const Color(0xFF3BE34F) : (left > 0.25 ? const Color(0xFFFFC02E) : const Color(0xFFFF4A3D));
    canvas.drawPath(
      metric.extractPath(0, metric.length * left),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = colour,
    );
  }

  @override
  bool shouldRepaint(_TurnRingPainter old) => old.left != left;
}

/// A carrom man seen from above, in the chosen piece set.
class _PieceIconPainter extends CustomPainter {
  const _PieceIconPainter(this.kind, this.pieces);

  final DiscKind kind;
  final PieceSkin pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    paintCarromDisc(canvas, Offset(r, r), r * 0.92, kind, striker: strikerSkins.first, pieces: pieces);
  }

  @override
  bool shouldRepaint(_PieceIconPainter old) => old.kind != kind || old.pieces != pieces;
}

/// The bar under the board the striker slides along; the knob mirrors where
/// the striker stands on the base line.
class _StrikerSlider extends StatelessWidget {
  const _StrikerSlider({required this.controller});

  final CarromController controller;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SliderPainter(controller));
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.c) : super(repaint: c.frame);

  final CarromController c;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(rr.shift(const Offset(0, 4)), Paint()..color = const Color(0x66000000));
    canvas.drawRRect(rr, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8C5A3C), Color(0xFF5B3A2E)]).createShader(Offset.zero & size));
    canvas.drawRRect(rr.deflate(4), Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFFB07A52));
    canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFF3F271F));
    final enabled = c.canAim;
    var k = (c.strikerX - CarromWorld.baseMinX) / (CarromWorld.baseMaxX - CarromWorld.baseMinX);
    if (c.viewRotated) k = 1 - k;
    final knob = Offset(size.width * (0.06 + 0.88 * k), size.height / 2);
    final r = size.height * 0.46;
    if (enabled) {
      canvas.drawCircle(knob, r * 1.4, Paint()..color = const Color(0x55FFD54A)..maskFilter = MaskFilter.blur(BlurStyle.normal, 8));
    }
    paintCarromDisc(canvas, knob, r, DiscKind.striker, striker: c.strikerSkin, pieces: c.pieceSkin);
  }

  @override
  bool shouldRepaint(_SliderPainter old) => true;
}

class _ChatButton extends StatelessWidget {
  const _ChatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AudioService.tap();
          onTap();
        },
        child: CustomPaint(size: const Size(78, 66), painter: _BubblePainter()),
      );
}

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height * 0.78), Radius.circular(size.height * 0.26));
    canvas.drawRRect(r.shift(const Offset(0, 4)), Paint()..color = const Color(0x55000000));
    canvas.drawRRect(r, Paint()..color = Colors.white);
    final tail = Path()
      ..moveTo(size.width * 0.28, size.height * 0.74)
      ..lineTo(size.width * 0.2, size.height)
      ..lineTo(size.width * 0.46, size.height * 0.74)
      ..close();
    canvas.drawPath(tail, Paint()..color = Colors.white);
    canvas.drawRRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFF1B1F2A));
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(size.width * (0.3 + i * 0.2), size.height * 0.38), size.height * 0.072, Paint()..color = const Color(0xFF2A3350));
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) => false;
}

class _MenuTab extends StatelessWidget {
  const _MenuTab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AudioService.tap();
          onTap();
        },
        child: const CustomPaint(size: Size(96, 46), painter: _MenuTabPainter()),
      );
}

class _MenuTabPainter extends CustomPainter {
  const _MenuTabPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final tab = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w * 0.8, h * 0.82)
      ..quadraticBezierTo(w * 0.77, h, w * 0.68, h)
      ..lineTo(w * 0.32, h)
      ..quadraticBezierTo(w * 0.23, h, w * 0.2, h * 0.82)
      ..close();
    canvas.drawPath(tab.shift(const Offset(0, 3)), Paint()..color = const Color(0x66000000));
    canvas.drawPath(
      tab,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE27A), Color(0xFFE9A920)]).createShader(Offset.zero & size),
    );
    canvas.drawPath(tab, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF8A5A00));
    final line = Paint()
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF6B4300);
    for (var i = 0; i < 3; i++) {
      final y = h * (0.26 + i * 0.2);
      canvas.drawLine(Offset(w * 0.38, y), Offset(w * 0.62, y), line);
    }
  }

  @override
  bool shouldRepaint(_MenuTabPainter old) => false;
}

class _CoinStackPainter extends CustomPainter {
  const _CoinStackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    for (var i = 2; i >= 0; i--) {
      final y = h * 0.62 - i * h * 0.2;
      final rect = Rect.fromCenter(center: Offset(w / 2, y), width: w, height: h * 0.4);
      canvas.drawOval(rect.shift(Offset(0, h * 0.1)), Paint()..color = const Color(0xFF8A5A00));
      canvas.drawOval(rect, Paint()..shader = const LinearGradient(colors: [Color(0xFFFFE27A), Color(0xFFE9A920)]).createShader(rect));
      canvas.drawOval(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = const Color(0xFF8A5A00));
    }
  }

  @override
  bool shouldRepaint(_CoinStackPainter old) => false;
}

/// Carrom Pool's deep red felt behind the board, lit from the middle.
class _CarromBackground extends StatelessWidget {
  const _CarromBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _BgPainter())),
          child,
        ],
      );
}

class _BgPainter extends CustomPainter {
  const _BgPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const RadialGradient(center: Alignment(0, 0.1), radius: 0.9, colors: [Color(0xFF8E1E1E), Color(0xFF4A0F0F), Color(0xFF240707)], stops: [0, 0.55, 1]).createShader(rect));
    // Faint diagonal weave.
    final weave = Paint()..color = Colors.white.withValues(alpha: 0.025)..strokeWidth = 2;
    for (var x = -size.height; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), weave);
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => false;
}
