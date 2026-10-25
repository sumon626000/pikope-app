import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../core/turn_life_dots.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../game/ludo/ludo_rules.dart';
import '../duel/match_overlays.dart';
import '../game/widgets/overlays.dart';
import '../misc/how_to_play_screen.dart';
import '../online/game_link.dart';
import '../online/session.dart';
import 'ludo_board.dart';
import '../../l10n/strings.dart';
import 'ludo_controller.dart';

class LudoScreen extends ConsumerStatefulWidget {
  const LudoScreen({super.key, required this.config, this.driver, this.colours});

  final LudoMatchConfig config;
  final OnlineGameDriver? driver;
  final List<int>? colours;

  @override
  ConsumerState<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends ConsumerState<LudoScreen> with SingleTickerProviderStateMixin {
  late final LudoController _c;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;
  bool _resultBooked = false;

  @override
  void initState() {
    super.initState();
    ref.read(audioProvider).playGameplayMusic();
    _c = LudoController(widget.config, ref.read(audioProvider), link: widget.driver, colours: widget.colours)
      ..addListener(_onChanged);
    final driver = widget.driver;
    if (driver != null) {
      driver
        ..onState = _c.applyRemote
        ..onChat = _c.showChat
        ..onError = _onNetError
        ..start();
    } else {
      _c.start();
    }
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      // Offline play stops while the pause menu is open; online the server runs on.
      if (!_paused || _c.online) _c.tick(min(dt, 0.1));
    })
      ..start();
  }

  bool _wasMyTurn = false;

  void _onChanged() {
    // A chime when the turn comes round to this player.
    final myTurn = _c.isMyTurn && !_c.over;
    if (myTurn && !_wasMyTurn) ref.read(audioProvider).play(Sfx.turn, volume: 0.6);
    _wasMyTurn = myTurn;
    if (_c.over && !_resultBooked) {
      _resultBooked = true;
      if (widget.driver != null) ref.read(sessionProvider.notifier).refresh().catchError((_) {});
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final state = _c.state;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _paused = !_paused);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF060814),
        body: _LudoBackground(
          child: SafeArea(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 1950,
                  height: 900,
                  child: state == null
                      ? const Center(child: CircularProgressIndicator(color: DuelColors.silver))
                      : Stack(
                          children: [
                            // Gold menu tab hanging from the top edge.
                            Positioned(left: 64, top: 0, child: _MenuTab(onTap: () => setState(() => _paused = true))),
                            // Pot indicator (only for staked online games); own balance shows on the seat card.
                            if (widget.config.bet.staked)
                              Positioned(
                                left: 20,
                                top: 58,
                                child: MatchPrizeTile(prize: widget.config.bet.prize),
                              ),
                            // The board, centred.
                            Positioned(
                              left: (1950 - 820) / 2,
                              top: (900 - 820) / 2,
                              width: 820,
                              height: 820,
                              child: RepaintBoundary(child: _Board(controller: _c, theme: ludoThemeOf(settings.ludoBoard), onTapToken: _c.moveToken)),
                            ),
                            // Player cards beside the board corners (dice sits in the active card).
                            ..._seatPanels(),
                            // Chat bubble above the bottom-left card.
                            Positioned(left: 232, top: 474, child: _ChatButton(onTap: _openChat)),
                            // What to do now, under the board.
                            Positioned(
                              left: (1950 - 820) / 2,
                              width: 820,
                              top: 862,
                              height: 36,
                              child: Center(
                                child: Text(
                                  _hint(),
                                  style: AppText.label(22, color: _c.canRoll || _c.movable.isNotEmpty ? const Color(0xFFFFE45C) : Colors.white70, weight: FontWeight.w900)
                                      .copyWith(shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 2))]),
                                ),
                              ),
                            ),
                            // Event messages over the board centre.
                            Positioned(
                              left: (1950 - 820) / 2,
                              width: 820,
                              top: 410,
                              child: IgnorePointer(
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: _c.toast == null
                                        ? const SizedBox.shrink()
                                        : Container(
                                            key: ValueKey(_c.toast),
                                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xE6101A3A),
                                              borderRadius: BorderRadius.circular(30),
                                              border: Border.all(color: const Color(0xFFF2C230), width: 3),
                                              boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 12)],
                                            ),
                                            child: Text(_c.toast!, style: AppText.label(30, color: Colors.white, weight: FontWeight.w900)),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            if (widget.driver != null)
                              ConnectionStatusLayer(
                                offline: widget.driver!.offline,
                                onLeave: () => Navigator.of(context).pop(),
                              ),
                            if (_c.over) _result(),
                            if (_paused)
                              PauseOverlay(
                                soundOn: settings.soundOn,
                                onResume: () => setState(() => _paused = false),
                                onToggleSound: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(soundOn: !s.soundOn)),
                                onRules: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen())),
                                onQuit: _quit,
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _hint() {
    final state = _c.state!;
    if (_c.over) return '';
    if (_c.canRoll) return 'YOUR TURN - TAP THE DICE';
    if (_c.movable.isNotEmpty) return 'TAP A GLOWING TOKEN TO MOVE';
    if (_c.isMyTurn || _c.diceSeat != state.turn) return '';
    final p = state.players[_c.diceSeat];
    return '${p.name.toUpperCase()} IS PLAYING...';
  }

  static const _countries = [
    ['AL', 'Albania'], ['NG', 'Nigeria'], ['IN', 'India'], ['BD', 'Bangladesh'], ['BR', 'Brazil'],
    ['PK', 'Pakistan'], ['ID', 'Indonesia'], ['EG', 'Egypt'], ['PH', 'Philippines'], ['TR', 'Turkey'],
    ['US', 'USA'], ['MY', 'Malaysia'], ['NP', 'Nepal'], ['SA', 'Saudi Arabia'], ['GB', 'UK'],
  ];

  List<Widget> _seatPanels() {
    final state = _c.state!;
    final session = ref.watch(sessionProvider);
    // The player's own balance (the pot has its own tile).
    final myCoins = ref.watch(settingsProvider).coins;
    final locale = WidgetsBinding.instance.platformDispatcher.locale.countryCode?.toUpperCase();
    const left = 565.0 - 34 - _SeatPanel.width, right = 1385.0 + 34;
    return [
      for (var seat = 0; seat < state.seats; seat++)
        Builder(builder: (context) {
          final p = state.players[seat];
          final top = p.colour == 1 || p.colour == 2;
          final mirror = p.colour == 2 || p.colour == 3;
          final you = _c.online && seat == _c.mySeat || (!_c.online && seat == 0);
          final active = _c.diceSeat == seat && !_c.over;
          final h = p.name.hashCode & 0x7fffffff;
          List<String>? country;
          if (you && locale != null) {
            country = _countries.firstWhere((c) => c[0] == locale, orElse: () => [locale, '']);
          } else if (p.isBot) {
            country = _countries[h % _countries.length];
          }
          return Positioned(
            left: mirror ? right : left,
            top: top ? 46 : 548,
            child: _SeatPanel(
              name: p.name,
              avatar: p.avatar,
              colour: LudoBoard.colours[p.colour],
              active: active,
              out: p.out,
              coins: you ? myCoins : 500 + (h % 9500) ~/ 50 * 50,
              level: you ? session.level : 1 + h % 10,
              country: country,
              top: top,
              mirror: mirror,
              face: _c.diceFace,
              rolling: active && _c.diceRolling,
              canRoll: active && _c.canRoll,
              onRoll: _c.roll,
              missed: p.missed,
              clock: _c.clock,
              turnLeft: active && _c.online ? () => _c.turnLeft : null,
              chat: _c.chatOf(seat) == null ? null : ludoChatPresets[_c.chatOf(seat)!],
            ),
          );
        }),
    ];
  }

  void _openChat() {
    final t = ref.read(stringsProvider);
    showDuelDialog<void>(
      context,
      barrierColor: const Color(0xAA000000),
      builder: (dialog) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(22),
          decoration: duelPanel(rim: DuelColors.rimLight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.quickChat, style: AppText.label(18, weight: FontWeight.w900)),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < ludoChatPresets.length; i++)
                    GestureDetector(
                      onTap: () {
                        AudioService.tap();
                        Navigator.of(dialog).pop();
                        _c.sayChat(i);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: duelPanel(radius: 12, rim: DuelColors.rim),
                        child: Text(ludoChatPresets[i], style: AppText.label(15, color: DuelColors.silver, weight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              DuelButton(label: t.close, width: 150, height: 44, color: DuelColors.rimLight, onPressed: () => Navigator.of(dialog).pop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _result() {
    final state = _c.state!;
    final w = state.winner!;
    return DuelResultOverlay(
      players: [
        for (var i = 0; i < state.seats; i++)
          ResultPlayer(
            name: state.players[i].name,
            avatar: state.players[i].avatar,
            won: i == w,
            me: _c.online ? i == _c.mySeat : i == 0,
          ),
      ],
      bet: widget.config.bet,
      reason: state.winReason,
      onBack: () => Navigator.of(context).pop(),
    );
  }
}

/// Player card in the reference style: coins outside the card, flag/country
/// row, gift badge, avatar beside an item slot (the dice while it is this
/// player's turn), life dots, name, and the level in the card's notch.
class _SeatPanel extends StatelessWidget {
  const _SeatPanel({
    required this.name,
    required this.avatar,
    required this.colour,
    required this.active,
    required this.out,
    required this.coins,
    required this.level,
    required this.country,
    required this.top,
    required this.mirror,
    required this.face,
    required this.rolling,
    required this.canRoll,
    required this.onRoll,
    required this.missed,
    required this.clock,
    this.turnLeft,
    this.chat,
  });

  static const width = 280.0;
  static const _h = 236.0;
  static const _coinsH = 40.0;
  static const _pad = 14.0, _box = 118.0, _gap = 16.0;
  static const _notchY = 198.0;

  final String name;
  final String avatar;
  final Color colour;
  final bool active;
  final bool out;
  final int coins;
  final int level;
  final List<String>? country;
  final bool top;
  final bool mirror;
  final int face;
  final bool rolling;
  final bool canRoll;
  final VoidCallback onRoll;
  final int missed;

  /// Frame clock for the bouncing roll arrow and the turn ring.
  final ValueListenable<double> clock;

  /// Online: fraction of the turn time left, drawn round the avatar.
  final double? Function()? turnLeft;

  /// Quick-chat line this player is saying.
  final String? chat;

  static const _shadow = [Shadow(color: Color(0xCC000000), blurRadius: 3, offset: Offset(0, 1.5))];

  static String _fmt(int n) {
    final str = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) b.write(',');
      b.write(str[i]);
    }
    return b.toString();
  }

  double _x(double lx, double w) => mirror ? width - lx - w : lx;

  @override
  Widget build(BuildContext context) {
    final cardTop = top ? _coinsH : 0.0;
    const slotX = _pad + _box + _gap;
    return Opacity(
      opacity: out ? 0.5 : 1,
      child: SizedBox(
        width: width,
        height: _h + _coinsH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: cardTop,
              width: width,
              height: _h,
              child: CustomPaint(painter: _CardPainter(mirror: mirror, notchX: slotX - 8, notchY: _notchY)),
            ),
            // Coins outside the card: above for top seats, below for bottom seats.
            Positioned(
              left: mirror ? null : 6,
              right: mirror ? 6 : null,
              top: top ? 0 : _h + 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CustomPaint(size: Size(34, 28), painter: _CoinStackPainter()),
                  const SizedBox(width: 6),
                  Text(_fmt(coins), style: AppText.label(22, color: Colors.white, weight: FontWeight.w900).copyWith(shadows: _shadow)),
                ],
              ),
            ),
            // Flag + country.
            Positioned(
              left: mirror ? 62 : _pad,
              right: mirror ? _pad : 62,
              top: cardTop + 11,
              height: 34,
              child: Row(
                mainAxisAlignment: mirror ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (mirror) ...[_countryText(), const SizedBox(width: 8)],
                  _flag(),
                  if (!mirror) ...[const SizedBox(width: 8), _countryText()],
                ],
              ),
            ),
            // Gift badge over the outer top corner.
            Positioned(left: _x(width - 44, 56), top: cardTop - 12, child: const _GiftBadge()),
            // Avatar.
            Positioned(
              left: _x(_pad, _box),
              top: cardTop + 52,
              child: Container(
                width: _box,
                height: _box,
                padding: EdgeInsets.all(active ? 3 : 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: active ? Border.all(color: const Color(0xFF3BE34F), width: 5) : null,
                  boxShadow: [
                    if (active) const BoxShadow(color: Color(0xAA3BE34F), blurRadius: 14, spreadRadius: 1),
                    const BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: FittedBox(fit: BoxFit.cover, child: AvatarImage(avatar, size: 110)),
                ),
              ),
            ),
            // Item slot, or the dice while this player is on turn.
            Positioned(left: _x(slotX, _box), top: cardTop + 52, child: active ? _diceSlot() : _emptySlot()),
            // Life dots under the slot.
            Positioned(
              left: _x(slotX, _box),
              top: cardTop + 176,
              width: _box,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TurnLifeDots(missed: missed, size: 12),
                ],
              ),
            ),
            // Name under the avatar (inside the card).
            Positioned(
              left: _x(6, _box + 2 * 8),
              top: cardTop + 186,
              width: _box + 2 * 8,
              height: 44,
              child: Center(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(21, color: Colors.white, weight: FontWeight.w900).copyWith(shadows: _shadow),
                ),
              ),
            ),
            // Online turn clock round the avatar.
            if (turnLeft != null)
              Positioned(
                left: _x(_pad - 5, _box + 10),
                top: cardTop + 47,
                width: _box + 10,
                height: _box + 10,
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: clock,
                    builder: (_, _, _) => CustomPaint(painter: _TurnRingPainter(turnLeft!() ?? 0)),
                  ),
                ),
              ),
            // Bouncing arrow pointing at the dice when it is the local player's roll.
            if (canRoll)
              Positioned(
                left: _x(slotX + _box / 2 - 26, 52),
                top: cardTop - 6,
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: clock,
                    builder: (_, t, _) => Transform.translate(
                      offset: Offset(0, (sin(t * 7)).abs() * 12),
                      child: const Icon(Icons.arrow_downward_rounded, size: 52, color: Color(0xFFFFE45C), shadows: [
                        Shadow(color: Color(0xEE000000), blurRadius: 6, offset: Offset(0, 2)),
                      ]),
                    ),
                  ),
                ),
              ),
            // Quick-chat bubble.
            if (chat != null)
              Positioned(
                left: mirror ? null : 4,
                right: mirror ? 4 : null,
                top: cardTop + 92,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF1B1F2A), width: 2.5),
                      boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: Text(chat!, style: AppText.label(19, color: const Color(0xFF1B1F2A), weight: FontWeight.w900)),
                  ),
                ),
              ),
            // Level in the notch, outside the card.
            Positioned(
              left: _x(slotX, _box),
              top: cardTop + _notchY + 4,
              width: _box,
              height: 34,
              child: Center(
                child: Text('Lvl $level', style: AppText.label(20, color: Colors.white, weight: FontWeight.w900).copyWith(shadows: _shadow)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countryText() {
    final c = country;
    if (c == null || c[1].isEmpty) return const SizedBox.shrink();
    return Flexible(
      child: Text(
        c[1],
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.label(20, color: Colors.white, weight: FontWeight.w900).copyWith(shadows: _shadow),
      ),
    );
  }

  Widget _flag() {
    final c = country;
    if (c == null) {
      return Container(
        width: 44,
        height: 32,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF3CCB9C), Color(0xFF1C80D2)]),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Icon(Icons.public, color: Colors.white, size: 22),
      );
    }
    final code = c[0];
    final emoji = String.fromCharCodes(code.codeUnits.map((u) => 0x1F1E6 + u - 0x41));
    return Container(
      width: 44,
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0E3A96),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: FittedBox(fit: BoxFit.cover, child: Text(emoji, style: const TextStyle(fontSize: 40, height: 1))),
    );
  }

  Widget _emptySlot() => Container(
        width: _box,
        height: _box,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF6DDE3), Color(0xFFE7B9C4)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFF3F6), width: 3),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2))],
        ),
      );

  Widget _diceSlot() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canRoll ? onRoll : null,
        child: Container(
          width: _box,
          height: _box,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(colour, Colors.white, 0.3)!, colour, Color.lerp(colour, Colors.black, 0.2)!],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              if (canRoll) const BoxShadow(color: Color(0xDDFFFFFF), blurRadius: 18, spreadRadius: 2),
              const BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: rolling ? (face - 3.5) * 0.35 : 0,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFDCE1EA)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x77000000), blurRadius: 6, offset: Offset(0, 3))],
              ),
              child: CustomPaint(painter: _DicePainter(face, Color.lerp(colour, Colors.black, 0.25)!)),
            ),
          ),
        ),
      );
}

/// Depleting ring round the active avatar (green -> amber -> red).
class _TurnRingPainter extends CustomPainter {
  _TurnRingPainter(this.left);

  final double left;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius((Offset.zero & size).deflate(3), const Radius.circular(10));
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

/// Card outline with the notch under the item slot (mirrored for right seats).
class _CardPainter extends CustomPainter {
  _CardPainter({required this.mirror, required this.notchX, required this.notchY});

  final bool mirror;
  final double notchX;
  final double notchY;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const r = 20.0, ri = 14.0;
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
      ..lineTo(w, notchY - r)
      ..arcToPoint(Offset(w - r, notchY), radius: const Radius.circular(r))
      ..lineTo(notchX + ri, notchY)
      ..arcToPoint(Offset(notchX, notchY + ri), radius: const Radius.circular(ri), clockwise: false)
      ..lineTo(notchX, h - r)
      ..arcToPoint(Offset(notchX - r, h), radius: const Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
      ..close();
    canvas.save();
    if (mirror) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawPath(path.shift(const Offset(0, 5)), Paint()
      ..color = const Color(0x77000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C7FEA), Color(0xFF1659C9), Color(0xFF0F45AA)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 7..color = const Color(0xFF4A3200));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE885), Color(0xFFE9B127), Color(0xFFFFD75A)],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardPainter old) => old.mirror != mirror || old.notchX != notchX || old.notchY != notchY;
}

/// Round gold-rimmed badge with a red gift box.
class _GiftBadge extends StatelessWidget {
  const _GiftBadge();

  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFF2A6FD6), Color(0xFF0C3A8E)]),
          border: Border.all(color: const Color(0xFFF2C230), width: 3.5),
          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 5, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: const CustomPaint(size: Size(32, 32), painter: _GiftPainter()),
      );
}

class _GiftPainter extends CustomPainter {
  const _GiftPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final red = Paint()..color = const Color(0xFFE53935);
    final redDark = Paint()..color = const Color(0xFFB71C1C);
    final gold = Paint()..color = const Color(0xFFFFD54F);
    canvas.drawRRect(RRect.fromLTRBR(w * 0.12, h * 0.42, w * 0.88, h * 0.98, Radius.circular(w * 0.06)), red);
    canvas.drawRRect(RRect.fromLTRBR(w * 0.04, h * 0.28, w * 0.96, h * 0.46, Radius.circular(w * 0.05)), redDark);
    canvas.drawRect(Rect.fromLTRB(w * 0.43, h * 0.28, w * 0.57, h * 0.98), gold);
    canvas.drawOval(Rect.fromLTRB(w * 0.18, h * 0.04, w * 0.5, h * 0.3), gold);
    canvas.drawOval(Rect.fromLTRB(w * 0.5, h * 0.04, w * 0.82, h * 0.3), gold);
    canvas.drawCircle(Offset(w * 0.5, h * 0.24), w * 0.07, Paint()..color = const Color(0xFFF9A825));
  }

  @override
  bool shouldRepaint(_GiftPainter old) => false;
}

/// Small pile of gold coins.
class _CoinStackPainter extends CustomPainter {
  const _CoinStackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final edge = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = const Color(0xFF8A5A00);
    void coin(Offset c, double rw, double rh) {
      final r = Rect.fromCenter(center: c, width: rw, height: rh);
      canvas.drawOval(r.shift(Offset(0, rh * 0.25)), Paint()..color = const Color(0xFFC88A12));
      canvas.drawOval(r, Paint()..shader = const LinearGradient(colors: [Color(0xFFFFE680), Color(0xFFF2B21E)]).createShader(r));
      canvas.drawOval(r, edge);
    }

    coin(Offset(w * 0.34, h * 0.8), w * 0.62, h * 0.32);
    coin(Offset(w * 0.34, h * 0.6), w * 0.62, h * 0.32);
    coin(Offset(w * 0.34, h * 0.4), w * 0.62, h * 0.32);
    final c = Offset(w * 0.72, h * 0.55);
    final rr = Rect.fromCircle(center: c, radius: h * 0.34);
    canvas.drawOval(rr, Paint()..shader = const RadialGradient(colors: [Color(0xFFFFEB8A), Color(0xFFF0A818)]).createShader(rr));
    canvas.drawOval(rr, edge);
    canvas.drawCircle(c, h * 0.2, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = const Color(0xFFB8860B));
  }

  @override
  bool shouldRepaint(_CoinStackPainter old) => false;
}

class _DicePainter extends CustomPainter {
  _DicePainter(this.face, this.pip);
  final int face;
  final Color pip;

  static const _pips = {
    1: [[0.5, 0.5]],
    2: [[0.28, 0.28], [0.72, 0.72]],
    3: [[0.26, 0.26], [0.5, 0.5], [0.74, 0.74]],
    4: [[0.28, 0.28], [0.72, 0.28], [0.28, 0.72], [0.72, 0.72]],
    5: [[0.26, 0.26], [0.74, 0.26], [0.5, 0.5], [0.26, 0.74], [0.74, 0.74]],
    6: [[0.28, 0.24], [0.72, 0.24], [0.28, 0.5], [0.72, 0.5], [0.28, 0.76], [0.72, 0.76]],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * (face == 1 ? 0.13 : 0.09);
    final paint = Paint()..color = pip;
    for (final p in _pips[face]!) {
      canvas.drawCircle(Offset(p[0] * size.width, p[1] * size.height), r, paint);
    }
  }

  @override
  bool shouldRepaint(_DicePainter old) => old.face != face || old.pip != pip;
}

class _Board extends StatelessWidget {
  const _Board({required this.controller, required this.theme, required this.onTapToken});

  final LudoController controller;
  final LudoBoardTheme theme;
  final void Function(int token) onTapToken;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        const size = 820.0;
        final s = size / LudoBoard.n;
        final movable = controller.movable;
        if (movable.isEmpty) return;
        final seat = controller.turn;
        // Find the nearest movable token to the tap.
        var best = -1;
        var bestDist = 1e9;
        for (final t in movable) {
          final pos = controller.tokenPos(seat, t);
          final c = Offset(pos[0] * s, pos[1] * s);
          final dist = (c - d.localPosition).distance;
          if (dist < bestDist) {
            bestDist = dist;
            best = t;
          }
        }
        if (best >= 0 && bestDist < s * 1.2) onTapToken(best);
      },
      child: CustomPaint(size: const Size.square(820), painter: _BoardPainter(controller, theme)),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.controller, this.theme) : super(repaint: Listenable.merge([controller, controller.clock]));

  final LudoController controller;
  final LudoBoardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / LudoBoard.n;
    Rect cellRect(int col, int row) => Rect.fromLTWH(col * s, row * s, s, s);
    Offset at(double gx, double gy) => Offset(gx * s, gy * s);
    final grid = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = theme.grid;
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.field);

    // Track cells; home lanes and start squares in their colour.
    for (final c in LudoBoard.path) {
      canvas.drawRect(cellRect(c[0], c[1]), Paint()..color = theme.track);
    }
    for (var colour = 0; colour < 4; colour++) {
      final fill = Paint()..color = LudoBoard.colours[colour];
      for (final c in LudoBoard.homeColumn[colour]) {
        canvas.drawRect(cellRect(c[0], c[1]), fill);
      }
      final st = LudoBoard.path[LudoRules.start[colour]];
      canvas.drawRect(cellRect(st[0], st[1]), fill);
    }
    // Clear cell outlines so every square reads.
    for (final c in LudoBoard.path) {
      canvas.drawRect(cellRect(c[0], c[1]), grid);
    }
    for (final lane in LudoBoard.homeColumn) {
      for (final c in lane) {
        canvas.drawRect(cellRect(c[0], c[1]), grid);
      }
    }

    // Yards: colour square, white inner square, four solid sockets.
    for (var colour = 0; colour < 4; colour++) {
      final y = LudoBoard.yardRect[colour];
      final rect = Rect.fromLTWH(y[0] * s, y[1] * s, y[2] * s, y[2] * s);
      final col = LudoBoard.colours[colour];
      canvas.drawRect(rect, Paint()..color = col);
      final inner = Rect.fromLTWH(rect.left + s, rect.top + s, s * 4, s * 4);
      canvas.drawRRect(RRect.fromRectAndRadius(inner, Radius.circular(s * 0.14)), Paint()..color = theme.track);
      for (final spot in LudoBoard.yard[colour]) {
        canvas.drawCircle(at(spot[0], spot[1]), s * 0.47, Paint()..color = col);
      }
      canvas.drawRect(rect, grid);
    }

    // Thin entry arrows at the tip of each arm.
    _tipArrow(canvas, cellRect(7, 0).center, s, _Dir.down, LudoBoard.colours[2]);
    _tipArrow(canvas, cellRect(0, 7).center, s, _Dir.right, LudoBoard.colours[1]);
    _tipArrow(canvas, cellRect(14, 7).center, s, _Dir.left, LudoBoard.colours[3]);
    _tipArrow(canvas, cellRect(7, 14).center, s, _Dir.up, LudoBoard.colours[0]);

    // Outlined stars on the safe squares.
    for (var i = 0; i < 52; i++) {
      if (LudoBoard.isSafe(i) && !LudoRules.start.contains(i)) {
        final c = LudoBoard.path[i];
        _drawStar(canvas, cellRect(c[0], c[1]).center, s * 0.36);
      }
    }

    // Centre four-colour triangles.
    final mid = at(7.5, 7.5);
    final tl = at(6, 6), tr = at(9, 6), br = at(9, 9), bl = at(6, 9);
    _tri(canvas, mid, tl, tr, LudoBoard.colours[2]); // top = red
    _tri(canvas, mid, tr, br, LudoBoard.colours[3]); // right = green
    _tri(canvas, mid, br, bl, LudoBoard.colours[0]); // bottom = yellow
    _tri(canvas, mid, bl, tl, LudoBoard.colours[1]); // left = blue
    canvas.drawRect(Rect.fromLTRB(tl.dx, tl.dy, br.dx, br.dy), grid);

    // Board edge.
    canvas.drawRect((Offset.zero & size).deflate(1.5), Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFF3A4252));

    // Footprints along the path a token just hopped, fading out.
    for (final m in controller.trail) {
      final alpha = controller.trailAlpha(m);
      if (alpha > 0) _drawFootprints(canvas, at(m.x, m.y), s, LudoBoard.colours[m.colour], m.angle, alpha);
    }

    // Tokens: stacked tokens fanned out, drawn top-to-bottom so lower pins overlap.
    final state = controller.state!;
    final movable = controller.movable;
    final activeSeat = controller.turn;
    final occupancy = <String, int>{};
    final pins = <(Offset, Color, bool)>[];
    final pulse = (sin(controller.clock.value * 6) + 1) / 2;
    for (var seat = 0; seat < state.seats; seat++) {
      for (var t = 0; t < 4; t++) {
        final pos = controller.tokenPos(seat, t);
        final key = '${pos[0].toStringAsFixed(1)},${pos[1].toStringAsFixed(1)}';
        final idx = occupancy[key] ?? 0;
        occupancy[key] = idx + 1;
        final centre = at(pos[0], pos[1]) + (idx == 0 ? Offset.zero : Offset((idx.isOdd ? 1 : -1) * s * 0.2, -idx * s * 0.06));
        final canMove = seat == activeSeat && movable.contains(t);
        // Hopping tokens lift; movable ones bob to invite a tap.
        final lift = controller.liftOf(seat, t) + (canMove ? pulse * 0.14 : 0);
        pins.add((centre - Offset(0, lift * s), LudoBoard.colours[state.players[seat].colour], canMove));
      }
    }
    pins.sort((a, b) => a.$1.dy.compareTo(b.$1.dy));
    for (final p in pins) {
      _drawPin(canvas, p.$1, s, p.$2, p.$3);
    }
  }

  /// One small footprint pointing along [angle], in the token's colour.
  void _drawFootprints(Canvas canvas, Offset c, double s, Color colour, double angle, double alpha) {
    final paint = Paint()..color = Color.lerp(colour, Colors.black, 0.25)!.withValues(alpha: 0.75 * alpha);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle + pi / 2); // foot drawn pointing up (-y)
    // sole, heel and toes
    canvas.drawOval(Rect.fromCenter(center: Offset(0, -s * 0.04), width: s * 0.13, height: s * 0.17), paint);
    canvas.drawOval(Rect.fromCenter(center: Offset(0, s * 0.09), width: s * 0.1, height: s * 0.1), paint);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset((i - 1) * s * 0.04, -s * 0.15 - (i == 1 ? s * 0.012 : 0)), s * 0.021, paint);
    }
    canvas.restore();
  }

  /// Reference-style token: a silver location pin standing in a coloured
  /// base ring, with a coloured disc in its head.
  void _drawPin(Canvas canvas, Offset c, double s, Color colour, bool movable) {
    final dark = Color.lerp(colour, Colors.black, 0.32)!;
    final base = c.translate(0, s * 0.16);
    if (movable) {
      canvas.drawOval(Rect.fromCenter(center: base, width: s * 1.0, height: s * 0.55), Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    canvas.drawOval(Rect.fromCenter(center: base, width: s * 0.8, height: s * 0.42), Paint()..color = dark);
    canvas.drawOval(Rect.fromCenter(center: base, width: s * 0.52, height: s * 0.25), Paint()..color = colour);
    if (movable) {
      canvas.drawOval(Rect.fromCenter(center: base, width: s * 0.82, height: s * 0.46),
          Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.05..color = Colors.white);
    }

    final hr = s * 0.36;
    final hc = c.translate(0, -s * 0.5);
    final a = acos(hr / (base - hc).distance);
    final pin = Path.combine(PathOperation.union, Path()..addOval(Rect.fromCircle(center: hc, radius: hr)), _teardrop(hc, base, hr, a));
    canvas.drawPath(pin.shift(Offset(s * 0.05, s * 0.04)), Paint()..color = const Color(0x55000000));
    canvas.drawPath(
      pin,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFE6EAF0), Color(0xFFB4BCC8)],
        ).createShader(Rect.fromCircle(center: hc, radius: hr * 1.8)),
    );
    canvas.drawPath(pin, Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.045..color = const Color(0xFF59616E));
    final disc = Rect.fromCircle(center: hc, radius: hr * 0.64);
    canvas.drawOval(
      disc,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(colour, Colors.white, 0.45)!, colour, dark],
          stops: const [0, 0.6, 1],
        ).createShader(disc),
    );
    canvas.drawOval(disc, Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.03..color = dark);
    canvas.drawCircle(hc.translate(-hr * 0.2, -hr * 0.22), hr * 0.14, Paint()..color = Colors.white.withValues(alpha: 0.85));
  }

  /// Triangle point of a pin: from [tip] up to two base points on the head
  /// circle at angle [a] either side of the downward vertical.
  Path _teardrop(Offset hc, Offset tip, double hr, double a) {
    final sx = sin(a) * hr, cy = cos(a) * hr;
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(hc.dx + sx, hc.dy + cy)
      ..lineTo(hc.dx - sx, hc.dy + cy)
      ..close();
  }

  void _drawStar(Canvas canvas, Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -pi / 2 + i * pi / 5;
      final rr = i.isEven ? r : r * 0.45;
      final p = c + Offset(cos(a), sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeJoin = StrokeJoin.round..color = theme.grid);
  }

  void _tipArrow(Canvas canvas, Offset c, double s, _Dir dir, Color colour) {
    final v = switch (dir) {
      _Dir.up => const Offset(0, -1),
      _Dir.down => const Offset(0, 1),
      _Dir.left => const Offset(-1, 0),
      _Dir.right => const Offset(1, 0),
    };
    final perp = Offset(-v.dy, v.dx);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = colour;
    final tip = c + v * s * 0.3;
    canvas.drawLine(c - v * s * 0.3, tip, pen);
    canvas.drawPath(
      Path()
        ..moveTo((tip - v * s * 0.17 + perp * s * 0.15).dx, (tip - v * s * 0.17 + perp * s * 0.15).dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo((tip - v * s * 0.17 - perp * s * 0.15).dx, (tip - v * s * 0.17 - perp * s * 0.15).dy),
      pen,
    );
  }

  void _tri(Canvas canvas, Offset a, Offset b, Offset c, Color colour) {
    canvas.drawPath(Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(c.dx, c.dy)..close(), Paint()..color = colour);
    canvas.drawPath(Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(c.dx, c.dy)..close(),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0x552A3350));
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}

enum _Dir { up, down, left, right }

/// White speech-bubble chat button (reference left side).
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
    // tail
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

/// Gold tab hanging from the top edge that opens the pause menu.
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
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE27A), Color(0xFFE9A920)],
        ).createShader(Offset.zero & size),
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

/// Full-screen Ludo wallpaper behind the table, on its own layer so the
/// animating board never makes it repaint.
class _LudoBackground extends StatelessWidget {
  const _LudoBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _LudoBgPainter(), isComplex: true)),
          child,
        ],
      );
}

/// Ludo King style wallpaper: giant Ludo boards tiled edge to edge, turned
/// 45 degrees and drawn only in shades of blue, so the real board on top
/// stands out.
class _LudoBgPainter extends CustomPainter {
  const _LudoBgPainter();

  static const _base = Color(0xFF1C4CAC);
  static const _track = Color(0xFF2A5EC2);
  static const _lane = Color(0xFF3369CB);
  static const _line = Color(0xFF1A44A0);
  static const _yard = Color(0xFF2B61C4);
  static const _yardInner = Color(0xFF2558BB);
  static const _socket = Color(0xFF17409A);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = _base);

    final u = size.height * 0.06; // one cell of the giant boards
    final period = 15 * u;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-pi / 4);
    final reach = sqrt(size.width * size.width + size.height * size.height) / 2 + period;
    final n = (reach / period).ceil();
    for (var i = -n; i <= n; i++) {
      for (var j = -n; j <= n; j++) {
        _board(canvas, Offset(i * period - period / 2, j * period - period / 2), u);
      }
    }
    canvas.restore();

    // Soft light in the middle, darker edges.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.95,
          colors: [Color(0x1AFFFFFF), Color(0x00000000), Color(0x66041030)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
  }

  void _board(Canvas canvas, Offset o, double u) {
    Rect cells(double c, double r, double w, double h) => Rect.fromLTWH(o.dx + c * u, o.dy + r * u, w * u, h * u);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.1
      ..color = _line;

    // The cross-shaped track and the coloured home lanes.
    canvas.drawRect(cells(6, 0, 3, 15), Paint()..color = _track);
    canvas.drawRect(cells(0, 6, 15, 3), Paint()..color = _track);
    final lane = Paint()..color = _lane;
    canvas.drawRect(cells(7, 1, 1, 5), lane);
    canvas.drawRect(cells(7, 9, 1, 5), lane);
    canvas.drawRect(cells(1, 7, 5, 1), lane);
    canvas.drawRect(cells(9, 7, 5, 1), lane);
    for (var k = 0; k <= 15; k++) {
      if (k <= 6 || k >= 9) {
        canvas.drawLine(Offset(o.dx + 6 * u, o.dy + k * u), Offset(o.dx + 9 * u, o.dy + k * u), line);
        canvas.drawLine(Offset(o.dx + k * u, o.dy + 6 * u), Offset(o.dx + k * u, o.dy + 9 * u), line);
      }
    }
    for (final k in [6.0, 7.0, 8.0, 9.0]) {
      canvas.drawLine(Offset(o.dx + k * u, o.dy), Offset(o.dx + k * u, o.dy + 6 * u), line);
      canvas.drawLine(Offset(o.dx + k * u, o.dy + 9 * u), Offset(o.dx + k * u, o.dy + 15 * u), line);
      canvas.drawLine(Offset(o.dx, o.dy + k * u), Offset(o.dx + 6 * u, o.dy + k * u), line);
      canvas.drawLine(Offset(o.dx + 9 * u, o.dy + k * u), Offset(o.dx + 15 * u, o.dy + k * u), line);
    }

    // Centre: four triangles in two shades.
    final c = Offset(o.dx + 7.5 * u, o.dy + 7.5 * u);
    final tl = Offset(o.dx + 6 * u, o.dy + 6 * u), tr = Offset(o.dx + 9 * u, o.dy + 6 * u);
    final br = Offset(o.dx + 9 * u, o.dy + 9 * u), bl = Offset(o.dx + 6 * u, o.dy + 9 * u);
    Path tri(Offset a, Offset b) => Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..close();
    canvas.drawPath(tri(tl, tr), Paint()..color = _lane);
    canvas.drawPath(tri(br, bl), Paint()..color = _lane);
    canvas.drawPath(tri(tr, br), Paint()..color = _yardInner);
    canvas.drawPath(tri(bl, tl), Paint()..color = _yardInner);

    // Yards: big rounded square, an inner panel and four dark sockets.
    for (final corner in const [Offset(0, 0), Offset(9, 0), Offset(0, 9), Offset(9, 9)]) {
      final yard = cells(corner.dx, corner.dy, 6, 6);
      canvas.drawRRect(RRect.fromRectAndRadius(yard.deflate(u * 0.35), Radius.circular(u * 1.1)), Paint()..color = _yard);
      canvas.drawRRect(RRect.fromRectAndRadius(yard.deflate(u * 1.05), Radius.circular(u * 0.7)), Paint()..color = _yardInner);
      for (final s in const [Offset(2, 2), Offset(4, 2), Offset(2, 4), Offset(4, 4)]) {
        canvas.drawCircle(Offset(yard.left + s.dx * u, yard.top + s.dy * u), u * 0.62, Paint()..color = _socket);
      }
    }
  }

  @override
  bool shouldRepaint(_LudoBgPainter old) => false;
}