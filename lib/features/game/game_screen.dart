import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/perf.dart';
import '../../core/widgets.dart';
import '../../data/demo_data.dart';
import '../../game/models/match_state.dart';
import '../../data/api_client.dart';
import '../../data/app_game.dart';
import '../misc/how_to_play_screen.dart';
import '../duel/match_overlays.dart';
import '../online/game_link.dart';
import '../online/online_screens.dart';
import '../online/session.dart';
import 'game_controller.dart';
import 'widgets/hud.dart';
import 'widgets/overlays.dart';
import 'widgets/table_view.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.config, this.driver, this.intro = false});

  /// Spin the jackpot wheel first (a staked match that just started).
  final bool intro;

  final MatchConfig config;

  /// Set for an online match.
  final OnlineGameDriver? driver;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with SingleTickerProviderStateMixin {
  late final GameController _c;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;
  late bool _intro = widget.intro && widget.config.bet.multiplier != null;
  bool _resultBooked = false;
  int? _reward;

  static const _tableRect = SeatLayout.tableRect;

  @override
  void initState() {
    super.initState();
    ref.read(audioProvider).playGameplayMusic();
    final driver = widget.driver;
    _c = GameController(widget.config, ref.read(audioProvider), link: driver)..addListener(_onChanged);
    if (driver != null) {
      driver
        ..onState = _c.applyRemote
        ..onError = _onNetError
        ..onAim = _c.applyRemoteAim
        ..start();
    }
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      final perf = Perf.begin();
      if (!_paused) _c.tick(dt);
      Perf.end('tick', perf);
    })
      ..start();
  }

  void _onChanged() {
    if (_c.state.phase == GamePhase.gameOver && !_resultBooked) {
      _resultBooked = true;
      _bookResult();
    }
    if (mounted) setState(() {});
  }

  /// Online the server has already paid out; offline the result is booked
  /// here (and reported to the server when signed in).
  void _bookResult() {
    final driver = widget.driver;
    final session = ref.read(sessionProvider.notifier);
    if (driver != null) {
      session.refresh().catchError((_) {});
      return;
    }
    // The profile belongs to the single local human; pass & play with
    // several humans has no one account to credit.
    if (_c.humanCount != 1) return;
    final won = !_c.players[_c.state.winner!].isBot;
    _reward = null;
    if (ref.read(sessionProvider).signedIn) {
      session.reportBotMatch(AppGame.poker, won: won).catchError((_) {});
    } else {
      ref.read(settingsProvider.notifier).recordPractice(won: won);
    }
  }

  void _onNetError(ApiException e) {
    // A refused action (someone else was faster, the turn moved on) needs no
    // fuss; a lost connection is shown by the ConnectionStatusLayer.
    if (e.code != 'network') _c.onActionRejected();
  }

  Future<void> _quit() async {
    final driver = widget.driver;
    final navigator = Navigator.of(context);
    if (driver != null && _c.state.phase != GamePhase.gameOver) {
      driver.send({'type': 'leave'});
      await driver.idle;
    }
    navigator.pop();
  }


  /// Online: a fresh room for the same players.
  Future<void> _playAgain() async {
    final driver = widget.driver!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final room = await driver.api.post('/rooms/${driver.roomId}/rematch');
      navigator.pushReplacement(MaterialPageRoute<void>(builder: (_) => RoomScreen(room: room)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _rematch() {
    _resultBooked = false;
    _reward = null;
    _c.rematch();
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.driver?.dispose();
    _c
      ..removeListener(_onChanged)
      ..dispose();
    ref.read(audioProvider).playMenuMusic();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final perf = Perf.begin();
    final tree = _build(context);
    Perf.end('screenBuild', perf);
    return tree;
  }

  Widget _build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final c = _c;
    final phase = c.state.phase;
    final viewer = c.players[c.viewerIndex];
    final inPlay = phase != GamePhase.determiningBreak && phase != GamePhase.dealing;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _paused = !_paused);
      },
      child: Scaffold(
        body: DesignCanvas(
          size: DesignCanvas.tableSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 118,
                top: 14,
                child: widget.config.bet.staked
                    ? MatchPrizeTile(prize: _intro ? 0 : widget.config.bet.prize)
                    : CoinsTile(coins: settings.coins, size: 84),
              ),
              Positioned(
                left: 104 - PowerBar.touchPad.left,
                top: 228 - PowerBar.touchPad.top,
                child: PowerBar(controller: c),
              ),
              if (c.canShoot)
                const Positioned(left: 92, top: 716, child: IgnorePointer(child: ShootHint())),
              Positioned(left: 24, top: 14, child: MenuTile(onTap: () => setState(() => _paused = true))),
              Positioned(left: 1836, top: 14, child: SpinControl(controller: c)),
              Positioned(
                left: 214,
                top: 16,
                width: 440,
                height: 64,
                child: StatusPill(c.statusText),
              ),
              Positioned.fromRect(
                rect: _tableRect.deflate(18),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(40)),
                    boxShadow: [
                      BoxShadow(color: Color(0xCC000000), blurRadius: 50, spreadRadius: 8, offset: Offset(0, 22)),
                      BoxShadow(color: Color(0x22FFFFFF), blurRadius: 70, spreadRadius: 4),
                    ],
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: _tableRect,
                child: TableView(
                  controller: c,
                  skin: DemoData.skin(settings.tableSkin),
                ),
              ),
              for (var i = 0; i < c.players.length; i++)
                AnimatedPositioned(
                  key: ValueKey('seat-$i'),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOut,
                  left: SeatLayout.avatar[c.slotOf(i)].dx - 30,
                  top: SeatLayout.avatar[c.slotOf(i)].dy,
                  child: SeatView(controller: c, playerIndex: i),
                ),
              if (inPlay)
                for (var i = 0; i < c.players.length; i++) ...buildHand(c, i),
              if (inPlay && !c.dealing)
                for (var i = 0; i < c.players.length; i++)
                  if (c.slotOf(i) != 0)
                    Positioned(
                      left: SeatLayout.doneChips[c.slotOf(i)].dx,
                      top: SeatLayout.doneChips[c.slotOf(i)].dy,
                      child: DoneChips(player: c.players[i]),
                    ),
              if (inPlay && !c.dealing && !viewer.isBot && !c.handoffPending)
                Positioned(
                  left: 1160,
                  top: 794,
                  width: 440,
                  child: ObjectivePanel(controller: c, player: viewer),
                ),
              if (phase == GamePhase.determiningBreak) ...buildBreakSpread(c),
              if (!inPlay) ...buildBreakCards(c),
              if (c.canDeclare)
                Positioned.fromRect(
                  rect: _tableRect,
                  child: Center(
                    child: GameButton(
                      label: 'DECLARE WINNER',
                      icon: Icons.emoji_events_rounded,
                      color: AppColors.gold,
                      height: 96,
                      fontSize: 32,
                      onPressed: c.declareWinner,
                    ),
                  ),
                ),
              if (c.banner != null)
                Positioned.fromRect(
                  rect: _tableRect,
                  child: IgnorePointer(
                    child: Center(
                      child: BannerView(key: ValueKey(c.bannerId), banner: c.banner!),
                    ),
                  ),
                ),
              if (c.handoffPending && !_paused) HandoffOverlay(controller: c),
              if (_intro) JackpotWheelOverlay(bet: widget.config.bet, onDone: () => setState(() => _intro = false)),
              if (phase == GamePhase.gameOver && widget.driver != null)
                DuelResultOverlay(
                  players: [
                    for (var i = 0; i < c.players.length; i++)
                      ResultPlayer(
                        name: c.players[i].name,
                        avatar: widget.config.seats[i].avatar,
                        won: i == c.state.winner,
                        me: i == widget.driver!.seat,
                      ),
                  ],
                  bet: widget.config.bet,
                  reason: null,
                  onBack: () => Navigator.of(context).pop(),
                )
              else if (phase == GamePhase.gameOver)
                GameOverOverlay(
                  controller: c,
                  reward: _reward,
                  onRematch: widget.driver == null ? _rematch : _playAgain,
                  rematchLabel: widget.driver == null ? 'REMATCH' : 'PLAY AGAIN',
                  onHome: () => Navigator.of(context).pop(),
                ),
              if (widget.driver != null)
                ConnectionStatusLayer(
                  offline: widget.driver!.offline,
                  // Still seated on the server: the home screen offers to rejoin.
                  onLeave: () => Navigator.of(context).pop(),
                ),
              if (_paused)
                PauseOverlay(
                  soundOn: settings.soundOn,
                  onResume: () => setState(() => _paused = false),
                  onToggleSound: () => ref
                      .read(settingsProvider.notifier)
                      .update((s) => s.copyWith(soundOn: !s.soundOn)),
                  onRules: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen())),
                  onQuit: _quit,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
