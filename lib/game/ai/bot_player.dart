import 'dart:math';

import '../models/match_state.dart';
import '../models/playing_card.dart';
import '../physics/physics_world.dart';
import '../physics/table_geometry.dart';
import '../physics/vec2.dart';
import '../rules/rules_engine.dart';

class BotShot {
  const BotShot({
    required this.angle,
    required this.power,
    this.card,
    this.freeBall,
    this.cuePos,
  });

  final double angle;
  final double power;
  final HandCard? card;
  final int? freeBall;

  /// Where to put the cue ball first when it is in hand.
  final Vec2? cuePos;
}

class _Candidate {
  _Candidate(this.ball, this.angle, this.power, this.quality, this.cuePos);

  final int ball;
  final double angle;
  final double power;
  final double quality;
  final Vec2 cuePos;
}

/// A shot being worked out: one candidate is simulated per [step].
class BotPlan {
  BotPlan._(this._bot, this._world, this._state, this._candidates, this._own);

  BotPlan._ready(BotShot shot)
      : _bot = null,
        _world = null,
        _state = null,
        _candidates = const [],
        _own = const [],
        _result = shot;

  final BotPlayer? _bot;
  final PhysicsWorld? _world;
  final MatchState? _state;
  final List<_Candidate> _candidates;
  final List<int> _own;

  int _next = 0;
  _Candidate? _best;
  double _bestScore = double.negativeInfinity;
  BotShot? _result;

  bool get done => _result != null;
  BotShot get result => _result!;

  void step() {
    if (done) return;
    if (_next < _candidates.length) {
      final c = _candidates[_next++];
      final score = _bot!._simulate(_world!, _state!, c) + c.quality * 5;
      if (score > _bestScore) {
        _bestScore = score;
        _best = c;
      }
    }
    if (_next >= _candidates.length) _result = _bot!._finish(_state!, _best, _own);
  }
}

/// Picks shots by generating ghost-ball candidates and test-running the best
/// ones on a cloned [PhysicsWorld]; skill only controls the aiming error.
class BotPlayer {
  BotPlayer(this.random);

  final Random random;
  static const double _r = TableGeometry.ballRadius;

  /// Plans in one go (tests, headless play).
  BotShot chooseShot(PhysicsWorld world, MatchState s) {
    final plan = startPlan(world, s);
    while (!plan.done) {
      plan.step();
    }
    return plan.result;
  }

  /// Starts planning a shot. Each [BotPlan.step] test-runs one candidate, so
  /// the caller can spread the work over several frames.
  BotPlan startPlan(PhysicsWorld world, MatchState s) {
    final p = s.current;
    if (s.isBreakShot) {
      final noise = (1 - p.botSkill) * 0.028;
      final cuePos = Vec2(TableGeometry.headSpot.x, 250 + (random.nextDouble() - 0.5) * 60);
      final aim = (TableGeometry.footSpot - cuePos).angle;
      return BotPlan._ready(BotShot(
        angle: aim + _gauss() * noise * 0.4,
        power: 0.88 + random.nextDouble() * 0.12,
        cuePos: cuePos,
      ));
    }
    final own = p.pendingBalls.where((b) => !world.balls[b].pocketed).toList();
    final free = RulesEngine.freeBalls.where((b) => !world.balls[b].pocketed).toList();
    final candidates = <_Candidate>[];
    for (final ball in [...own, ...free]) {
      candidates.addAll(_candidatesFor(world, s, ball, isFree: free.contains(ball)));
    }
    candidates.sort((a, b) => b.quality.compareTo(a.quality));
    return BotPlan._(this, world.clone(), s, candidates.take(10).toList(), own);
  }

  BotShot _finish(MatchState s, _Candidate? best, List<int> own) {
    final p = s.current;
    if (best == null) {
      // Nothing to aim at (should not happen while balls are respotted).
      return BotShot(angle: random.nextDouble() * 2 * pi, power: 0.3, freeBall: 14);
    }
    final noise = (1 - p.botSkill) * 0.028;
    return BotShot(
      angle: best.angle + _gauss() * noise,
      power: (best.power + _gauss() * 0.04).clamp(0.12, 1.0),
      card: own.contains(best.ball)
          ? p.hand.firstWhere((c) => c.card.ball == best.ball && !c.completed)
          : null,
      freeBall: own.contains(best.ball) ? null : best.ball,
      cuePos: s.ballInHand ? best.cuePos : null,
    );
  }

  Iterable<_Candidate> _candidatesFor(PhysicsWorld world, MatchState s, int ball,
      {required bool isFree}) sync* {
    final target = world.balls[ball].pos;
    final bias = isFree ? -0.35 : 0.0;
    for (final pocket in TableGeometry.pockets) {
      final toPocket = (pocket.aim - target).normalized;
      final ghost = target - toPocket * (2 * _r);
      if (!world.pathClear(target, pocket.aim, ignore: {ball, 0})) continue;
      var cuePos = world.cue.pos;
      if (s.ballInHand) {
        final placed = _placeBehind(world, ghost, toPocket);
        if (placed == null) continue;
        cuePos = placed;
      }
      final toGhost = ghost - cuePos;
      final cut = toGhost.normalized.dot(toPocket);
      if (cut < 0.25) continue;
      if (!world.pathClear(cuePos, ghost, ignore: {ball, 0})) continue;
      final travel = toGhost.length + target.distanceTo(pocket.aim);
      final quality = cut - travel / 2500 + bias;
      final base = (0.22 + travel / 1900 + (1 - cut) * 0.25).clamp(0.2, 0.9);
      yield _Candidate(ball, toGhost.angle, base, quality, cuePos);
      yield _Candidate(ball, toGhost.angle, (base + 0.2).clamp(0.2, 1.0), quality - 0.05, cuePos);
    }
    // Safety: a plain full hit so the first contact is at least legal.
    if (!isFree) {
      final cuePos = world.cue.pos;
      final direct = target - cuePos;
      final clear = world.pathClear(cuePos, target - direct.normalized * (2 * _r), ignore: {ball, 0});
      yield _Candidate(ball, direct.angle, 0.3, clear ? -1.0 : -2.0, cuePos);
    }
  }

  Vec2? _placeBehind(PhysicsWorld world, Vec2 ghost, Vec2 toPocket) {
    for (final dist in const [260.0, 180.0, 120.0, 340.0]) {
      final p = ghost - toPocket * dist;
      if (world.isFree(p, ignore: 0)) return p;
    }
    return null;
  }

  /// Scores a candidate by test-running it as aimed and nudged to either side
  /// by the bot's own aiming error; a line that fouls when slightly off is
  /// marked down.
  double _simulate(PhysicsWorld world, MatchState s, _Candidate c) {
    final wobble = max(0.004, (1 - s.current.botSkill) * 0.028);
    var total = 0.0;
    var worst = double.infinity;
    for (final offset in [0.0, wobble, -wobble]) {
      final v = _simulateOnce(world, s, c, c.angle + offset);
      total += offset == 0 ? v * 2 : v;
      worst = min(worst, v);
    }
    return worst <= -80 ? (worst + total / 4) / 2 : total / 4;
  }

  double _simulateOnce(PhysicsWorld world, MatchState s, _Candidate c, double angle) {
    final sim = world.clone();
    sim.cue.pos = c.cuePos;
    sim.shoot(angle, c.power);
    final o = sim.simulateToRest();
    final p = s.current;
    var score = 0.0;
    if (o.firstContact != c.ball) score -= 60;
    if (o.cuePocketed) score -= 50;
    for (final b in o.pocketed) {
      if (RulesEngine.freeBalls.contains(b)) {
        score += 30;
      } else if (p.pendingBalls.contains(b)) {
        score += 100;
      } else if (!p.requiredBalls.contains(b)) {
        score -= 90;
      }
    }
    return score;
  }

  double _gauss() {
    final u = max(random.nextDouble(), 1e-9);
    return sqrt(-2 * log(u)) * cos(2 * pi * random.nextDouble());
  }
}
