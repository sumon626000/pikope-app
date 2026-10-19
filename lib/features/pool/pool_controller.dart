import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/match_bet.dart';
import '../../core/audio_service.dart';
import '../../game/physics/physics_world.dart';
import '../../game/physics/table_geometry.dart';
import '../../game/physics/vec2.dart';
import '../../game/pool/pool_bot.dart';
import '../../game/pool/pool_rules.dart';
import '../game/game_controller.dart' show SeatConfig;
import '../game/shot_table.dart';
import '../online/game_link.dart';

class PoolMatchConfig {
  const PoolMatchConfig({required this.game, required this.seats, this.shotSeconds = 30, this.seed, this.bet = const MatchBet()});

  /// Stake and prize of an online match.
  final MatchBet bet;

  final PoolGame game;
  final List<SeatConfig> seats;
  final int shotSeconds;
  final int? seed;
}

/// Drives one 9-Ball, 8-Ball or 10-Ball match on the shared table widgets.
class PoolController extends ChangeNotifier implements ShotTable {
  PoolController(this.config, this.audio, {this.link})
      : _random = config.seed == null ? Random.secure() : Random(config.seed) {
    rules = PoolRules(random: _random);
    _bot = PoolBot(rules, _random);
    _newMatch();
    audio.play(Sfx.matchStart, volume: 0.8);
  }

  final PoolMatchConfig config;
  final AudioService audio;

  /// Set for an online match: the server rules and keeps the clock.
  final GameLink? link;
  bool get online => link != null;
  bool get _myTurnOnline => !online || state.turn == link!.seat;
  final Random _random;
  late final PoolRules rules;
  late final PoolBot _bot;

  late PoolState state;

  @override
  final PhysicsWorld world = PhysicsWorld();
  @override
  final ValueNotifier<int> frame = ValueNotifier(0);
  final ValueNotifier<double> clock = ValueNotifier(0);

  @override
  double aimAngle = 0;
  @override
  double power = 0;
  @override
  Vec2 spin = Vec2.zero;
  @override
  final List<SinkingBall> sinking = [];

  GameBanner? banner;
  int bannerId = 0;
  bool presenting = true;
  int viewerIndex = 0;

  double _time = 0;
  double _accumulator = 0;
  final List<({double at, VoidCallback run})> _schedule = [];
  final List<GameBanner> _bannerQueue = [];
  double _bannerUntil = 0;
  int _lastTick = -1;
  bool _disposed = false;
  Set<int> _legal = const {};
  Set<int> _onTableBeforeShot = const {};

  PoolBotPlan? _plan;
  double? _botAimFrom;
  double _botAimTo = 0;
  double _botAimStart = 0;
  double _botPower = 0;

  // ------------------------------------------------------------ derived

  List<PoolPlayer> get players => state.players;
  PoolPlayer get current => state.current;
  int get humanCount => players.where((p) => !p.isBot).length;

  Set<int> get onTable =>
      {for (final b in world.balls) if (!b.pocketed && b.number != 0) b.number};

  @override
  double get time => _time;

  /// Player 0 sits at the bottom; a second human sees the table from the far side.
  @override
  bool get viewRotated => viewerIndex == 1;

  bool get isHumanTurn =>
      !current.isBot && !presenting && _myTurnOnline && state.phase == PoolPhase.playerTurn;
  bool get canAim => isHumanTurn;

  @override
  bool get canShoot => canAim && rules.canShoot(state, onTable);

  @override
  bool get canPlaceCue => canAim && state.ballInHand;

  @override
  bool get showAimGuide => state.phase == PoolPhase.playerTurn && !presenting && _myTurnOnline;

  @override
  bool get showBallInHand => state.ballInHand && !current.isBot && _myTurnOnline;

  bool get onEight => rules.onEight(state, onTable);
  bool get needsPocketCall => canAim && onEight && state.calledPocket == null;
  bool get canPushOut => canAim && state.pushOutAvailable;
  bool get choosingPushOut =>
      state.phase == PoolPhase.pushOutChoice && !current.isBot && !presenting && _myTurnOnline;

  @override
  Set<int> get highlightBalls =>
      showAimGuide && !current.isBot && !state.game.isRotation && !state.pushOutDeclared
          ? _legal
          : const {};

  @override
  int? get targetBall {
    if (!showAimGuide || state.pushOutDeclared) return null;
    if (state.game.isRotation || _legal.length == 1) return _legal.isEmpty ? null : _legal.first;
    return null;
  }

  @override
  int? get calledPocket => state.phase == PoolPhase.playerTurn ? state.calledPocket : null;

  @override
  bool isWrongContact(int ball) =>
      !state.isBreakShot && !state.pushOutDeclared && !_legal.contains(ball);

  String get statusText {
    final name = current.name;
    switch (state.phase) {
      case PoolPhase.gameOver:
        return '${players[state.winner!].name} WINS';
      case PoolPhase.shooting:
        return '$name SHOOTS';
      case PoolPhase.pushOutChoice:
        return current.isBot || !_myTurnOnline ? '$name IS DECIDING' : '$name: SHOOT OR PASS IT BACK?';
      case PoolPhase.playerTurn:
        if (presenting) return 'NEXT: $name';
        if (current.isBot || !_myTurnOnline) return '$name IS AIMING';
        if (state.isBreakShot) return '$name: BREAK! AIM, THEN PULL THE POWER BAR DOWN';
        if (state.pushOutDeclared) return '$name: PUSH OUT - PLAY THE CUE BALL ANYWHERE';
        if (needsPocketCall) return '$name: TAP A POCKET TO CALL THE 8-BALL';
        if (state.game.isRotation) return '$name: HIT BALL ${_legal.first} FIRST - PULL THE POWER BAR';
        if (onEight) return '$name: POCKET THE 8 IN THE CALLED POCKET';
        final group = current.group;
        return group == PoolGroup.none
            ? '$name: OPEN TABLE - POCKET ANY SOLID OR STRIPE'
            : '$name: YOU ARE ${group.label} - HIT ONE FIRST';
    }
  }

  // -------------------------------------------------------------- setup

  void _newMatch() {
    state = PoolState(
      game: config.game,
      players: [
        for (final seat in config.seats)
          PoolPlayer(name: seat.name, avatar: seat.avatar, isBot: seat.isBot, botSkill: seat.botSkill),
      ],
      turn: _random.nextInt(2),
    );
    viewerIndex = max(0, players.indexWhere((p) => !p.isBot));
    _schedule.clear();
    _bannerQueue.clear();
    banner = null;
    sinking.clear();
    _plan = null;
    _botAimFrom = null;
    presenting = true;
    power = 0;
    spin = Vec2.zero;
    if (online) {
      // The rack and who breaks come with the first state from the server.
      viewerIndex = link!.seat;
      return;
    }
    rules.rack(state, world);
    aimAngle = 0;
    _showBanner(GameBanner([state.game.title, '${current.name} BREAKS'], BannerTone.gold, seconds: 1.8));
    _after(2.0, _beginTurn);
  }

  void rematch() {
    if (online) return; // a new online match starts from the lobby
    _newMatch();
    audio.play(Sfx.matchStart, volume: 0.8);
    notifyListeners();
  }

  // --------------------------------------------------------------- turn

  void _beginTurn() {
    presenting = false;
    power = 0;
    spin = Vec2.zero;
    _plan = null;
    _botAimFrom = null;
    clock.value = config.shotSeconds.toDouble();
    _lastTick = -1;
    if (state.phase == PoolPhase.gameOver) {
      notifyListeners();
      return;
    }
    if (online) {
      _stage = _NetStage.idle;
      _legal = rules.legalTargets(state, onTable);
      if (!world.cue.pocketed) _aimAtDefault();
      if (!_myTurnOnline) power = 0;
      _remoteAim = null;
      if (_myTurnOnline) audio.play(Sfx.turn, volume: 0.5);
      notifyListeners();
      _pump(); // anything that arrived while the last result was shown
      return;
    }
    _legal = rules.legalTargets(state, onTable);
    if (!current.isBot) viewerIndex = state.turn;
    if (!world.cue.pocketed) _aimAtDefault();
    audio.play(Sfx.turn, volume: 0.5);
    if (current.isBot) {
      if (state.phase == PoolPhase.pushOutChoice) {
        // Bots always take the shot themselves.
        _after(1.0, () => answerPushOut(shoot: true));
      } else {
        _after(0.9, () {
          if (state.phase == PoolPhase.playerTurn && current.isBot) _plan = _bot.startPlan(world, state);
        });
      }
    }
    notifyListeners();
  }

  void _aimAtDefault() {
    final to = _legal.isNotEmpty && !state.isBreakShot
        ? world.balls[_legal.reduce(min)].pos
        : TableGeometry.footSpot;
    final d = to - world.cue.pos;
    if (d.length > 1) aimAngle = d.angle;
  }

  // -------------------------------------------------------- human input

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
    if (canPlaceCue) world.placeCue(worldPoint, behindHeadString: state.behindHeadString);
  }

  /// These games have no card to reveal; a tapped ball is only aimed at.
  @override
  bool selectBall(int ball) => false;

  @override
  bool tapPocket(int index) {
    if (!canAim || !rules.callPocket(state, onTable, index)) return false;
    link?.send({'type': 'call_pocket', 'pocket': index});
    audio.play(Sfx.card);
    notifyListeners();
    return true;
  }

  @override
  void setPower(double value) {
    if (canAim) power = value.clamp(0.0, 1.0);
  }

  @override
  void setSpin(Vec2 value) {
    if (!canAim) return;
    spin = value.length > 1 ? value.normalized : value;
    notifyListeners();
  }

  @override
  void releaseShot() {
    if (canShoot && power > 0.04) {
      if (power < 0.12) power = 0.12;
      _shoot();
    } else {
      if (needsPocketCall && power > 0.04) {
        _showBanner(const GameBanner(['CALL A POCKET FIRST', 'TAP THE POCKET FOR THE 8-BALL'],
            BannerTone.gold,
            seconds: 1.8));
      }
      power = 0;
    }
  }

  void togglePushOut() {
    if (canAim && rules.togglePushOut(state)) {
      link?.send({'type': 'push_out'});
      notifyListeners();
    }
  }

  void answerPushOut({required bool shoot}) {
    if (state.phase != PoolPhase.pushOutChoice) return;
    if (online) {
      link!.send({'type': 'push_out_answer', 'shoot': shoot});
      return;
    }
    rules.answerPushOut(state, shoot: shoot);
    _beginTurn();
  }

  // ---------------------------------------------------------------- bot

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
      world.placeCue(shot.cuePos!, behindHeadString: state.behindHeadString);
    }
    if (shot.calledPocket != null) rules.callPocket(state, onTable, shot.calledPocket!);
    _botAimFrom = aimAngle;
    _botAimTo = shot.angle;
    _botAimStart = _time;
    _botPower = shot.power;
    notifyListeners();
  }

  void _tickBotStroke() {
    final from = _botAimFrom;
    if (from == null) return;
    const aimSeconds = 0.9, strokeSeconds = 0.45;
    final t = _time - _botAimStart;
    if (t < aimSeconds) {
      var delta = (_botAimTo - from) % (2 * pi);
      if (delta > pi) delta -= 2 * pi;
      final k = (t / aimSeconds).clamp(0.0, 1.0);
      aimAngle = from + delta * (k * k * (3 - 2 * k));
    } else if (t < aimSeconds + strokeSeconds) {
      aimAngle = _botAimTo;
      power = _botPower * (t - aimSeconds) / strokeSeconds;
    } else {
      aimAngle = _botAimTo;
      power = _botPower;
      _botAimFrom = null;
      if (rules.canShoot(state, onTable)) _shoot();
    }
  }

  // --------------------------------------------------------------- shot

  void _shoot() {
    _onTableBeforeShot = onTable;
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
    state.phase = PoolPhase.shooting;
    world.shootDir(dir, power, spinX: spin.x, spinY: spin.y);
    audio.play(Sfx.cueHit, volume: 0.4 + power * 0.6);
    _accumulator = 0;
    power = 0;
    notifyListeners();
  }

  void _finishShot() {
    final outcome = world.outcome;
    state.phase = PoolPhase.playerTurn;
    if (online) {
      // Own shot or a replay: either way the ruling comes from the server.
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
    final shooter = players[state.turn].name;
    final r = rules.resolveShot(state, outcome, _onTableBeforeShot);
    for (final n in r.respot) {
      world.respot(n);
    }
    if (outcome.cuePocketed) world.respotCue();
    _present(r, shooter);
  }

  void _timeout() {
    final shooter = current.name;
    _plan = null;
    _botAimFrom = null;
    _present(rules.timeout(state), shooter);
  }

  void _present(PoolShotResult r, String shooter) {
    presenting = true;
    power = 0;
    if (r.winner != null) {
      audio.play(Sfx.win);
      _schedule.clear();
      notifyListeners();
      return;
    }
    final next = players[r.nextPlayer].name;
    var hold = 1.4;
    if (!r.legal) {
      audio.play(Sfx.foul);
      final fouls = players[r.player].consecutiveFouls;
      _showBanner(GameBanner([
        r.foul.label,
        if (r.respot.isNotEmpty) '${r.respot.first}-BALL SPOTTED',
        if (state.game == PoolGame.nineBall && fouls > 1) '$shooter: $fouls FOULS IN A ROW',
        'BALL IN HAND: $next',
      ], BannerTone.bad, seconds: 2.4));
      hold = 2.6;
    } else if (r.wasPushOut) {
      _showBanner(GameBanner(['PUSH OUT', '$next: SHOOT OR PASS IT BACK'], BannerTone.info, seconds: 1.6));
      hold = 1.8;
    } else if (r.groupAssigned != null) {
      audio.play(Sfx.success);
      _showBanner(GameBanner(
          [
            '$shooter IS ${r.groupAssigned!.label}',
            '${players[1 - r.player].name} IS ${r.groupAssigned!.other.label}',
          ],
          BannerTone.gold,
          seconds: 2.0));
      hold = 2.2;
    } else if (r.turnContinues) {
      audio.play(Sfx.success);
      _showBanner(GameBanner(
          ['BALL ${r.pocketed.join(' & ')} POCKETED', '$shooter SHOOTS AGAIN'], BannerTone.good,
          seconds: 1.4));
      hold = 1.6;
    } else {
      _showBanner(GameBanner([r.wasBreak ? 'BREAK' : (r.pocketed.isEmpty ? 'MISS' : 'TURN OVER'), 'NEXT: $next'],
          BannerTone.info,
          seconds: 1.2));
    }
    _after(hold, _beginTurn);
    notifyListeners();
  }

  // --------------------------------------------------------------- tick

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

    if (state.phase == PoolPhase.shooting) {
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
    } else if (!presenting &&
        (state.phase == PoolPhase.playerTurn || state.phase == PoolPhase.pushOutChoice)) {
      _tickPlan();
      _tickBotStroke();
      if (state.phase != PoolPhase.shooting) {
        clock.value = max(0, clock.value - dt);
        final whole = clock.value.ceil();
        if (!current.isBot && whole <= 5 && whole != _lastTick && whole > 0) {
          _lastTick = whole;
          audio.play(Sfx.tick);
        }
        if (clock.value <= 0 && !online) {
          if (state.phase == PoolPhase.pushOutChoice) {
            answerPushOut(shoot: true);
          } else {
            _timeout();
          }
        }
      }
    }
    frame.value++;
  }

  // ------------------------------------------------------------- online

  Map<String, dynamic>? _remote;
  int _serverOffsetMs = 0;
  bool _started = false;
  bool _overAnnounced = false;

  /// Rulings not shown yet, oldest first; played back one at a time so a
  /// slow device never skips a shot.
  final List<Map<String, dynamic>> _events = [];
  int _lastQueuedResult = 0;
  static const _skipped = 'skippedRulings';
  _NetStage _stage = _NetStage.presenting;

  /// Online: false while a stroke is on its way to the server or a ruling is
  /// still being shown, i.e. while this table may differ from the server's.
  bool get inSync => !online || (_stage == _NetStage.idle && _events.isEmpty);
  Map<String, dynamic>? _replaying;

  /// Newest view of the match from the server (a poll or an action's reply).
  void applyRemote(Map<String, dynamic> v, int serverNow) {
    if (_disposed || !online) return;
    _serverOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
    _remote = v;
    if (!_started) {
      _started = true;
      _applyRemoteState(v);
      world.rackLayout((v['rackRows'] as List).cast<int>(), (v['rackOrder'] as List).cast<int>());
      _setBalls(v['balls']);
      _lastQueuedResult = (v['lastResult'] as Map?)?['seq'] as int? ?? 0;
      _showBanner(GameBanner([state.game.title, '${current.name} BREAKS'], BannerTone.gold, seconds: 1.8));
      _after(2.0, _beginTurn);
      notifyListeners();
      return;
    }
    final seq = (v['lastResult'] as Map?)?['seq'] as int? ?? 0;
    if (seq > _lastQueuedResult) {
      // A ruling missed while the connection was down cannot be replayed:
      // the table here is not the one that stroke was played on.
      _events.add(seq == _lastQueuedResult + 1 ? v : {...v, _skipped: true});
      _lastQueuedResult = seq;
    }
    _pump();
  }

  @override
  String get cueId => config.seats[state.turn.clamp(0, config.seats.length - 1)].cue;

  // ------------------------------------------------- opponent's cue (online)

  @override
  bool get showRemoteCue =>
      _previewing ||
      (online && !_myTurnOnline && state.phase == PoolPhase.playerTurn && !presenting && _stage == _NetStage.idle && _events.isEmpty);

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
    if (_disposed || _previewing || !showRemoteCue || m['s'] != state.turn) return;
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

  void _applyRemoteState(Map<String, dynamic> v) {
    final ps = (v['players'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < players.length; i++) {
      players[i]
        ..group = PoolGroup.values.byName(ps[i]['group'] as String)
        ..consecutiveFouls = ps[i]['consecutiveFouls'] as int
        ..shots = ps[i]['shots'] as int
        ..ballsPocketed = ps[i]['ballsPocketed'] as int
        ..fouls = ps[i]['fouls'] as int
        ..missed = ps[i]['missed'] as int? ?? 0;
    }
    state
      ..turn = v['turn'] as int
      ..phase = PoolPhase.values.byName(v['phase'] as String)
      ..isBreakShot = v['isBreakShot'] as bool
      ..ballInHand = v['ballInHand'] as bool
      ..behindHeadString = v['behindHeadString'] as bool
      ..pushOutAvailable = v['pushOutAvailable'] as bool
      ..pushOutDeclared = v['pushOutDeclared'] as bool
      ..calledPocket = v['calledPocket'] as int?
      ..shotNumber = v['shotNumber'] as int
      ..winner = v['winner'] as int?
      ..winReason = v['winReason'] as String?;
  }

  PoolShotResult _resultFrom(Map<String, dynamic> r) => PoolShotResult(
        player: r['player'] as int,
        foul: PoolFoul.values.byName(r['foul'] as String),
        pocketed: (r['pocketed'] as List).cast<int>(),
        respot: (r['respot'] as List).cast<int>(),
        turnContinues: r['turnContinues'] as bool,
        nextPlayer: r['nextPlayer'] as int,
        winner: r['winner'] as int?,
        reason: r['reason'] as String?,
        groupAssigned:
            r['groupAssigned'] == null ? null : PoolGroup.values.byName(r['groupAssigned'] as String),
        wasBreak: r['wasBreak'] as bool,
        wasPushOut: r['wasPushOut'] as bool,
      );

  /// Plays the next thing the server has told us, when the table is free:
  /// an opponent's shot to replay, a ruling to present, or just newer state.
  void _pump() {
    final latest = _remote;
    if (latest == null || !_started) return;
    if (_stage == _NetStage.waitingOwn) {
      // Own shot has stopped rolling: its ruling is the next event.
      if (_events.isNotEmpty) _presentEvent(_events.removeAt(0));
      return;
    }
    if (_stage != _NetStage.idle) return;
    if (_events.isEmpty) {
      final turnBefore = state.turn;
      final phaseBefore = state.phase;
      _applyRemoteState(latest);
      _syncClock(latest);
      _legal = rules.legalTargets(state, onTable);
      if (state.phase == PoolPhase.gameOver && !_overAnnounced) {
        // Ended without a shot (the opponent left).
        _overAnnounced = true;
        audio.play(Sfx.win);
        _schedule.clear();
      } else if (turnBefore != state.turn || phaseBefore != state.phase) {
        if (!world.cue.pocketed && _myTurnOnline) _aimAtDefault();
      }
      notifyListeners();
      return;
    }
    final e = _events.removeAt(0);
    final shot = e['lastShot'] as Map<String, dynamic>?;
    final result = e['lastResult'] as Map<String, dynamic>;
    final played = result['foul'] != 'timeout' && shot != null;
    if (!played || shot['by'] == link!.seat || e[_skipped] == true) {
      _presentEvent(e);
      return;
    }
    // Physics is deterministic: replaying the stroke shows the same shot.
    // The rule state is applied only once the balls have stopped.
    world.cue
      ..pos = Vec2((shot['cueX'] as num).toDouble(), (shot['cueY'] as num).toDouble())
      ..pocketed = false;
    final dir = Vec2((shot['dirX'] as num).toDouble(), (shot['dirY'] as num).toDouble());
    _onTableBeforeShot = onTable;
    _armPreview(
      e,
      dir,
      (shot['power'] as num).toDouble(),
      spinX: (shot['spinX'] as num).toDouble(),
      spinY: (shot['spinY'] as num).toDouble(),
    );
  }

  /// Shows the opponent's cue on the real shot line before the balls move,
  /// so a bot (and a shot that arrived in one poll) is visible.
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
    state.phase = PoolPhase.shooting;
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
    final shooter = players[result['player'] as int].name;
    _applyRemoteState(e);
    _setBalls(e['balls'], measure: result['foul'] != 'timeout' && e[_skipped] != true);
    state.lastResult = _resultFrom(result);
    if (state.phase == PoolPhase.gameOver) _overAnnounced = true;
    _present(state.lastResult!, shooter);
  }

  /// The server refused an action: drop whatever was assumed, show its state.
  void onActionRejected() {
    final v = _remote;
    if (!online || v == null || !_started) return;
    _stage = _NetStage.idle;
    _replaying = null;
    _previewing = false;
    presenting = false;
    power = 0;
    _applyRemoteState(v);
    _setBalls(v['balls']);
    _syncClock(v);
    _legal = rules.legalTargets(state, onTable);
    notifyListeners();
  }

  void _after(double seconds, VoidCallback run) => _schedule.add((at: _time + seconds, run: run));

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

/// Where an online match is in showing what the server has ruled.
enum _NetStage { idle, animatingOwn, animatingReplay, waitingOwn, presenting }
