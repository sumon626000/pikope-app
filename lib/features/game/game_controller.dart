import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/match_bet.dart';
import '../../core/audio_service.dart';
import '../../game/ai/bot_player.dart';
import '../../game/models/match_state.dart';
import '../../game/models/player_state.dart';
import '../../game/models/playing_card.dart';
import '../../game/physics/physics_world.dart';
import '../../game/physics/table_geometry.dart';
import '../../game/physics/vec2.dart';
import '../../game/rules/rules_engine.dart';
import '../online/game_link.dart';
import 'shot_table.dart';

export 'shot_table.dart';

class SeatConfig {
  const SeatConfig({
    required this.name,
    required this.avatar,
    this.isBot = false,
    this.botSkill = 0.6,
    this.cue = 'classic',
  });

  /// Id of the cue this player uses (looks only).
  final String cue;

  final String name;
  final String avatar;
  final bool isBot;
  final double botSkill;
}

class MatchConfig {
  const MatchConfig({required this.seats, this.shotSeconds = 30, this.seed, this.bet = const MatchBet()});

  /// Stake and prize of an online match.
  final MatchBet bet;

  final List<SeatConfig> seats;
  final int shotSeconds;

  /// Fixes all randomness (tests). Null uses a secure source.
  final int? seed;
}

class _Scheduled {
  _Scheduled(this.at, this.run);
  final double at;
  final VoidCallback run;
}

/// Drives one match: owns the authoritative [MatchState], the physics world,
/// the shot clock and the bots. Widgets only read from it and forward input.
///
/// [notifyListeners] fires on state changes (HUD); [frame] ticks every
/// animation frame for the table painter; [clock] carries the shot timer.
class GameController extends ChangeNotifier implements ShotTable {
  GameController(this.config, this.audio, {this.link})
      : _random = config.seed == null ? Random.secure() : Random(config.seed) {
    engine = RulesEngine(random: _random);
    _bot = BotPlayer(_random);
    _newMatch();
    audio.play(Sfx.matchStart, volume: 0.8);
  }

  final MatchConfig config;
  final AudioService audio;

  /// Set for an online match: the server deals, rules and keeps the clock;
  /// this controller mirrors its state and only simulates the physics.
  final GameLink? link;
  bool get online => link != null;
  bool get _myTurnOnline => !online || state.currentIndex == link!.seat;
  final Random _random;
  late final RulesEngine engine;
  late final BotPlayer _bot;

  late MatchState state;
  @override
  final PhysicsWorld world = PhysicsWorld();

  @override
  final ValueNotifier<int> frame = ValueNotifier(0);
  final ValueNotifier<double> clock = ValueNotifier(0);

  // --- break draw
  List<PlayingCard?> breakSpread = [];
  bool breakRevealed = false;

  // --- dealing animation
  bool dealing = false;
  int dealtCards = 0;

  // --- aiming
  @override
  double aimAngle = 0;
  @override
  double power = 0;
  @override
  Vec2 spin = Vec2.zero;

  // --- presentation
  GameBanner? banner;
  int bannerId = 0;
  final Set<HandCard> raisedCards = {};
  @override
  final List<SinkingBall> sinking = [];

  /// Seconds since the controller started, for render-side animation.
  @override
  double get time => _time;
  bool presenting = false;

  /// Pass & play: the device must change hands before the turn starts.
  bool handoffPending = false;
  int viewerIndex = 0;

  double _time = 0;
  double _accumulator = 0;
  final List<_Scheduled> _schedule = [];
  final List<GameBanner> _bannerQueue = [];
  double _bannerUntil = 0;
  int _lastTick = -1;
  bool _disposed = false;

  // --- bot animation
  BotPlan? _plan;
  double? _botAimFrom;
  double _botAimTo = 0;
  double _botAimStart = 0;
  double _botPower = 0;
  static const _botAimSeconds = 0.9;
  static const _botStrokeSeconds = 0.45;

  // ------------------------------------------------------------ derived

  List<PlayerState> get players => state.players;
  PlayerState get current => state.current;
  bool get orderKnown => state.turnOrder.isNotEmpty;
  int get humanCount => players.where((p) => !p.isBot).length;

  /// Seat slot of player [index] as seen by the viewer:
  /// 0 bottom, 1 left, 2 top, 3 right (clockwise in turn order).
  int slotOf(int index) {
    if (!orderKnown) return (index - viewerIndex) % 4;
    return (state.turnOrder.indexOf(index) - state.turnOrder.indexOf(viewerIndex)) % 4;
  }

  int playerAtSlot(int slot) => [for (var i = 0; i < 4; i++) i].firstWhere((i) => slotOf(i) == slot);

  /// The table is drawn turned 180 degrees for viewers sitting on its far side.
  @override
  bool get viewRotated => orderKnown && state.turnOrder.indexOf(viewerIndex) >= 2;

  bool get isHumanTurn =>
      !current.isBot &&
      !dealing &&
      !presenting &&
      !handoffPending &&
      _myTurnOnline &&
      (state.phase == GamePhase.playerTurn || state.phase == GamePhase.declarePhase);

  bool get canAim => isHumanTurn && state.phase == GamePhase.playerTurn;
  @override
  bool get canShoot => canAim && engine.canShoot(state);
  @override
  bool get canPlaceCue => canAim && state.ballInHand;
  bool get canDeclare => isHumanTurn && state.phase == GamePhase.declarePhase;

  @override
  bool get showAimGuide =>
      state.phase == GamePhase.playerTurn && !dealing && !presenting && !handoffPending && _myTurnOnline;

  @override
  bool get showBallInHand => state.ballInHand && !current.isBot && _myTurnOnline;

  @override
  Set<int> get highlightBalls =>
      showAimGuide && !current.isBot && viewerIndex == state.currentIndex
          ? current.pendingBalls
          : const {};

  @override
  int? get targetBall => state.phase == GamePhase.playerTurn ? state.targetBall : null;

  @override
  int? get calledPocket => null;

  @override
  bool isWrongContact(int ball) =>
      !state.isBreakShot && state.targetBall != null && ball != state.targetBall;

  @override
  bool tapPocket(int index) => false;

  int? get breakPicker {
    if (state.phase != GamePhase.determiningBreak || breakRevealed) return null;
    // Online: nothing can be picked until the server has said where the match
    // stands (it may be well past the break when rejoining).
    if (online) return _remote != null && players[link!.seat].breakCard == null ? link!.seat : null;
    for (var i = 0; i < players.length; i++) {
      if (!players[i].isBot && players[i].breakCard == null) return i;
    }
    return null;
  }

  String get statusText {
    final name = current.name;
    switch (state.phase) {
      case GamePhase.loading:
        return 'LOADING';
      case GamePhase.determiningBreak:
        final picker = breakPicker;
        if (picker != null) return '${players[picker].name}: PICK A CARD FOR THE BREAK';
        return 'HIGHEST CARD BREAKS FIRST';
      case GamePhase.dealing:
        return 'BREAK ORDER SET';
      case GamePhase.gameOver:
        return '${players[state.winner!].name} WINS';
      case GamePhase.declarePhase:
        if (presenting) return 'NEXT: $name';
        return current.isBot || !_myTurnOnline ? '$name IS DECLARING' : '$name: DECLARE WINNER!';
      case GamePhase.shooting:
      case GamePhase.resolvingShot:
        return '$name SHOOTS';
      case GamePhase.playerTurn:
        if (dealing) return 'DEALING 7 CARDS EACH';
        if (presenting) return 'NEXT: $name';
        if (current.isBot || !_myTurnOnline) return '$name IS AIMING';
        if (state.isBreakShot) return '$name: BREAK! AIM, THEN PULL THE POWER BAR DOWN';
        if (state.targetBall == null) return '$name: TAP ONE OF YOUR CARDS OR BALLS';
        final extra = state.extraShots > 0 ? ' (+${state.extraShots} EXTRA)' : '';
        return '$name: HIT BALL ${state.targetBall} FIRST$extra - PULL THE POWER BAR';
    }
  }

  // -------------------------------------------------------------- setup

  void _newMatch() {
    state = MatchState(players: [
      for (var i = 0; i < config.seats.length; i++)
        PlayerState(
          id: 'p$i',
          name: config.seats[i].name,
          avatar: config.seats[i].avatar,
          isBot: config.seats[i].isBot,
          botSkill: config.seats[i].botSkill,
        ),
    ]);
    viewerIndex = max(0, state.players.indexWhere((p) => !p.isBot));
    _schedule.clear();
    _plan = null;
    _botAimFrom = null;
    _bannerQueue.clear();
    banner = null;
    raisedCards.clear();
    sinking.clear();
    presenting = false;
    handoffPending = false;
    dealing = false;
    dealtCards = 0;
    breakRevealed = false;
    power = 0;
    spin = Vec2.zero;
    for (final b in world.balls) {
      b.pocketed = true;
    }
    engine.startBreakDraw(state);
    if (online) {
      // The server holds the real spread; these are face-down stand-ins.
      viewerIndex = link!.seat;
      breakSpread = List<PlayingCard?>.filled(RulesEngine.breakSpreadSize, _unknownCard);
      return;
    }
    breakSpread = List<PlayingCard?>.of(engine.newBreakSpread());
    var delay = 0.9;
    for (var i = 0; i < players.length; i++) {
      if (!players[i].isBot) continue;
      final index = i;
      _after(delay, () => _botPickBreakCard(index));
      delay += 0.55;
    }
  }

  void rematch() {
    if (online) return; // a new online match starts from the lobby
    _newMatch();
    audio.play(Sfx.matchStart, volume: 0.8);
    notifyListeners();
  }

  // --------------------------------------------------------- break draw

  void pickBreakCard(int spreadIndex) {
    final picker = breakPicker;
    if (picker == null) return;
    if (online) {
      link!.send({'type': 'pick_break', 'index': spreadIndex});
      return;
    }
    _takeBreakCard(picker, spreadIndex);
  }

  void _botPickBreakCard(int player) {
    final free = [
      for (var i = 0; i < breakSpread.length; i++)
        if (breakSpread[i] != null) i
    ];
    _takeBreakCard(player, free[_random.nextInt(free.length)]);
  }

  void _takeBreakCard(int player, int spreadIndex) {
    final card = breakSpread[spreadIndex];
    if (card == null || players[player].breakCard != null) return;
    if (state.phase != GamePhase.determiningBreak) return;
    players[player].breakCard = card;
    breakSpread[spreadIndex] = null;
    audio.play(Sfx.card);
    if (players.every((p) => p.breakCard != null)) {
      _after(0.7, () {
        breakRevealed = true;
        engine.determineBreak(state);
        audio.play(Sfx.success);
        final first = players[state.turnOrder.first];
        _showBanner(GameBanner(
            ['${first.name} BREAKS FIRST', 'WITH ${first.breakCard!.spokenName}'], BannerTone.gold,
            seconds: 2.2));
        notifyListeners();
        _after(2.6, _deal);
      });
    }
    notifyListeners();
  }

  void _deal() {
    engine.deal(state);
    world.rack(_random);
    _animateDeal(_beginTurn);
  }

  void _animateDeal(VoidCallback done) {
    aimAngle = 0;
    dealing = true;
    dealtCards = 0;
    final total = players.length * RulesEngine.cardsPerPlayer;
    for (var i = 1; i <= total; i++) {
      _after(0.07 * i, () {
        dealtCards = i;
        if (i.isOdd) audio.play(Sfx.card, volume: 0.6);
        notifyListeners();
      });
    }
    _after(0.07 * total + 0.6, () {
      dealing = false;
      done();
    });
    notifyListeners();
  }

  // --------------------------------------------------------------- turn

  void _beginTurn() {
    presenting = false;
    power = 0;
    spin = Vec2.zero;
    _botAimFrom = null;
    _plan = null;
    clock.value = config.shotSeconds.toDouble();
    _lastTick = -1;
    if (state.phase == GamePhase.gameOver) {
      notifyListeners();
      return;
    }
    if (online) {
      _stage = _NetStage.idle;
      if (!world.cue.pocketed) _aimAtDefault();
      if (!_myTurnOnline) power = 0;
      _remoteAim = null;
      if (_myTurnOnline) audio.play(Sfx.turn, volume: 0.5);
      notifyListeners();
      _pump(); // anything that arrived while the last result was shown
      return;
    }
    final index = state.currentIndex;
    final p = current;
    if (!p.isBot) {
      if (humanCount > 1 && viewerIndex != index) handoffPending = true;
      viewerIndex = index;
    }
    if (!world.cue.pocketed) _aimAtDefault();
    audio.play(Sfx.turn, volume: 0.5);
    if (p.isBot) {
      if (state.phase == GamePhase.declarePhase) {
        _after(1.6, () => declareWinner());
      } else {
        _after(0.9, _botPlan);
      }
    }
    notifyListeners();
  }

  void _aimAtDefault() {
    final target = state.targetBall;
    final to = target != null && !world.balls[target].pocketed
        ? world.balls[target].pos
        : TableGeometry.footSpot;
    final d = to - world.cue.pos;
    if (d.length > 1) aimAngle = d.angle;
  }

  void confirmHandoff() {
    handoffPending = false;
    clock.value = config.shotSeconds.toDouble();
    notifyListeners();
  }

  // -------------------------------------------------------- human input

  void selectCard(HandCard card) {
    if (!canAim || state.isBreakShot) return;
    if (engine.selectCard(state, card)) {
      link?.send({'type': 'select_card', 'cardId': card.card.id});
      audio.play(Sfx.card);
      _aimAtDefault();
      notifyListeners();
    }
  }

  /// Tapping a ball on the table: if it is one of the player's pending balls
  /// (or a free ball) this reveals a matching card for it. Returns whether
  /// the ball became the target.
  @override
  bool selectBall(int ball) {
    if (!canAim || state.isBreakShot) return false;
    if (RulesEngine.freeBalls.contains(ball)) {
      selectFreeBall(ball);
      return state.selectedFreeBall == ball;
    }
    for (final card in current.hand) {
      if (card.card.ball == ball && !card.completed && engine.selectCard(state, card)) {
        link?.send({'type': 'select_card', 'cardId': card.card.id});
        audio.play(Sfx.card);
        _aimAtDefault();
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void selectFreeBall(int ball) {
    if (!canAim || state.isBreakShot) return;
    if (engine.selectFreeBall(state, ball)) {
      link?.send({'type': 'select_free', 'ball': ball});
      audio.play(Sfx.card);
      _aimAtDefault();
      notifyListeners();
    }
  }

  @override
  void aimAt(Vec2 worldPoint) {
    if (!canAim) return;
    final d = worldPoint - world.cue.pos;
    if (d.length < 4) return;
    aimAngle = d.angle;
  }

  @override
  void nudgeAim(double radians) {
    if (canAim) aimAngle += radians;
  }

  @override
  void moveCue(Vec2 worldPoint) {
    if (!canPlaceCue) return;
    world.placeCue(worldPoint, behindHeadString: state.isBreakShot);
  }

  @override
  void setPower(double value) {
    if (!canAim) return;
    power = value.clamp(0.0, 1.0);
  }

  @override
  void setSpin(Vec2 value) {
    if (!canAim) return;
    spin = value.length > 1 ? value.normalized : value;
    notifyListeners();
  }

  /// Called when the power bar is released.
  @override
  void releaseShot() {
    if (canShoot && power > 0.04) {
      // A short pull is still a deliberate shot: give it a playable minimum.
      if (power < 0.12) power = 0.12;
      _shoot();
    } else {
      if (canAim && power > 0.04 && !engine.canShoot(state)) {
        _showBanner(const GameBanner(['PICK YOUR BALL FIRST', 'TAP ONE OF YOUR CARDS'], BannerTone.gold, seconds: 1.8));
      }
      power = 0;
    }
  }

  void declareWinner() {
    if (state.phase != GamePhase.declarePhase) return;
    if (online) {
      link!.send({'type': 'declare'});
      return;
    }
    if (engine.declareWinner(state, state.currentIndex)) {
      audio.play(Sfx.win);
      _schedule.clear();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- bot

  void _botPlan() {
    if (state.phase != GamePhase.playerTurn || !current.isBot) return;
    _plan = _bot.startPlan(world, state);
  }

  /// Runs the bot's shot search a few milliseconds at a time so that
  /// thinking never costs a frame.
  void _tickPlan() {
    final plan = _plan;
    if (plan == null) return;
    final watch = Stopwatch()..start();
    while (!plan.done && watch.elapsedMicroseconds < 3000) {
      plan.step();
    }
    if (!plan.done) return;
    _plan = null;
    final shot = plan.result;
    if (shot.cuePos != null && state.ballInHand) {
      world.placeCue(shot.cuePos!, behindHeadString: state.isBreakShot);
    }
    if (shot.card != null) engine.selectCard(state, shot.card!);
    if (shot.freeBall != null) engine.selectFreeBall(state, shot.freeBall!);
    if (!state.isBreakShot) audio.play(Sfx.card);
    _botAimFrom = aimAngle;
    _botAimTo = shot.angle;
    _botAimStart = _time;
    _botPower = shot.power;
    notifyListeners();
  }

  void _tickBot() {
    final from = _botAimFrom;
    if (from == null) return;
    final t = _time - _botAimStart;
    if (t < _botAimSeconds) {
      var delta = (_botAimTo - from) % (2 * pi);
      if (delta > pi) delta -= 2 * pi;
      final k = _easeInOut(t / _botAimSeconds);
      aimAngle = from + delta * k;
    } else if (t < _botAimSeconds + _botStrokeSeconds) {
      aimAngle = _botAimTo;
      power = _botPower * (t - _botAimSeconds) / _botStrokeSeconds;
    } else {
      aimAngle = _botAimTo;
      power = _botPower;
      _botAimFrom = null;
      if (engine.canShoot(state)) _shoot();
    }
  }

  // --------------------------------------------------------------- shot

  void _shoot() {
    // The server simulates the same stroke and is the authority on where the
    // balls end up; this device only animates it.
    final dir = Vec2.fromAngle(aimAngle);
    link?.send({
      'type': 'shoot',
      'dirX': dir.x,
      'dirY': dir.y,
      'power': power,
      'spinX': spin.x,
      'spinY': spin.y,
      'cueX': world.cue.pos.x,
      'cueY': world.cue.pos.y,
    });
    if (online) _stage = _NetStage.animatingOwn;
    state.phase = GamePhase.shooting;
    world.shootDir(dir, power, spinX: spin.x, spinY: spin.y);
    audio.play(Sfx.cueHit, volume: 0.4 + power * 0.6);
    _accumulator = 0;
    power = 0;
    notifyListeners();
  }

  void _finishShot() {
    final outcome = world.outcome;
    if (online) {
      // Own shot or a replay: either way the ruling comes from the server.
      state.phase = GamePhase.resolvingShot;
      presenting = true;
      notifyListeners();
      final replayed = _replaying;
      _replaying = null;
      if (_stage == _NetStage.animatingReplay && replayed != null) {
        _presentEvent(replayed);
      } else {
        _stage = _NetStage.waitingOwn;
        _pump();
      }
      return;
    }
    final shooter = state.currentIndex;
    final result = engine.resolveShot(state, outcome);
    // Every ball can be somebody's objective (now or after a penalty), so
    // pocketed balls always return to the table.
    for (final n in outcome.pocketed) {
      world.respot(n);
    }
    if (outcome.cuePocketed) world.respotCue();
    _presentShot(
      shooter: shooter,
      foul: result.foulType,
      penaltyCount: result.penaltyCards.length,
      nextPlayer: result.nextPlayer,
      completed: result.completedObjectives,
      shown: result.shownCards,
      earnedExtra: result.earnedExtraShots,
      becameReady: result.becameReadyToDeclare,
      turnContinues: result.turnContinues,
      wasBreak: result.wasBreak,
    );
  }

  /// Banners, sounds and raised cards for a ruled shot, then the next turn.
  void _presentShot({
    required int shooter,
    required FoulType foul,
    required int penaltyCount,
    required int nextPlayer,
    required List<int> completed,
    required List<PlayingCard> shown,
    required int earnedExtra,
    required bool becameReady,
    required bool turnContinues,
    required bool wasBreak,
  }) {
    final name = players[shooter].name;
    presenting = true;
    power = 0;
    var hold = 1.5;
    if (foul == FoulType.timeout) {
      audio.play(Sfx.foul);
      _showBanner(GameBanner([
        'TIME OUT',
        if (penaltyCount > 0) '+1 PENALTY CARD',
        'NEXT: ${players[nextPlayer].name}',
      ], BannerTone.bad, seconds: 2.4));
      hold = 2.6;
    } else if (foul != FoulType.none) {
      audio.play(Sfx.foul);
      _showBanner(GameBanner([
        foul.label,
        if (penaltyCount > 0) '+$penaltyCount PENALTY CARD${penaltyCount > 1 ? 'S' : ''}',
        if (foul == FoulType.scratch) 'BALL IN HAND',
        'TURN ENDED - NEXT: ${players[nextPlayer].name}',
      ], BannerTone.bad, seconds: 2.6));
      hold = 2.8;
    } else {
      if (completed.isNotEmpty) {
        audio.play(Sfx.success);
        for (final c in players[shooter].hand) {
          if (!c.hidden && shown.contains(c.card)) raisedCards.add(c);
        }
        _showBanner(GameBanner([
          'BALL ${completed.join(' & ')} POCKETED',
          '$name SHOWS ${shown.map((c) => c.spokenName).join(', ')}',
        ], BannerTone.good, seconds: 1.8));
        _after(2.4, () {
          raisedCards.clear();
          notifyListeners();
        });
        hold = 2.0;
      }
      if (earnedExtra > 0) {
        audio.play(Sfx.extra);
        _showBanner(GameBanner(['+$earnedExtra EXTRA SHOT', 'FREE BALL POCKETED'], BannerTone.gold,
            seconds: 1.8));
        hold = max(hold, 2.0);
      }
      if (becameReady) {
        _showBanner(GameBanner(
            ['$name: ALL BALLS DONE', 'DECLARE WINNER ON YOUR NEXT TURN'], BannerTone.gold,
            seconds: 2.6));
        hold += 2.6;
      } else if (!turnContinues && completed.isEmpty) {
        _showBanner(GameBanner([wasBreak ? 'BREAK' : 'MISS', 'NEXT: ${players[nextPlayer].name}'],
            BannerTone.info,
            seconds: 1.3));
      }
    }
    _after(hold, _beginTurn);
    notifyListeners();
  }

  void _timeout() {
    final result = engine.applyTimeout(state);
    _botAimFrom = null;
    _plan = null;
    _presentShot(
      shooter: result.playerIndex,
      foul: FoulType.timeout,
      penaltyCount: result.penaltyCards.length,
      nextPlayer: result.nextPlayer,
      completed: const [],
      shown: const [],
      earnedExtra: 0,
      becameReady: false,
      turnContinues: false,
      wasBreak: false,
    );
  }

  // ------------------------------------------------------------- online

  static const _unknownCard = PlayingCard(1, Suit.clubs);

  Map<String, dynamic>? _remote;
  int _serverOffsetMs = 0;
  bool _introStarted = false;
  bool _introDone = false;
  bool _overAnnounced = false;

  /// Rulings not shown yet, oldest first. Each is a full server snapshot;
  /// they are played back one at a time so a slow device never skips a shot.
  final List<Map<String, dynamic>> _events = [];
  int _lastQueuedResult = 0;
  static const _skipped = 'skippedRulings';
  _NetStage _stage = _NetStage.idle;
  Map<String, dynamic>? _replaying;

  /// Newest view of the match from the server (a poll or an action's reply).
  void applyRemote(Map<String, dynamic> v, int serverNow) {
    if (_disposed || !online) return;
    _serverOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
    _remote = v;
    if (_introStarted) {
      if (_introDone) {
        _queueIfNew(v);
        _pump();
      }
      return;
    }
    // Break draw: picks stay face down until everybody has one.
    final spread = (v['breakSpread'] as List).cast<bool>();
    for (var i = 0; i < breakSpread.length && i < spread.length; i++) {
      breakSpread[i] = spread[i] ? _unknownCard : null;
    }
    final ps = (v['players'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < players.length; i++) {
      if (ps[i]['picked'] == true && players[i].breakCard == null) {
        players[i].breakCard = _unknownCard;
        audio.play(Sfx.card);
      }
    }
    final order = (v['turnOrder'] as List).cast<int>();
    if (order.isNotEmpty) {
      _introStarted = true;
      for (var i = 0; i < players.length; i++) {
        players[i].breakCard = PlayingCard.fromId(ps[i]['breakCard'] as int);
      }
      state
        ..turnOrder = order
        ..turnPos = 0
        ..phase = GamePhase.dealing;
      breakRevealed = true;
      audio.play(Sfx.success);
      final first = players[order.first];
      _showBanner(GameBanner(
          ['${first.name} BREAKS FIRST', 'WITH ${first.breakCard!.spokenName}'], BannerTone.gold,
          seconds: 2.2));
      _after(2.6, _remoteDeal);
    }
    notifyListeners();
  }

  void _remoteDeal() {
    final v = _remote!;
    _applyRemoteState(v);
    world.rackLayout(const [1, 2, 3, 4, 5], (v['rackOrder'] as List).cast<int>());
    _setBalls(v['balls']);
    _animateDeal(() {
      // Joining late (reconnect): take the table as it stands now.
      final now = _remote!;
      _lastQueuedResult = (now['lastResult'] as Map?)?['seq'] as int? ?? 0;
      _setBalls(now['balls']);
      _introDone = true;
      _beginTurn();
    });
  }

  @override
  String get cueId => config.seats[state.currentIndex.clamp(0, config.seats.length - 1)].cue;

  // ------------------------------------------------- opponent's cue (online)

  @override
  bool get showRemoteCue =>
      _previewing ||
      (online && !_myTurnOnline && state.phase == GamePhase.playerTurn && !dealing && !presenting && _stage == _NetStage.idle && _events.isEmpty);

  bool _previewing = false;
  double _previewLeft = 0;
  Vec2? _previewDir;
  double _previewPower = 0;
  double _previewSpinX = 0;
  double _previewSpinY = 0;
  static const _previewHold = 1.05;

  double? _remoteAim;
  double _aimShareIn = 0;
  String _aimShared = '';

  /// Another player's cue, as relayed by the server.
  void applyRemoteAim(Map<String, dynamic> m) {
    if (_disposed || _previewing || !showRemoteCue || m['s'] != state.currentIndex) return;
    final a = (m['a'] as num?)?.toDouble(), p = (m['p'] as num?)?.toDouble();
    final x = (m['x'] as num?)?.toDouble(), y = (m['y'] as num?)?.toDouble();
    if (a == null || p == null || !a.isFinite) return;
    _remoteAim = a;
    power = p.clamp(0.0, 1.0);
    // Ball in hand: follow the cue ball as it is being placed.
    if (state.ballInHand && x != null && y != null && !world.isMoving && !world.cue.pocketed) {
      world.cue.pos = Vec2(
        x.clamp(TableGeometry.ballRadius, TableGeometry.width - TableGeometry.ballRadius),
        y.clamp(TableGeometry.ballRadius, TableGeometry.height - TableGeometry.ballRadius),
      );
    }
  }

  void _tickAimSharing(double dt) {
    if (!online || _previewing) return;
    if (showRemoteCue) {
      final target = _remoteAim;
      if (target != null) {
        // Glide to the latest reported angle the short way round.
        final diff = atan2(sin(target - aimAngle), cos(target - aimAngle));
        aimAngle += diff * min(1.0, dt * 14);
      }
      return;
    }
    if (!canAim) return;
    _aimShareIn -= dt;
    if (_aimShareIn > 0) return;
    final cue = world.cue.pos;
    final now = '${aimAngle.toStringAsFixed(3)} ${power.toStringAsFixed(2)} ${cue.x.toStringAsFixed(1)} ${cue.y.toStringAsFixed(1)}';
    if (now == _aimShared) return;
    _aimShared = now;
    _aimShareIn = 0.09;
    link!.sendAim({'a': aimAngle, 'p': power, 'x': cue.x, 'y': cue.y});
  }

  /// Largest distance between where this device's own simulation left a
  /// ball and where the server says it rests (diagnostic; expected 0).
  double replayDrift = 0;

  void _setBalls(Object? balls, {bool measure = false}) {
    if (balls is! List) return;
    for (var i = 0; i < world.balls.length && i < balls.length; i++) {
      final b = balls[i] as List;
      final pos = Vec2((b[0] as num).toDouble(), (b[1] as num).toDouble());
      final gone = b[2] as bool;
      if (measure && !gone && !world.balls[i].pocketed) {
        replayDrift = max(replayDrift, world.balls[i].pos.distanceTo(pos));
      }
      world.balls[i]
        ..pos = pos
        ..vel = Vec2.zero
        ..pocketed = gone;
    }
  }

  void _syncClock(Map<String, dynamic> v) {
    final left = ((v['deadline'] as int) - DateTime.now().millisecondsSinceEpoch - _serverOffsetMs) / 1000;
    clock.value = left.clamp(0.0, config.shotSeconds.toDouble());
  }

  /// Copies the server's rule state into [state]. Card objects are kept
  /// where possible so widgets and animations keep their identity.
  void _applyRemoteState(Map<String, dynamic> v) {
    final ps = (v['players'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      final j = ps[i];
      final old = {for (final c in p.hand) c.key: c};
      final hand = <HandCard>[];
      for (final e in (j['hand'] as List).cast<Map<String, dynamic>>()) {
        final key = e['k'] as int;
        final id = e['id'] as int?;
        var card = old[key];
        if (card == null || (card.hidden && id != null)) {
          card = id == null
              ? HandCard.unknown(key, isPenalty: e['penalty'] as bool)
              : HandCard(PlayingCard.fromId(id), isPenalty: e['penalty'] as bool, key: key);
        }
        card
          ..completed = e['completed'] as bool
          ..revealed = e['revealed'] as bool;
        hand.add(card);
      }
      p.hand
        ..clear()
        ..addAll(hand);
      p.completedBalls
        ..clear()
        ..addAll((j['completedBalls'] as List).cast<int>());
      p
        ..remoteReady = j['ready'] as bool
        ..remotePending = j['pending'] as int?;
      final st = j['stats'] as Map<String, dynamic>;
      p.stats
        ..shots = st['shots'] as int
        ..ballsCompleted = st['ballsCompleted'] as int
        ..fouls = st['fouls'] as int
        ..penaltyCards = st['penaltyCards'] as int
        ..timeouts = st['timeouts'] as int
        ..extraShots = st['extraShots'] as int;
    }
    state
      ..turnOrder = (v['turnOrder'] as List).cast<int>()
      ..turnPos = v['turnPos'] as int
      ..isBreakShot = v['isBreakShot'] as bool
      ..ballInHand = v['ballInHand'] as bool
      ..extraShots = v['extraShots'] as int
      ..shotNumber = v['shotNumber'] as int
      ..winner = v['winner'] as int?
      ..selectedFreeBall = v['selectedFreeBall'] as int?;
    final selected = v['selectedCard'] as int?;
    state.selectedCard = null;
    if (selected != null) {
      for (final c in current.hand) {
        if (!c.hidden && c.card.id == selected) state.selectedCard = c;
      }
    }
    state.phase = switch (v['phase'] as String) {
      'determiningBreak' => GamePhase.determiningBreak,
      'shooting' => GamePhase.shooting,
      'declarePhase' => GamePhase.declarePhase,
      'gameOver' => GamePhase.gameOver,
      _ => GamePhase.playerTurn,
    };
  }

  void _queueIfNew(Map<String, dynamic> v) {
    final seq = (v['lastResult'] as Map?)?['seq'] as int? ?? 0;
    if (seq > _lastQueuedResult) {
      // A ruling missed while the connection was down cannot be replayed:
      // the table here is not the one that stroke was played on.
      _events.add(seq == _lastQueuedResult + 1 ? v : {...v, _skipped: true});
      _lastQueuedResult = seq;
    }
  }

  /// Plays the next thing the server has told us, when the table is free:
  /// an opponent's shot to replay, a ruling to present, or just newer state.
  void _pump() {
    final latest = _remote;
    if (latest == null || !_introDone) return;
    if (_stage == _NetStage.waitingOwn) {
      // Own shot has stopped rolling: its ruling is the next event.
      if (_events.isNotEmpty) _presentEvent(_events.removeAt(0));
      return;
    }
    if (_stage != _NetStage.idle) return;
    if (_events.isEmpty) {
      _applyRemoteState(latest);
      _syncClock(latest);
      _announceIfOver();
      notifyListeners();
      return;
    }
    final e = _events.removeAt(0);
    final shot = e['lastShot'] as Map<String, dynamic>?;
    final result = e['lastResult'] as Map<String, dynamic>;
    final played = result['foulType'] != 'timeout' && shot != null;
    if (!played || shot['by'] == link!.seat || e[_skipped] == true) {
      _presentEvent(e);
      return;
    }
    // Physics is deterministic: replaying the stroke shows the same shot.
    // The rule state is applied only once the balls have stopped.
    final target = shot['target'];
    state
      ..selectedCard = null
      ..selectedFreeBall = null;
    if (target is Map) {
      for (final c in players[shot['by'] as int].hand) {
        if (!c.hidden && c.card.id == target['card']) state.selectedCard = c;
      }
      state.selectedFreeBall = target['freeBall'] as int?;
    }
    world.cue
      ..pos = Vec2((shot['cueX'] as num).toDouble(), (shot['cueY'] as num).toDouble())
      ..pocketed = false;
    final dir = Vec2((shot['dirX'] as num).toDouble(), (shot['dirY'] as num).toDouble());
    _armPreview(
      e,
      dir,
      (shot['power'] as num).toDouble(),
      spinX: (shot['spinX'] as num).toDouble(),
      spinY: (shot['spinY'] as num).toDouble(),
    );
  }

  void _armPreview(Map<String, dynamic> e, Vec2 dir, double strength, {double spinX = 0, double spinY = 0}) {
    aimAngle = dir.angle;
    power = 0.12;
    _previewDir = dir;
    _previewPower = strength;
    _previewSpinX = spinX;
    _previewSpinY = spinY;
    _previewLeft = _previewHold;
    _previewing = true;
    presenting = false;
    _stage = _NetStage.animatingReplay;
    _replaying = e;
    notifyListeners();
  }

  void _tickPreview(double dt) {
    _previewLeft -= dt;
    final t = (1 - _previewLeft / _previewHold).clamp(0.0, 1.0);
    power = t < 0.4 ? 0.12 : _previewPower * ((t - 0.4) / 0.6);
    if (_previewLeft > 0) return;
    _previewing = false;
    final dir = _previewDir ?? Vec2(1, 0);
    final strength = _previewPower;
    state.phase = GamePhase.shooting;
    world.shootDir(dir, strength, spinX: _previewSpinX, spinY: _previewSpinY);
    audio.play(Sfx.cueHit, volume: 0.4 + strength * 0.6);
    _accumulator = 0;
    power = 0;
    notifyListeners();
  }

  /// Shows one ruling: the table and rule state as of that snapshot.
  void _presentEvent(Map<String, dynamic> e) {
    final result = e['lastResult'] as Map<String, dynamic>;
    _stage = _NetStage.presenting;
    _applyRemoteState(e);
    _setBalls(e['balls'], measure: result['foulType'] != 'timeout' && e[_skipped] != true);
    _presentShot(
      shooter: result['playerIndex'] as int,
      foul: FoulType.values.byName(result['foulType'] as String),
      penaltyCount: result['penaltyCount'] as int,
      nextPlayer: result['nextPlayer'] as int,
      completed: (result['completedObjectives'] as List).cast<int>(),
      shown: [for (final id in (result['shownCards'] as List).cast<int>()) PlayingCard.fromId(id)],
      earnedExtra: result['earnedExtraShots'] as int,
      becameReady: result['becameReadyToDeclare'] as bool,
      turnContinues: result['turnContinues'] as bool,
      wasBreak: result['wasBreak'] as bool,
    );
    _announceIfOver();
  }

  /// The server refused an action (the turn had moved on, the cue ball could
  /// not be placed there ...): drop whatever was assumed and show its state.
  void onActionRejected() {
    final v = _remote;
    if (!online || v == null || !_introDone) return;
    _stage = _NetStage.idle;
    _replaying = null;
    _previewing = false;
    presenting = false;
    power = 0;
    _applyRemoteState(v);
    _setBalls(v['balls']);
    _syncClock(v);
    notifyListeners();
  }

  void _announceIfOver() {
    if (state.phase == GamePhase.gameOver && !_overAnnounced) {
      _overAnnounced = true;
      audio.play(Sfx.win);
      _schedule.clear();
      presenting = false;
      notifyListeners();
    }
  }

  // --------------------------------------------------------------- tick

  /// Advances the match by [dt] seconds of real time.
  void tick(double dt) {
    if (_disposed) return;
    dt = min(dt, 0.1);
    _time += dt;
    _tickAimSharing(dt);
    if (_previewing) {
      _tickPreview(dt);
      frame.value++;
      return;
    }

    while (_schedule.isNotEmpty) {
      final due = _schedule.where((s) => s.at <= _time).toList();
      if (due.isEmpty) break;
      due.sort((a, b) => a.at.compareTo(b.at));
      _schedule.remove(due.first);
      due.first.run();
    }

    sinking.removeWhere((b) => _time - b.start > SinkingBall.seconds);

    if (banner != null && _time >= _bannerUntil) {
      banner = null;
      _nextBanner();
      notifyListeners();
    }

    if (state.phase == GamePhase.shooting) {
      _accumulator += dt;
      while (_accumulator >= PhysicsWorld.fixedDt) {
        world.step();
        _accumulator -= PhysicsWorld.fixedDt;
      }
      for (final e in world.events) {
        switch (e.type) {
          case PhysicsEventType.ballHit:
            audio.play(Sfx.ballHit, volume: e.intensity);
          case PhysicsEventType.cushionHit:
            audio.play(Sfx.cushion, volume: e.intensity);
          case PhysicsEventType.pocket:
            audio.play(Sfx.pocket);
            sinking.add(SinkingBall(e.ball, e.at, e.pocket, _time));
        }
      }
      world.events.clear();
      if (!world.isMoving) _finishShot();
    } else if ((state.phase == GamePhase.playerTurn || state.phase == GamePhase.declarePhase) &&
        !dealing &&
        !presenting &&
        !handoffPending) {
      _tickPlan();
      _tickBot();
      if (state.phase != GamePhase.shooting) {
        clock.value = max(0, clock.value - dt);
        final whole = clock.value.ceil();
        if (!current.isBot && whole <= 5 && whole != _lastTick && whole > 0) {
          _lastTick = whole;
          audio.play(Sfx.tick);
        }
        // Online the server keeps the clock; its ruling arrives with a poll.
        if (clock.value <= 0 && !online) _timeout();
      }
    }
    frame.value++;
  }

  // ------------------------------------------------------------ helpers

  void _after(double seconds, VoidCallback run) => _schedule.add(_Scheduled(_time + seconds, run));

  void _showBanner(GameBanner b) {
    _bannerQueue.add(b);
    if (banner == null) _nextBanner();
  }

  void _nextBanner() {
    if (_bannerQueue.isEmpty) return;
    banner = _bannerQueue.removeAt(0);
    bannerId++;
    _bannerUntil = _time + banner!.seconds;
  }

  @override
  void dispose() {
    _disposed = true;
    frame.dispose();
    clock.dispose();
    super.dispose();
  }
}

double _easeInOut(double t) {
  t = t.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Where an online match is in showing what the server has ruled.
enum _NetStage { idle, animatingOwn, animatingReplay, waitingOwn, presenting }
