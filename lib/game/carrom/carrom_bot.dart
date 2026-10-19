import 'dart:math';

import '../physics/vec2.dart';
import 'carrom_physics.dart';
import 'carrom_rules.dart';

class CarromBotShot {
  const CarromBotShot({required this.x, required this.dir, required this.power});

  /// Striker position on the base line.
  final double x;
  final Vec2 dir;
  final double power;
}

class _Option {
  _Option(this.target, this.x, this.dir, this.power, this.quality);

  final int target;
  final double x;
  final Vec2 dir;
  final double power;

  /// Rough promise before test-running (shorter, clearer shots first).
  final double quality;
}

/// A stroke being worked out; each [step] test-runs one option so the UI
/// thread never stalls (backend/src/Game/Bots.php::carrom does the same in
/// one go).
class CarromBotPlan {
  CarromBotPlan._(this._bot, this._world, this._state, this._seat, this._options);

  final CarromBot _bot;
  final CarromWorld _world;
  final CarromState _state;
  final int _seat;
  final List<_Option> _options;

  int _next = 0;
  _Option? _best;
  double _bestScore = double.negativeInfinity;
  CarromBotShot? _result;

  bool get done => _result != null;
  CarromBotShot get result => _result!;

  void step() {
    if (done) return;
    if (_next < _options.length) {
      final o = _options[_next++];
      final score = _bot._score(_world, _state, _seat, o) + o.quality;
      if (score > _bestScore) {
        _bestScore = score;
        _best = o;
      }
    }
    if (_next >= _options.length) _result = _bot._finish(_world, _seat, _best);
  }
}

/// Practice-mode opponent: ghost-disc aims at every own piece (and the queen)
/// for every pocket from a few striker positions, the most promising
/// test-run on a copy of the board.
class CarromBot {
  CarromBot(this.random, {this.skill = 0.6});

  final Random random;

  /// 0..1: how straight the bot shoots.
  final double skill;

  static const _trials = 12;
  static const _strikerXs = [220.0, 313.0, 406.0, 500.0, 593.0, 686.0, 780.0];

  CarromBotShot chooseShot(CarromWorld world, CarromState s, int seat) {
    final plan = startPlan(world, s, seat);
    while (!plan.done) {
      plan.step();
    }
    return plan.result;
  }

  CarromBotPlan startPlan(CarromWorld world, CarromState s, int seat) {
    final colour = s.players[seat].colour;
    final own = CarromRules.onBoard(world, colour);
    final targets = [...own];
    // The queen is worth taking once there is a piece left to cover her with.
    if (CarromRules.queenOnBoard(world) && own.isNotEmpty && s.queenPending != seat) targets.add(CarromWorld.queen);
    final baseY = seat == 0 ? CarromWorld.baseNear : CarromWorld.baseFar;
    final options = <_Option>[];
    for (final t in targets) {
      final tp = Vec2(world.x[t], world.y[t]);
      for (final p in CarromWorld.pockets) {
        final pocket = Vec2(p[0], p[1]);
        final toPocket = pocket - tp;
        if (toPocket.length < 1) continue;
        final ghost = tp - toPocket.normalized * (CarromWorld.strikerR + CarromWorld.pieceR);
        for (final sx in _strikerXs) {
          if (!world.strikerFits(seat, sx)) continue;
          final from = Vec2(sx, baseY);
          final d = ghost - from;
          if (d.length < 1) continue;
          final dir = d.normalized;
          // Must leave the base line towards the board.
          if (seat == 0 ? dir.y > -0.08 : dir.y < 0.08) continue;
          // The cut angle: the striker must arrive roughly along the pocket line.
          final cut = dir.dot(toPocket.normalized);
          if (cut < 0.2) continue;
          final clear = _pathClear(world, from, ghost, {CarromWorld.striker, t});
          final power = (0.25 + d.length / 1600 + toPocket.length / 1800 + (1 - cut) * 0.25).clamp(0.25, 1.0);
          options.add(_Option(t, sx, dir, power, (clear ? 30 : 0) + cut * 20 - toPocket.length / 60 - d.length / 120));
        }
      }
    }
    options.sort((a, b) => b.quality.compareTo(a.quality));
    return CarromBotPlan._(this, world, s, seat, options.take(_trials).toList());
  }

  bool _pathClear(CarromWorld w, Vec2 from, Vec2 to, Set<int> ignore) {
    final seg = to - from;
    final len2 = seg.length2;
    if (len2 == 0) return true;
    for (var i = 0; i < CarromWorld.count; i++) {
      if (w.gone[i] || ignore.contains(i)) continue;
      final p = Vec2(w.x[i], w.y[i]);
      final t = ((p - from).dot(seg) / len2).clamp(0.0, 1.0);
      if ((from + seg * t).distanceTo(p) < CarromWorld.strikerR + CarromWorld.pieceR - 0.5) return false;
    }
    return true;
  }

  double _score(CarromWorld world, CarromState s, int seat, _Option o) {
    final w = world.clone();
    w.placeStriker(seat, o.x);
    w.shoot(o.dir, o.power);
    w.simulate();
    final me = s.players[seat];
    final them = s.players[1 - seat];
    var score = 0.0;
    var own = 0, opp = 0, queen = false;
    for (final d in w.pocketed) {
      final c = CarromWorld.colourOf(d);
      if (c == me.colour) {
        own++;
      } else if (c == them.colour) {
        opp++;
      } else {
        queen = true;
      }
    }
    if (w.strikerPocketed) return -200.0 + own * 10;
    score += own * 100 - opp * 70;
    final queenOwned = me.hasQueen || them.hasQueen;
    if (queen) score += own > 0 ? 80 : (CarromRules.onBoard(w, me.colour).isNotEmpty ? 30 : -40);
    if (s.queenPending == seat && own == 0) score -= 60; // she would come back
    if (me.pocketed + own >= CarromRules.piecesEach && !queenOwned && !queen) score -= 120;
    // Nothing dropped: prefer leaving own pieces nearer the pockets.
    if (own == 0 && !queen) {
      for (final i in CarromRules.onBoard(w, me.colour)) {
        var best = double.infinity;
        for (final p in CarromWorld.pockets) {
          best = min(best, Vec2(w.x[i] - p[0], w.y[i] - p[1]).length);
        }
        score -= best / 200;
      }
    }
    return score;
  }

  CarromBotShot _finish(CarromWorld world, int seat, _Option? best) {
    if (best == null) {
      // Nothing lined up: nudge the nearest piece gently.
      final baseY = seat == 0 ? CarromWorld.baseNear : CarromWorld.baseFar;
      var x = 500.0;
      if (!world.strikerFits(seat, x)) x = 400;
      var target = Vec2(500, 500);
      var bestD = double.infinity;
      for (var i = 1; i < CarromWorld.count; i++) {
        if (world.gone[i]) continue;
        final d = Vec2(world.x[i] - x, world.y[i] - baseY).length;
        if (d < bestD) {
          bestD = d;
          target = Vec2(world.x[i], world.y[i]);
        }
      }
      return CarromBotShot(x: x, dir: (target - Vec2(x, baseY)).normalized, power: 0.45);
    }
    // A hand that shakes a little, less so with skill.
    final noise = (random.nextDouble() * 2 - 1) * 0.05 * (1.3 - skill);
    final a = best.dir.angle + noise;
    return CarromBotShot(x: best.x, dir: Vec2.fromAngle(a), power: (best.power + (random.nextDouble() - 0.5) * 0.08).clamp(0.25, 1.0));
  }
}
