import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../data/demo_data.dart';
import '../../game/pool/pool_rules.dart';
import '../game/widgets/ball_painter.dart';
import '../game/widgets/hud.dart';
import '../game/widgets/overlays.dart';
import '../game/widgets/table_view.dart';
import '../../data/api_client.dart';
import '../../data/app_game.dart';
import '../misc/how_to_play_screen.dart';
import '../online/game_link.dart';
import '../online/online_screens.dart';
import '../online/session.dart';
import '../../l10n/strings.dart';
import '../duel/match_overlays.dart';
import 'pool_controller.dart';

/// Match screen for 9-Ball, 8-Ball and 10-Ball (two players).
class PoolScreen extends ConsumerStatefulWidget {
  const PoolScreen({super.key, required this.config, this.driver, this.intro = false});

  /// Show the "which game was drawn" reveal first (a match that just started).
  final bool intro;

  final PoolMatchConfig config;

  /// Set for an online match.
  final OnlineGameDriver? driver;

  @override
  ConsumerState<PoolScreen> createState() => _PoolScreenState();
}

class _PoolScreenState extends ConsumerState<PoolScreen> with SingleTickerProviderStateMixin {
  late final PoolController _c;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;
  late bool _intro = widget.intro && widget.config.bet.mode == 'billiard';
  bool _resultBooked = false;
  int? _reward;

  /// Fills the screen below the player bar, like the classic pool games.
  static const _tableRect = Rect.fromLTWH(339, 150, 1272, 744);

  @override
  void initState() {
    super.initState();
    ref.read(audioProvider).playGameplayMusic();
    final driver = widget.driver;
    _c = PoolController(widget.config, ref.read(audioProvider), link: driver)..addListener(_onChanged);
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
      if (!_paused) _c.tick(dt);
    })
      ..start();
  }

  void _onChanged() {
    if (_c.state.phase == PoolPhase.gameOver && !_resultBooked) {
      _resultBooked = true;
      _bookResult();
    }
    if (mounted) setState(() {});
  }

  void _bookResult() {
    final driver = widget.driver;
    final session = ref.read(sessionProvider.notifier);
    if (driver != null) {
      session.refresh().catchError((_) {});
      return;
    }
    if (_c.humanCount != 1) return;
    final won = !_c.players[_c.state.winner!].isBot;
    _reward = null;
    if (ref.read(sessionProvider).signedIn) {
      final game = AppGame.values.firstWhere((g) => g.poolGame == _c.state.game);
      session.reportBotMatch(game, won: won).catchError((_) {});
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
    if (driver != null && _c.state.phase != PoolPhase.gameOver) {
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
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final c = _c;
    final s = c.state;
    final over = s.phase == PoolPhase.gameOver;
    final live = !over && !c.presenting &&
        (s.phase == PoolPhase.playerTurn || s.phase == PoolPhase.shooting || s.phase == PoolPhase.pushOutChoice);

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
              // --- top bar: menu, both players, coins, spin
              Positioned(left: 24, top: 8, child: MenuTile(onTap: () => setState(() => _paused = true))),
              Positioned(
                left: 126,
                top: 28,
                child: Text(s.game.title, style: AppText.label(28, color: AppColors.gold, weight: FontWeight.w900)),
              ),
              Positioned(
                left: 933,
                top: 6,
                child: widget.config.bet.staked
                    ? MatchPrizeTile(prize: widget.config.bet.prize)
                    : CoinsTile(coins: settings.coins, size: 84),
              ),
              Positioned(left: 1836, top: 4, child: SpinControl(controller: c)),
              for (var i = 0; i < 2; i++) ...[
                AnimatedPositioned(
                  key: ValueKey('seat-$i'),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOut,
                  left: _onLeft(i) ? 800 : 1006,
                  top: 6,
                  child: AvatarSeat(
                    name: c.players[i].name,
                    avatar: c.players[i].avatar,
                    isCurrent: live && s.turn == i,
                    isWinner: s.winner == i,
                    clock: c.clock,
                    shotSeconds: c.config.shotSeconds,
                    size: 84,
                    nameSide: NameSide.hidden,
                    turnMisses: widget.driver != null ? c.players[i].missed : null,
                  ),
                ),
                AnimatedPositioned(
                  key: ValueKey('tray-$i'),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOut,
                  left: _onLeft(i) ? 400 : 1140,
                  top: 8,
                  width: 420,
                  child: _PlayerTray(controller: c, index: i, alignEnd: _onLeft(i)),
                ),
              ],
              Positioned(left: 575, top: 98, width: 800, height: 46, child: StatusPill(c.statusText)),
              // --- controls
              Positioned(
                left: 150 - PowerBar.touchPad.left,
                top: 250 - PowerBar.touchPad.top,
                child: PowerBar(controller: c),
              ),
              if (c.canShoot) const Positioned(left: 138, top: 738, child: IgnorePointer(child: ShootHint())),
              // --- table
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
                child: TableView(controller: c, skin: DemoData.skin(settings.tableSkin)),
              ),
              if (s.game.isRotation)
                Positioned(left: 1634, top: 430, width: 296, child: _RackStrip(controller: c)),
              if (c.canPushOut)
                Positioned(
                  left: 1636,
                  top: 250,
                  child: GameButton(
                    label: s.pushOutDeclared ? 'PUSH OUT: ON' : 'PUSH OUT',
                    icon: Icons.open_with_rounded,
                    width: 290,
                    height: 70,
                    fontSize: 20,
                    color: s.pushOutDeclared ? AppColors.gold : AppColors.frame,
                    onPressed: c.togglePushOut,
                  ),
                ),
              if (c.choosingPushOut)
                Positioned.fromRect(
                  rect: _tableRect,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GameButton(
                          label: 'SHOOT',
                          width: 250,
                          height: 84,
                          fontSize: 26,
                          onPressed: () => c.answerPushOut(shoot: true),
                        ),
                        const SizedBox(width: 24),
                        GameButton(
                          label: 'PASS BACK',
                          width: 250,
                          height: 84,
                          fontSize: 26,
                          color: AppColors.gold,
                          onPressed: () => c.answerPushOut(shoot: false),
                        ),
                      ],
                    ),
                  ),
                ),
              if (c.banner != null)
                Positioned.fromRect(
                  rect: _tableRect,
                  child: IgnorePointer(
                    child: Center(child: BannerView(key: ValueKey(c.bannerId), banner: c.banner!)),
                  ),
                ),
              if (_intro)
                GameRevealOverlay(
                  ball: switch (s.game) { PoolGame.eightBall => 8, PoolGame.nineBall => 9, PoolGame.tenBall => 10 },
                  onDone: () => setState(() => _intro = false),
                ),
              if (over && widget.driver != null)
                DuelResultOverlay(
                  players: [
                    for (var i = 0; i < c.players.length; i++)
                      ResultPlayer(
                        name: c.players[i].name,
                        avatar: widget.config.seats[i].avatar,
                        won: i == s.winner,
                        me: i == widget.driver!.seat,
                      ),
                  ],
                  bet: widget.config.bet,
                  reason: s.winReason,
                  onBack: () => Navigator.of(context).pop(),
                )
              else if (over)
                _PoolGameOver(
                  controller: c,
                  reward: _reward,
                  rematchLabel: widget.driver == null ? t.rematch : t.playAgain,
                  onRematch: widget.driver != null
                      ? _playAgain
                      : () {
                          _resultBooked = false;
                          _reward = null;
                          c.rematch();
                        },
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

  /// The viewer's panel is on the left of the bar, the opponent's on the right.
  bool _onLeft(int player) => player == _c.viewerIndex;
}

/// What a player still has to do: their group in 8-ball, their record in the
/// rotation games.
class _PlayerTray extends StatelessWidget {
  const _PlayerTray({required this.controller, required this.index, required this.alignEnd});

  final PoolController controller;
  final int index;

  /// Right-align (the panel left of the avatars).
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = c.players[index];
    final game = c.state.game;
    final onTable = c.onTable;
    final List<Widget> balls;
    final String label;
    if (game == PoolGame.eightBall) {
      final group = p.group;
      if (group == PoolGroup.none) {
        label = 'OPEN TABLE';
        balls = const [];
      } else {
        final mine = [for (var b = 1; b <= 15; b++) if (PoolRules.groupOf(b) == group) b];
        final left = mine.where(onTable.contains).length;
        label = left == 0 ? '${group.label} CLEARED - ON THE 8' : '${group.label}  $left LEFT';
        balls = [
          for (final b in mine) _TrayBall(b, gone: !onTable.contains(b)),
          const SizedBox(width: 10),
          _TrayBall(8, gone: !onTable.contains(8), ring: left == 0),
        ];
      }
    } else {
      label = 'POCKETED ${p.ballsPocketed}   FOULS ${p.fouls}'
          '${game == PoolGame.nineBall ? '   IN A ROW ${p.consecutiveFouls}/3' : ''}';
      balls = const [];
    }
    final side = alignEnd ? Alignment.centerRight : Alignment.centerLeft;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(p.name.toUpperCase(), maxLines: 1, style: AppText.label(19, weight: FontWeight.w900)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: side,
          child: Text(label, style: AppText.label(13, color: AppColors.textDim)),
        ),
        if (balls.isNotEmpty) ...[
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: side,
            child: Row(mainAxisSize: MainAxisSize.min, children: balls),
          ),
        ],
      ],
    );
  }
}

class _TrayBall extends StatelessWidget {
  const _TrayBall(this.number, {required this.gone, this.ring = false});

  final int number;
  final bool gone;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 3),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring ? AppColors.gold : Colors.transparent, width: 3),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          BallIcon(number, size: 32, opacity: gone ? 0.3 : 1),
          if (gone) const Icon(Icons.check_rounded, color: AppColors.active, size: 24),
        ],
      ),
    );
  }
}

/// Rotation games: every ball of the rack, the next one to hit ringed.
class _RackStrip extends ConsumerWidget {
  const _RackStrip({required this.controller});

  final PoolController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final c = controller;
    final game = c.state.game;
    final onTable = c.onTable;
    final lowest = onTable.isEmpty ? null : onTable.reduce((a, b) => a < b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.lowestFirstWins(game.moneyBall), style: AppText.label(13, color: AppColors.textDim)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var b = 1; b <= game.ballCount; b++)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: b == lowest ? AppColors.gold : Colors.transparent, width: 3),
                  ),
                  child: BallIcon(b, size: 40, opacity: onTable.contains(b) ? 1 : 0.25),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Why" line of the result: when the game was lost rather than won, name
/// the player who made the losing mistake.
String _reason(PoolController c) {
  final reason = c.state.winReason ?? '';
  final shooter = c.state.lastResult?.player;
  if (shooter == null || shooter == c.state.winner) return reason;
  return '${c.players[shooter].name.toUpperCase()}: $reason';
}

class _PoolGameOver extends ConsumerWidget {
  const _PoolGameOver({
    required this.controller,
    required this.reward,
    required this.onRematch,
    required this.onHome,
    this.rematchLabel,
  });

  final String? rematchLabel;
  final PoolController controller;
  final int? reward;
  final VoidCallback? onRematch;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final c = controller;
    final gameTitle = switch (c.state.game) {
      PoolGame.eightBall => t.eightBallTitle,
      PoolGame.nineBall => t.nineBallTitle,
      PoolGame.tenBall => t.tenBallTitle,
    };
    final winner = c.players[c.state.winner!];
    Widget cell(String text, {int flex = 10, Color color = AppColors.text, bool left = false}) => Expanded(
          flex: flex,
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: left ? TextAlign.left : TextAlign.center,
              style: AppText.label(18, color: color)),
        );
    return Scrim(
      confetti: true,
      child: OverlayPanel(
        width: 900,
        borderColor: AppColors.gold,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FramedTile(
                  size: 130,
                  frameColor: AppColors.gold,
                  child: AvatarImage(winner.avatar, size: 130),
                ),
                const SizedBox(width: 28),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.emoji_events_rounded, color: AppColors.gold, size: 44),
                        const SizedBox(width: 10),
                        Text(t.winnerGame(gameTitle), style: AppText.label(24, color: AppColors.gold)),
                      ]),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(winner.name.toUpperCase(), style: AppText.label(46, weight: FontWeight.w900)),
                      ),
                      Text(_reason(c), style: AppText.label(17, color: AppColors.textDim)),
                      if (reward != null && reward! > 0) Text('+${formatPicoCoins(reward!)}', style: AppText.label(20, color: AppColors.gold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(children: [
              cell(t.playerCol, flex: 22, color: AppColors.textDim, left: true),
              cell(t.shotsCol, color: AppColors.textDim),
              cell(t.ballsCol, color: AppColors.textDim),
              cell(t.foulsCol, color: AppColors.textDim),
            ]),
            const Divider(color: AppColors.frame, height: 18),
            for (var i = 0; i < 2; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  cell(c.players[i].name.toUpperCase(),
                      flex: 22, left: true, color: i == c.state.winner ? AppColors.gold : AppColors.text),
                  cell('${c.players[i].shots}'),
                  cell('${c.players[i].ballsPocketed}'),
                  cell('${c.players[i].fouls}'),
                ]),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onRematch != null) ...[
                  GameButton(label: rematchLabel ?? t.rematch, icon: Icons.replay_rounded, width: 300, onPressed: onRematch),
                  const SizedBox(width: 24),
                ],
                GameButton(
                  label: t.home,
                  icon: Icons.home_rounded,
                  width: 300,
                  color: AppColors.frame,
                  onPressed: onHome,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
