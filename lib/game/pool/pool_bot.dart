import 'dart:math';

import '../physics/physics_world.dart';
import '../physics/table_geometry.dart';
import '../physics/vec2.dart';
import 'pool_rules.dart';

class PoolBotShot {
  const PoolBotShot({required this.angle, required this.power, this.cuePos, this.calledPocket});

  final double angle;
  final double power;
  final Vec2? cuePos;
  final int? calledPocket;
}

class _Option {
  _Option(this.ball, this.pocket, this.angle, this.power, this.quality, this.cuePos);

  final int ball;
  final int pocket;
  final double angle;
  final double power;
  final double quality;
  final Vec2 cuePos;
}

/// A shot being worked out; each [step] test-runs one option.
class PoolBotPlan {
  PoolBotPlan._(this._bot, this._world, this._state, this._onTable, this._options);

  PoolBotPlan._ready(PoolBotShot shot)
      : _bot = null,
        _world = null,
        _state = null,
        _onTable = const {},
        _options = const [],
        _result = shot;

  final PoolBot? _bot;
  final PhysicsWorld? _world;
  final PoolState? _state;
  final Set<int> _onTable;
  final List<_Option> _options;

  int _next = 0;
  _Option? _best;
  double _bestScore = double.negativeInfinity;
  PoolBotShot? _result;

  bool get done => _result != null;
  PoolBotShot get result => _result!;

  void step() {
    if (done) return;
    if (_next < _options.length) {
      final o = _options[_next++];
      final score = _bot!._score(_world!, _state!, _onTable, o) + o.quality * 5;
      if (score > _bestScore) {
        _bestScore = score;
        _best = o;
      }
    }
    if (_next >= _options.length) _result = _bot!._finish(_state!, _onTable, _best);
  }
}

/// Bot for the two-player pool games: ghost-ball options for every legal
/// target, each test-run on a cloned table and scored by the real rules.
class PoolBot {
  PoolBot(this.rules, this.random);

  final PoolRules rules;
  final Random random;
  static const double _r = TableGeometry.ballRadius;

  PoolBotShot chooseShot(PhysicsWorld world, PoolState s) {
    final plan = startPlan(world, s);
    while (!plan.done) {
      plan.step();
    }
    return plan.result;
  }

  PoolBotPlan startPlan(PhysicsWorld world, PoolState s) {
    final onTable = {for (final b in world.balls) if (!b.pocketed && b.number != 0) b.number};
    final noise = (1 - s.current.botSkill) * 0.028;
    if (s.isBreakShot) {
      final cuePos = Vec2(TableGeometry.headSpot.x, 250 + (random.nextDouble() - 0.5) * 50);
      return PoolBotPlan._ready(PoolBotShot(
        angle: (TableGeometry.footSpot - cuePos).angle + _gauss() * noise * 0.3,
        power: 0.9 + random.nextDouble() * 0.1,
        cuePos: cuePos,
      ));
    }
    final options = <_Option>[];
    for (final ball in rules.legalTargets(s, onTable)) {
      options.addAll(_optionsFor(world, s, ball));
    }
    options.sort((a, b) => b.quality.compareTo(a.quality));
    return PoolBotPlan._(this, world.clone(), s, onTable, options.take(10).toList());
  }

  Iterable<_Option> _optionsFor(PhysicsWorld world, PoolState s, int ball) sync* {
    final target = world.balls[ball].pos;
    for (var i = 0; i < TableGeometry.pockets.length; i++) {
      final pocket = TableGeometry.pockets[i];
      final toPocket = (pocket.aim - target).normalized;
      final ghost = target - toPocket * (2 * _r);
      if (!world.pathClear(target, pocket.aim, ignore: {ball, 0})) continue;
      var cuePos = world.cue.pos;
      if (s.ballInHand) {
        Vec2? placed;
        for (final dist in const [260.0, 180.0, 120.0, 340.0]) {
          final p = ghost - toPocket * dist;
          if (world.isFree(p, ignore: 0)) {
            placed = p;
            break;
          }
        }
        if (placed == null) continue;
        cuePos = placed;
      }
      final toGhost = ghost - cuePos;
      final cut = toGhost.normalized.dot(toPocket);
      if (cut < 0.25) continue;
      if (!world.pathClear(cuePos, ghost, ignore: {ball, 0})) continue;
      final travel = toGhost.length + target.distanceTo(pocket.aim);
      final quality = cut - travel / 2500;
      final base = (0.22 + travel / 1900 + (1 - cut) * 0.25).clamp(0.2, 0.9);
      yield _Option(ball, i, toGhost.angle, base, quality, cuePos);
      yield _Option(ball, i, toGhost.angle, (base + 0.2).clamp(0.2, 1.0), quality - 0.05, cuePos);
    }
    // Safety: a plain full hit, so at least the first contact is legal.
    final cuePos = world.cue.pos;
    final direct = target - cuePos;
    final clear = world.pathClear(cuePos, target - direct.normalized * (2 * _r), ignore: {ball, 0});
    yield _Option(ball, 0, direct.angle, 0.4, clear ? -1.0 : -2.0, cuePos);
  }

  /// Scores an option by test-running it three times: as aimed and nudged to
  /// either side by the bot's own aiming error. A line that loses the game
  /// when slightly off (the 8 or cue ball sitting close by) is rejected.
  double _score(PhysicsWorld world, PoolState s, Set<int> onTable, _Option o) {
    final wobble = max(0.004, (1 - s.current.botSkill) * 0.028);
    var total = 0.0;
    var worst = double.infinity;
    for (final offset in [0.0, wobble, -wobble]) {
      final v = _scoreOnce(world, s, onTable, o, o.angle + offset);
      total += offset == 0 ? v * 2 : v;
      worst = min(worst, v);
    }
    return worst <= -1000 ? worst : total / 4;
  }

  double _scoreOnce(PhysicsWorld world, PoolState s, Set<int> onTable, _Option o, double angle) {
    final sim = world.clone();
    sim.cue.pos = o.cuePos;
    sim.shoot(angle, o.power);
    final outcome = sim.simulateToRest();
    final called = s.calledPocket;
    s.calledPocket = o.pocket;
    final r = rules.evaluate(s, outcome, onTable);
    s.calledPocket = called;
    if (r.winner == s.turn) return 1000;
    if (r.winner != null) return -1000;
    if (!r.legal) return -100;
    return r.turnContinues ? 100.0 + r.pocketed.length * 5 : 0;
  }

  PoolBotShot _finish(PoolState s, Set<int> onTable, _Option? best) {
    if (best == null) return PoolBotShot(angle: random.nextDouble() * 2 * pi, power: 0.4);
    final noise = (1 - s.current.botSkill) * 0.028;
    return PoolBotShot(
      angle: best.angle + _gauss() * noise,
      power: (best.power + _gauss() * 0.04).clamp(0.12, 1.0),
      cuePos: s.ballInHand ? best.cuePos : null,
      calledPocket: rules.onEight(s, onTable) ? best.pocket : null,
    );
  }

  double _gauss() {
    final u = max(random.nextDouble(), 1e-9);
    return sqrt(-2 * log(u)) * cos(2 * pi * random.nextDouble());
  }
}
