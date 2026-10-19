import 'dart:math';

import '../models/match_state.dart';
import 'table_geometry.dart';
import 'vec2.dart';

class Ball {
  Ball(this.number, this.pos);

  /// 0 is the cue ball, 1..15 the object balls.
  final int number;
  Vec2 pos;
  Vec2 vel = Vec2.zero;
  bool pocketed = false;

  /// Distance rolled, used only to animate the ball face.
  double roll = 0;

  bool get isMoving => vel.x != 0 || vel.y != 0;
}

enum PhysicsEventType { ballHit, cushionHit, pocket }

class PhysicsEvent {
  const PhysicsEvent(this.type, this.intensity,
      {this.ball = 0, this.pocket = 0, this.at = Vec2.zero});

  final PhysicsEventType type;

  /// 0..1 loudness hint.
  final double intensity;
  final int ball;
  final int pocket;

  /// Where the ball was when it dropped.
  final Vec2 at;
}

class AimPrediction {
  const AimPrediction({required this.ghost, this.hitBall, this.targetDir, this.cueDir});

  /// Cue-ball centre at the moment of first impact (ball or cushion).
  final Vec2 ghost;
  final int? hitBall;
  final Vec2? targetDir;
  final Vec2? cueDir;
}

/// Deterministic fixed-step pool physics on the [TableGeometry] playfield.
class PhysicsWorld {
  PhysicsWorld() : balls = [for (var i = 0; i <= 15; i++) Ball(i, Vec2.zero)..pocketed = true];

  static const double fixedDt = 1 / 300;
  static const double maxShotSpeed = 2600;
  static const double minShotSpeed = 160;
  // Drag grows with speed, but the constant part is small: a slowing ball
  // keeps creeping for a second or two instead of halting abruptly.
  // backend/src/Game/Physics.php must use the same numbers.
  static const double _slideDecel = 22;
  static const double _dragCoeff = 0.46;
  static const double _restSpeed = 2;
  static const double _ballRestitution = 0.96;
  static const double _cushionRestitution = 0.78;
  static const double _r = TableGeometry.ballRadius;

  final List<Ball> balls;
  final List<PhysicsEvent> events = [];

  int? _firstContact;
  final List<int> _pocketed = [];
  bool _cuePocketed = false;
  bool _railContact = false;
  bool _railAfterContact = false;
  final Set<int> _railBalls = {};
  final Map<int, int> _pocketOf = {};
  double _spinX = 0;
  double _spinY = 0;

  Ball get cue => balls[0];

  bool get isMoving => balls.any((b) => !b.pocketed && b.isMoving);

  PhysicsWorld clone() {
    final w = PhysicsWorld();
    for (var i = 0; i < balls.length; i++) {
      w.balls[i]
        ..pos = balls[i].pos
        ..vel = balls[i].vel
        ..pocketed = balls[i].pocketed;
    }
    return w;
  }

  // ---------------------------------------------------------------- setup

  /// Cue on the head spot, 15 balls racked in a random triangle on the foot spot.
  void rack(Random random) {
    final order = [for (var i = 1; i <= 15; i++) i]..shuffle(random);
    const gap = 0.3;
    final dx = (2 * _r + gap) * sqrt(3) / 2;
    final dy = 2 * _r + gap;
    var k = 0;
    for (var row = 0; row < 5; row++) {
      for (var j = 0; j <= row; j++) {
        balls[order[k++]]
          ..pos = Vec2(TableGeometry.footSpot.x + row * dx,
              TableGeometry.footSpot.y + (j - row / 2) * dy)
          ..vel = Vec2.zero
          ..pocketed = false;
      }
    }
    cue
      ..pos = TableGeometry.headSpot
      ..vel = Vec2.zero
      ..pocketed = false;
    _resetShotFacts();
  }

  /// Racks [rows] of balls (row r holds rows[r] balls) with the apex on the
  /// foot spot; [numbers] fills the rows front to back. Unused balls stay off
  /// the table.
  void rackLayout(List<int> rows, List<int> numbers) {
    for (final b in balls) {
      b
        ..pocketed = true
        ..vel = Vec2.zero;
    }
    const gap = 0.3;
    final dx = (2 * _r + gap) * sqrt(3) / 2;
    final dy = 2 * _r + gap;
    var k = 0;
    for (var row = 0; row < rows.length; row++) {
      for (var j = 0; j < rows[row]; j++) {
        balls[numbers[k++]]
          ..pos = Vec2(TableGeometry.footSpot.x + row * dx,
              TableGeometry.footSpot.y + (j - (rows[row] - 1) / 2) * dy)
          ..pocketed = false;
      }
    }
    cue
      ..pos = TableGeometry.headSpot
      ..vel = Vec2.zero
      ..pocketed = false;
    _resetShotFacts();
  }

  bool isFree(Vec2 p, {int? ignore}) {
    if (!TableGeometry.insidePlayfield(p)) return false;
    for (final b in balls) {
      if (b.pocketed || b.number == ignore) continue;
      if (b.pos.distanceTo(p) < 2 * _r + 0.5) return false;
    }
    return true;
  }

  /// Puts a pocketed ball back: the foot spot, or the nearest free point on
  /// the long string behind (then in front of) it.
  void respot(int number) {
    final b = balls[number];
    Vec2? spot;
    for (var x = TableGeometry.footSpot.x; x <= TableGeometry.width - _r && spot == null; x += 2) {
      final p = Vec2(x, TableGeometry.footSpot.y);
      if (isFree(p, ignore: number)) spot = p;
    }
    for (var x = TableGeometry.footSpot.x; x >= _r && spot == null; x -= 2) {
      final p = Vec2(x, TableGeometry.footSpot.y);
      if (isFree(p, ignore: number)) spot = p;
    }
    b
      ..pos = spot ?? TableGeometry.footSpot
      ..vel = Vec2.zero
      ..pocketed = false;
  }

  /// Returns the cue ball to the table after a scratch (ball in hand).
  void respotCue() {
    Vec2? spot;
    for (var x = TableGeometry.headSpot.x; x >= _r && spot == null; x -= 2) {
      final p = Vec2(x, TableGeometry.headSpot.y);
      if (isFree(p, ignore: 0)) spot = p;
    }
    cue
      ..pos = spot ?? TableGeometry.headSpot
      ..vel = Vec2.zero
      ..pocketed = false;
  }

  /// Moves the cue ball while in hand; refused if the spot is occupied.
  bool placeCue(Vec2 p, {bool behindHeadString = false}) {
    final maxX = behindHeadString ? TableGeometry.headStringX : TableGeometry.width - _r;
    final c = Vec2(p.x.clamp(_r, maxX), p.y.clamp(_r, TableGeometry.height - _r));
    if (!isFree(c, ignore: 0)) return false;
    cue.pos = c;
    return true;
  }

  // ----------------------------------------------------------------- shot

  /// [power] 0..1, [spinX] english (-1 left .. 1 right), [spinY] draw (-1) .. follow (1).
  void shoot(double angle, double power, {double spinX = 0, double spinY = 0}) =>
      shootDir(Vec2.fromAngle(angle), power, spinX: spinX, spinY: spinY);

  /// Same stroke given as a unit direction. Online play sends the direction
  /// rather than the angle so the server starts from exactly the same numbers
  /// (sin and cos can differ in the last bit between platforms).
  void shootDir(Vec2 dir, double power, {double spinX = 0, double spinY = 0}) {
    _resetShotFacts();
    final speed = minShotSpeed + (maxShotSpeed - minShotSpeed) * power.clamp(0.0, 1.0);
    cue.vel = dir * speed;
    _spinX = spinX.clamp(-1.0, 1.0);
    _spinY = spinY.clamp(-1.0, 1.0);
  }

  void _resetShotFacts() {
    _firstContact = null;
    _pocketed.clear();
    _cuePocketed = false;
    _railContact = false;
    _railAfterContact = false;
    _railBalls.clear();
    _pocketOf.clear();
    _spinX = 0;
    _spinY = 0;
    events.clear();
  }

  ShotOutcome get outcome => ShotOutcome(
        firstContact: _firstContact,
        pocketed: List.of(_pocketed),
        cuePocketed: _cuePocketed,
        railContact: _railContact,
        railAfterContact: _railAfterContact,
        objectBallsToRail: _railBalls.length,
        pocketOf: Map.of(_pocketOf),
      );

  /// Runs the shot to rest without rendering (bots, tests).
  ShotOutcome simulateToRest({int maxSteps = 9000}) {
    for (var i = 0; i < maxSteps && isMoving; i++) {
      step();
    }
    for (final b in balls) {
      b.vel = Vec2.zero;
    }
    return outcome;
  }

  void step([double dt = fixedDt]) {
    for (final b in balls) {
      if (b.pocketed || !b.isMoving) continue;
      final speed = b.vel.length;
      final drop = (_slideDecel + _dragCoeff * speed) * dt;
      if (speed <= drop || speed < _restSpeed) {
        b.vel = Vec2.zero;
        continue;
      }
      b.vel = b.vel * ((speed - drop) / speed);
      b.pos = b.pos + b.vel * dt;
      b.roll += speed * dt;
    }
    _collideBalls();
    _collideCushions();
    _checkPockets();
  }

  void _collideBalls() {
    for (var i = 0; i < balls.length; i++) {
      final a = balls[i];
      if (a.pocketed) continue;
      for (var j = i + 1; j < balls.length; j++) {
        final b = balls[j];
        if (b.pocketed || (!a.isMoving && !b.isMoving)) continue;
        final d = b.pos - a.pos;
        final dist2 = d.length2;
        if (dist2 >= 4 * _r * _r || dist2 == 0) continue;
        final dist = sqrt(dist2);
        final n = d * (1 / dist);
        final overlap = 2 * _r - dist;
        a.pos = a.pos - n * (overlap / 2);
        b.pos = b.pos + n * (overlap / 2);
        final rel = (a.vel - b.vel).dot(n);
        if (rel <= 0) continue;
        final cueDir = a.vel.normalized;
        final cueSpeed = a.vel.length;
        final impulse = (1 + _ballRestitution) / 2 * rel;
        a.vel = a.vel - n * impulse;
        b.vel = b.vel + n * impulse;
        if (a.number == 0 && _firstContact == null) {
          _firstContact = b.number;
          // Follow / draw: top spin drives the cue ball on, back spin pulls it back.
          if (cueSpeed > 0) a.vel = a.vel + cueDir * (_spinY * 0.5 * rel);
          _spinY = 0;
        }
        events.add(PhysicsEvent(PhysicsEventType.ballHit, (rel / 1200).clamp(0.05, 1.0)));
      }
    }
  }

  void _collideCushions() {
    for (final b in balls) {
      if (b.pocketed || !b.isMoving) continue;
      for (final c in TableGeometry.cushions) {
        final ab = c.b - c.a;
        final t = ((b.pos - c.a).dot(ab) / ab.length2).clamp(0.0, 1.0);
        final q = c.a + ab * t;
        final d = b.pos - q;
        final dist = d.length;
        if (dist >= _r) continue;
        // On the straight part use the cushion normal; at the jaw tips bounce
        // off the tip itself.
        final n = (t > 0 && t < 1) || dist == 0 ? c.normal : d * (1 / dist);
        final vn = b.vel.dot(n);
        b.pos = q + n * _r;
        if (vn >= 0) continue;
        b.vel = b.vel - n * ((1 + _cushionRestitution) * vn);
        if (b.number == 0 && _spinX != 0) {
          b.vel = b.vel + n.perp * (_spinX * 0.3 * vn.abs());
          _spinX *= 0.4;
        }
        _railContact = true;
        if (_firstContact != null) _railAfterContact = true;
        if (b.number != 0) _railBalls.add(b.number);
        events.add(PhysicsEvent(PhysicsEventType.cushionHit, (vn.abs() / 1200).clamp(0.05, 1.0)));
      }
    }
  }

  void _checkPockets() {
    for (final b in balls) {
      if (b.pocketed) continue;
      var hit = -1;
      for (var i = 0; i < TableGeometry.pockets.length; i++) {
        final p = TableGeometry.pockets[i];
        if (b.pos.distanceTo(p.center) < p.radius) hit = i;
      }
      if (hit < 0 && !TableGeometry.insidePlayfield(b.pos, margin: -4)) {
        // Slipped through a mouth past the capture circle: nearest pocket takes it.
        var best = double.infinity;
        for (var i = 0; i < TableGeometry.pockets.length; i++) {
          final d = b.pos.distanceTo(TableGeometry.pockets[i].center);
          if (d < best) {
            best = d;
            hit = i;
          }
        }
      }
      if (hit < 0) continue;
      b
        ..pocketed = true
        ..vel = Vec2.zero;
      if (b.number == 0) {
        _cuePocketed = true;
      } else {
        _pocketed.add(b.number);
        _pocketOf[b.number] = hit;
      }
      events.add(PhysicsEvent(PhysicsEventType.pocket, 1, ball: b.number, pocket: hit, at: b.pos));
    }
  }

  // ------------------------------------------------------------------ aim

  /// Straight-line prediction of the first impact for the aiming guide.
  AimPrediction predict(double angle) {
    final o = cue.pos;
    final d = Vec2.fromAngle(angle);
    var bestT = double.infinity;
    Ball? hit;
    for (final b in balls) {
      if (b.pocketed || b.number == 0) continue;
      final oc = b.pos - o;
      final proj = oc.dot(d);
      if (proj <= 0) continue;
      final perp2 = oc.length2 - proj * proj;
      final rr = 4 * _r * _r;
      if (perp2 >= rr) continue;
      final t = proj - sqrt(rr - perp2);
      if (t >= 0 && t < bestT) {
        bestT = t;
        hit = b;
      }
    }
    var wallT = double.infinity;
    if (d.x > 0) wallT = min(wallT, (TableGeometry.width - _r - o.x) / d.x);
    if (d.x < 0) wallT = min(wallT, (_r - o.x) / d.x);
    if (d.y > 0) wallT = min(wallT, (TableGeometry.height - _r - o.y) / d.y);
    if (d.y < 0) wallT = min(wallT, (_r - o.y) / d.y);
    if (hit == null || wallT < bestT) {
      return AimPrediction(ghost: o + d * max(0, wallT));
    }
    final ghost = o + d * bestT;
    final targetDir = (hit.pos - ghost).normalized;
    final tangent = d - targetDir * d.dot(targetDir);
    return AimPrediction(
      ghost: ghost,
      hitBall: hit.number,
      targetDir: targetDir,
      cueDir: tangent.length < 0.05 ? null : tangent.normalized,
    );
  }

  /// True when a ball can travel from [from] to [to] without touching any
  /// ball other than those in [ignore].
  bool pathClear(Vec2 from, Vec2 to, {Set<int> ignore = const {}}) {
    final seg = to - from;
    final len2 = seg.length2;
    if (len2 == 0) return true;
    for (final b in balls) {
      if (b.pocketed || ignore.contains(b.number)) continue;
      final t = ((b.pos - from).dot(seg) / len2).clamp(0.0, 1.0);
      if ((from + seg * t).distanceTo(b.pos) < 2 * _r - 0.5) return false;
    }
    return true;
  }
}
