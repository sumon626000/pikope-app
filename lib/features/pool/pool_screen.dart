import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/audio_service.dart';
import '../../core/app_theme.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/orientation.dart';
import '../../core/widgets.dart';
import '../../data/demo_data.dart';
import '../../game/pool/pool_rules.dart';
import '../duel/cues_screen.dart';
import '../game/widgets/hud.dart';
import '../game/widgets/overlays.dart';
import '../game/widgets/table_view.dart';
import '../../data/api_client.dart';
import '../../data/app_game.dart';
import '../misc/how_to_play_screen.dart';
import '../online/game_link.dart';
import '../online/opponent_presence.dart';
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
  late final AudioService _audio;
  late final PoolController _c;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;
  late bool _intro = widget.intro && widget.config.bet.mode == 'billiard';
  bool _resultBooked = false;
  int? _reward;

  // Quick-chat: the picker panel and the emote currently floating over the
  // viewer's avatar (cleared after a few seconds).
  bool _chatOpen = false;
  String? _emote;
  Timer? _emoteTimer;

  /// Preset quick-chat tokens (emoji or short phrase).
  static const _quickChat = ['👍', '😂', '😮', '🎯', '🔥', '😎', 'Nice shot!', 'Good luck', 'Oops!', 'Well played'];

  void _sendEmote(String e) {
    AudioService.tap();
    _emoteTimer?.cancel();
    setState(() {
      _emote = e;
      _chatOpen = false;
    });
    // Let the opponent see it in an online match; harmless if unsupported.
    widget.driver?.send({'type': 'emote', 'value': e});
    _emoteTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _emote = null);
    });
  }

  static const _canvasW = PortraitGameCanvas.width;
  static const _rightColW = 118.0;
  static const _sidePad = 18.0;
  /// Landscape table art aspect (width / height) before portrait rotate.
  static const _tableAspect = TableProjection.imageWidth / TableProjection.imageHeight;

  @override
  void initState() {
    super.initState();
    _audio = ref.read(audioProvider);
    _audio.playGameplayMusic();
    final driver = widget.driver;
    _c = PoolController(widget.config, _audio, link: driver)..addListener(_onChanged);
    if (driver != null) {
      driver
        ..onState = _c.applyRemote
        ..onPresence = _c.applyPresence
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
    _emoteTimer?.cancel();
    _ticker.dispose();
    widget.driver?.dispose();
    _c
      ..removeListener(_onChanged)
      ..dispose();
    _audio.playMenuMusic();
    super.dispose();
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
        backgroundColor: const Color(0xFF140B2E),
        body: OrientationLock(
          orientation: AppOrientation.portrait,
          child: ColoredBox(
            color: const Color(0xFF140B2E),
            child: PortraitGameCanvas(
              builder: (context, height) => _portraitTable(context, height, settings),
            ),
          ),
        ),
      ),
    );
  }

  /// Portrait stack: top seats + pot + ball slots, rotated table, right rail,
  /// bottom menu + aim ruler. Keeps existing PikoPe table/ball/cue assets.
  Widget _portraitTable(BuildContext context, double height, AppSettings settings) {
    final t = ref.watch(stringsProvider);
    final c = _c;
    final s = c.state;
    final over = s.phase == PoolPhase.gameOver;
    final live = !over &&
        !c.presenting &&
        (s.phase == PoolPhase.playerTurn ||
            s.phase == PoolPhase.shooting ||
            s.phase == PoolPhase.pushOutChoice);

    const topHud = 268.0;
    const bottomBar = 128.0;
    final rightColLeft = _canvasW - _rightColW - _sidePad;
    final tableAreaTop = topHud;
    final tableAreaBottom = height - bottomBar;
    final tableAreaH = (tableAreaBottom - tableAreaTop).clamp(400.0, 2400.0);
    // After 90° rotate, visual width = landscape height, visual height = landscape width.
    var tableVisW = rightColLeft - _sidePad * 2;
    var tableVisH = tableVisW * _tableAspect;
    if (tableVisH > tableAreaH - 16) {
      tableVisH = tableAreaH - 16;
      tableVisW = tableVisH / _tableAspect;
    }
    final tableLeft = _sidePad + ((rightColLeft - _sidePad) - tableVisW) / 2;
    final tableTop = tableAreaTop + (tableAreaH - tableVisH) / 2;

    final me = c.viewerIndex;
    final opp = 1 - me;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ----- Top HUD: two player cards + pot -----
        Positioned(
          left: _sidePad,
          top: 12,
          width: (_canvasW - _sidePad * 2 - 140) / 2,
          child: _PortraitSeatCard(
            name: c.players[me].name,
            avatar: c.players[me].avatar,
            accent: const Color(0xFF2E8BE8),
            active: live && s.turn == me,
            clock: c.clock,
            shotSeconds: c.config.shotSeconds,
            missed: widget.driver != null ? c.players[me].missed : null,
            you: true,
          ),
        ),
        Positioned(
          right: _sidePad,
          top: 12,
          width: (_canvasW - _sidePad * 2 - 140) / 2,
          child: _PortraitSeatCard(
            name: c.players[opp].name,
            avatar: c.players[opp].avatar,
            accent: const Color(0xFF9B5CF0),
            active: live && s.turn == opp,
            clock: c.clock,
            shotSeconds: c.config.shotSeconds,
            missed: widget.driver != null ? c.players[opp].missed : null,
            you: false,
          ),
        ),
        Positioned(
          left: (_canvasW - 120) / 2,
          top: 28,
          width: 120,
          child: IgnorePointer(
            child: widget.config.bet.staked
                ? MatchPrizeTile(prize: widget.config.bet.prize)
                : CoinsTile(coins: settings.coins, size: 100),
          ),
        ),
        // Ball trays under the cards
        Positioned(
          left: _sidePad,
          top: 168,
          width: (_canvasW - _sidePad * 2 - 24) / 2,
          child: IgnorePointer(
            child: _PortraitBallRow(controller: c, index: me, alignEnd: false),
          ),
        ),
        Positioned(
          right: _sidePad,
          top: 168,
          width: (_canvasW - _sidePad * 2 - 24) / 2,
          child: IgnorePointer(
            child: _PortraitBallRow(controller: c, index: opp, alignEnd: true),
          ),
        ),
        Positioned(
          left: _sidePad,
          right: _sidePad + _rightColW + 8,
          top: 228,
          height: 36,
          child: IgnorePointer(
            child: Center(
              child: Text(
                c.statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppText.label(22, color: DesignGameplay.hintActive, weight: FontWeight.w800),
              ),
            ),
          ),
        ),

        // ----- Table (rotated 90° so long axis is vertical) -----
        // TableView uses LayoutBuilder for live size; RotatedBox remaps hits.
        // HUD chrome above/beside uses IgnorePointer so it cannot steal aim/pan.
        Positioned(
          left: tableLeft - 10,
          top: tableTop - 10,
          width: tableVisW + 20,
          height: tableVisH + 20,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(28)),
                boxShadow: [
                  BoxShadow(color: Color(0xCC000000), blurRadius: 28, offset: Offset(0, 14)),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: tableLeft,
          top: tableTop,
          width: tableVisW,
          height: tableVisH,
          child: RotatedBox(
            quarterTurns: 3,
            child: SizedBox(
              // Pre-rotate landscape box: width = visual height, height = visual width.
              width: tableVisH,
              height: tableVisW,
              child: TableView(controller: c, skin: DemoData.skin(settings.tableSkin)),
            ),
          ),
        ),
        if (c.choosingPushOut)
          Positioned(
            left: tableLeft,
            top: tableTop,
            width: tableVisW,
            height: tableVisH,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GameButton(
                    label: 'SHOOT',
                    width: 280,
                    height: 80,
                    fontSize: 28,
                    onPressed: () => c.answerPushOut(shoot: true),
                  ),
                  const SizedBox(height: 16),
                  GameButton(
                    label: 'PASS BACK',
                    width: 280,
                    height: 80,
                    fontSize: 28,
                    color: AppColors.gold,
                    onPressed: () => c.answerPushOut(shoot: false),
                  ),
                ],
              ),
            ),
          ),
        if (c.banner != null)
          Positioned(
            left: tableLeft,
            top: tableTop,
            width: tableVisW,
            height: tableVisH,
            child: IgnorePointer(
              child: Center(child: BannerView(key: ValueKey(c.bannerId), banner: c.banner!)),
            ),
          ),

        // ----- Right control column -----
        Positioned(
          left: rightColLeft,
          top: tableTop,
          width: _rightColW,
          bottom: bottomBar,
          child: Column(
            children: [
              _RailIconButton(
                icon: Icons.close_rounded,
                onTap: () => setState(() => _paused = true),
              ),
              const SizedBox(height: 14),
              _RailIconButton(
                icon: Icons.sports_esports_rounded,
                onTap: () {
                  AudioService.tap();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CuesScreen(ownedOnly: true),
                    ),
                  );
                },
              ),
              // Placeholder: real SpinControl is stacked above so PowerBar
              // overflow / table pans cannot steal its hits.
              const SizedBox(height: 14 + 120 + 14),
              _RailIconButton(
                icon: Icons.chat_bubble_rounded,
                onTap: () => setState(() => _chatOpen = !_chatOpen),
              ),
              if (c.canPushOut) ...[
                const SizedBox(height: 12),
                GameButton(
                  label: s.pushOutDeclared ? 'PUSH' : 'PUSH',
                  width: 100,
                  height: 56,
                  fontSize: 16,
                  color: s.pushOutDeclared ? AppColors.gold : AppColors.frame,
                  onPressed: c.togglePushOut,
                ),
              ],
              const Spacer(),
              SizedBox(
                width: _rightColW,
                height: 420,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  child: PowerBar(controller: c, compact: true),
                ),
              ),
            ],
          ),
        ),
        // Spin dial above the rail (Listener + fat touch pad) so portrait
        // scaling still leaves a usable finger target for English / follow / draw.
        Positioned(
          left: rightColLeft - 10,
          top: tableTop + 78 + 14 + 78,
          width: _rightColW + 20,
          child: Center(
            child: SpinControl(
              controller: c,
              diameter: 108,
              touchPad: const EdgeInsets.all(16),
            ),
          ),
        ),

        // ----- Bottom: menu + aim ruler -----
        Positioned(
          left: _sidePad,
          bottom: 28,
          child: MenuTile(onTap: () => setState(() => _paused = true), size: 78),
        ),
        Positioned(
          left: _sidePad + 100,
          right: _sidePad + _rightColW + 8,
          bottom: 36,
          height: 64,
          child: _AimRuler(onNudge: c.canAim ? c.nudgeAim : null),
        ),
        if (s.game.isRotation)
          Positioned(
            left: _sidePad,
            right: _sidePad + _rightColW + 8,
            bottom: bottomBar + 4,
            child: IgnorePointer(child: _RackStrip(controller: c)),
          ),

        if (_chatOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _chatOpen = false),
            ),
          ),
        if (_chatOpen)
          Positioned(
            left: 120,
            right: _rightColW + 40,
            top: tableTop + 40,
            child: _ChatPanel(items: _quickChat, onPick: _sendEmote),
          ),
        if (_emote != null)
          Positioned(
            left: _sidePad + 40,
            top: 100,
            child: IgnorePointer(child: _EmoteBubble(_emote!)),
          ),

        if (_intro)
          GameRevealOverlay(
            ball: switch (s.game) {
              PoolGame.eightBall => 8,
              PoolGame.nineBall => 9,
              PoolGame.tenBall => 10,
            },
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
            reason: ref.read(stringsProvider).formatMatchWinReason(s.winReason),
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
        if (widget.driver != null) ...[
          OpponentDisconnectBanner(
            presence: _c.opponentPresence,
            serverOffsetMs: _c.serverOffsetMs,
            opponentName: _c.players[1 - widget.driver!.seat].name,
          ),
          ConnectionStatusLayer(
            offline: widget.driver!.offline,
            onLeave: () => Navigator.of(context).pop(),
            scale: 1.35,
          ),
        ],
        if (_paused)
          PauseOverlay(
            scale: 1.55,
            soundOn: settings.soundOn,
            onResume: () => setState(() => _paused = false),
            onToggleSound: () => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(soundOn: !s.soundOn)),
            onRules: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen()),
            ),
            onQuit: _quit,
          ),
      ],
    );
  }
}

class _PortraitSeatCard extends StatelessWidget {
  const _PortraitSeatCard({
    required this.name,
    required this.avatar,
    required this.accent,
    required this.active,
    required this.clock,
    required this.shotSeconds,
    required this.you,
    this.missed,
  });

  final String name;
  final String avatar;
  final Color accent;
  final bool active;
  final ValueNotifier<double> clock;
  final int shotSeconds;
  final bool you;
  final int? missed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3B2C86), Color(0xFF221852)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.9), width: 2.5),
          boxShadow: [
            if (active) BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 14),
            const BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            if (!you) ...[
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppText.label(22, weight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
            ],
            SizedBox(
              width: 72,
              height: 72,
              child: AvatarSeat(
                name: name,
                avatar: avatar,
                isCurrent: active,
                isWinner: false,
                clock: clock,
                shotSeconds: shotSeconds,
                size: 72,
                nameSide: NameSide.hidden,
                turnMisses: missed,
              ),
            ),
            if (you) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(22, weight: FontWeight.w900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact 8-ball group slots (or pocketed count for rotation games).
class _PortraitBallRow extends StatelessWidget {
  const _PortraitBallRow({
    required this.controller,
    required this.index,
    required this.alignEnd,
  });

  final PoolController controller;
  final int index;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = c.players[index];
    final game = c.state.game;
    final onTable = c.onTable;
    final List<Widget> balls;
    if (game == PoolGame.eightBall) {
      final group = p.group;
      if (group == PoolGroup.none) {
        balls = List.generate(
          7,
          (_) => const _TrayBall(0, gone: true, empty: true),
        );
      } else {
        final mine = [
          for (var b = 1; b <= 15; b++)
            if (PoolRules.groupOf(b) == group) b,
        ];
        balls = [for (final b in mine) _TrayBall(b, gone: !onTable.contains(b))];
      }
    } else {
      return Text(
        'POCKETED ${p.ballsPocketed} · FOULS ${p.fouls}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: AppText.label(18, color: AppColors.textDim, weight: FontWeight.w700),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: balls),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5A63D8), Color(0xFF3B3FA8)],
          ),
          border: Border.all(color: const Color(0xFF8E96F0), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 4))],
        ),
        child: Icon(icon, color: Colors.white, size: 38),
      ),
    );
  }
}

/// Fine aim: drag left/right to nudge the cue angle.
class _AimRuler extends StatelessWidget {
  const _AimRuler({required this.onNudge});

  final void Function(double radians)? onNudge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: onNudge == null
          ? null
          : (d) => onNudge!(d.delta.dx * 0.0045),
      child: CustomPaint(
        painter: _AimRulerPainter(enabled: onNudge != null),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AimRulerPainter extends CustomPainter {
  _AimRulerPainter({required this.enabled});

  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(r, Paint()..color = const Color(0xCC1A1240));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = enabled ? const Color(0xFF8E96F0) : const Color(0x668E96F0),
    );
    final midY = size.height / 2;
    final paint = Paint()
      ..color = enabled ? Colors.white70 : Colors.white30
      ..strokeWidth = 2;
    for (var i = 0; i <= 24; i++) {
      final x = size.width * (i / 24);
      final tall = i % 4 == 0;
      canvas.drawLine(
        Offset(x, midY - (tall ? 18 : 10)),
        Offset(x, midY + (tall ? 18 : 10)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AimRulerPainter old) => old.enabled != enabled;
}

class _TrayBall extends StatelessWidget {
  const _TrayBall(
    this.number, {
    required this.gone,
    this.empty = false,
  });

  final int number;
  final bool gone;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: empty ? const Color(0x44221852) : null,
        border: Border.all(
          color: empty ? const Color(0x668E96F0) : Colors.transparent,
          width: 2,
        ),
      ),
      child: empty
          ? null
          : Stack(
              alignment: Alignment.center,
              children: [
                BallIcon(number, size: 32, opacity: gone ? 0.3 : 1),
                if (gone)
                  const Icon(Icons.check_rounded, color: AppColors.active, size: 22),
              ],
            ),
    );
  }
}

bool _isEmoji(String s) => !RegExp(r'[A-Za-z]').hasMatch(s);

/// The emoji / phrase picker that drops from the chat button.
class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.items, required this.onPick});

  final List<String> items;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A1F66), Color(0xFF17123A)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF6E5BD6), width: 2),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (final e in items)
            GestureDetector(
              onTap: () => onPick(e),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: _isEmoji(e) ? 12 : 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B2C86),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6E5BD6)),
                ),
                child: Text(
                  e,
                  style: TextStyle(
                      fontSize: _isEmoji(e) ? 34 : 22, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A speech bubble floating over the viewer's avatar after they quick-chat.
class _EmoteBubble extends StatelessWidget {
  const _EmoteBubble(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final emoji = _isEmoji(text);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (_, t, child) =>
          Transform.scale(scale: t.clamp(0.0, 1.0), alignment: Alignment.topLeft, child: child),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: emoji ? 16 : 22, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: emoji ? 40 : 26, fontWeight: FontWeight.w900, color: const Color(0xFF17123A)),
        ),
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
