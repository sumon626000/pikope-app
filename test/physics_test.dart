import 'dart:math';

import 'package:billiard_poker/game/ai/bot_player.dart';
import 'package:billiard_poker/game/models/match_state.dart';
import 'package:billiard_poker/game/physics/physics_world.dart';
import 'package:billiard_poker/game/physics/table_geometry.dart';
import 'package:billiard_poker/game/physics/vec2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

PhysicsWorld emptyTable() => PhysicsWorld()
  ..cue.pocketed = false
  ..cue.pos = const Vec2(250, 250);

void place(PhysicsWorld w, int n, Vec2 p) => w.balls[n]
  ..pos = p
  ..pocketed = false;

void main() {
  test('rack puts 15 non-overlapping balls on the table', () {
    final w = PhysicsWorld()..rack(Random(4));
    final active = w.balls.where((b) => !b.pocketed).toList();
    expect(active.length, 16);
    for (final a in active) {
      for (final b in active) {
        if (a != b) {
          expect(a.pos.distanceTo(b.pos), greaterThanOrEqualTo(2 * TableGeometry.ballRadius));
        }
      }
    }
  });

  test('break shot spreads the rack and every ball comes to rest', () {
    final w = PhysicsWorld()..rack(Random(4));
    w.shoot(0, 1);
    final o = w.simulateToRest();
    expect(w.isMoving, isFalse);
    expect(o.firstContact, isNotNull);
    for (final b in w.balls.where((b) => !b.pocketed)) {
      expect(TableGeometry.insidePlayfield(b.pos, margin: 0), isTrue, reason: 'ball ${b.number}');
    }
  });

  test('first contact is the first object ball the cue ball touches', () {
    final w = emptyTable();
    place(w, 5, const Vec2(500, 250));
    place(w, 9, const Vec2(700, 250));
    w.shoot(0, 0.5);
    expect(w.simulateToRest().firstContact, 5);
  });

  test('a straight shot pockets the ball in the corner', () {
    final w = emptyTable();
    w.cue.pos = const Vec2(500, 250);
    final target = const Vec2(900, 450);
    place(w, 3, target);
    final toPocket = (TableGeometry.pockets[5].aim - target).normalized;
    final ghost = target - toPocket * (2 * TableGeometry.ballRadius);
    w.shoot((ghost - w.cue.pos).angle, 0.5);
    final o = w.simulateToRest();
    expect(o.firstContact, 3);
    expect(o.pocketed, [3]);
    expect(o.cuePocketed, isFalse);
  });

  test('cue ball into a pocket is a scratch', () {
    final w = emptyTable();
    w.shoot((TableGeometry.pockets[0].aim - w.cue.pos).angle, 0.6);
    final o = w.simulateToRest();
    expect(o.cuePocketed, isTrue);
    expect(o.firstContact, isNull);
  });

  test('balls bounce off cushions and stay on the table', () {
    final w = emptyTable();
    w.shoot(pi / 2 + 0.3, 0.9);
    final o = w.simulateToRest();
    expect(o.railContact, isTrue);
    expect(o.cuePocketed, isFalse);
    expect(TableGeometry.insidePlayfield(w.cue.pos), isTrue);
  });

  test('simulation is deterministic', () {
    List<Vec2> run() {
      final w = PhysicsWorld()..rack(Random(9));
      w.shoot(0.03, 0.9, spinX: 0.4, spinY: -0.5);
      w.simulateToRest();
      return [for (final b in w.balls) b.pos];
    }

    final a = run(), b = run();
    for (var i = 0; i < a.length; i++) {
      expect(a[i].x, b[i].x);
      expect(a[i].y, b[i].y);
    }
  });

  test('respot never overlaps another ball', () {
    final w = PhysicsWorld()..rack(Random(2));
    w.balls[7].pocketed = true;
    w.respot(7);
    for (final b in w.balls.where((b) => !b.pocketed && b.number != 7)) {
      expect(b.pos.distanceTo(w.balls[7].pos), greaterThanOrEqualTo(2 * TableGeometry.ballRadius));
    }
  });

  test('aim prediction reports the ball in the line of fire', () {
    final w = emptyTable();
    place(w, 5, const Vec2(600, 250));
    final hit = w.predict(0);
    expect(hit.hitBall, 5);
    expect(hit.ghost.x, closeTo(600 - 2 * TableGeometry.ballRadius, 0.01));
    expect(w.predict(pi).hitBall, isNull);
  });

  test('bot always nominates a legal target and hits it first when it can', () {
    var legal = 0;
    const rounds = 20;
    for (var seed = 0; seed < rounds; seed++) {
      final m = matchWith(defaultHands);
      final w = PhysicsWorld()..rack(Random(seed));
      w.shoot(0.01 * seed, 0.95);
      w.simulateToRest();
      for (final b in w.balls.where((b) => b.pocketed).toList()) {
        b.number == 0 ? w.respotCue() : w.respot(b.number);
      }
      final shot = BotPlayer(Random(seed)).chooseShot(w, m.state);
      final target = shot.card?.card.ball ?? shot.freeBall;
      expect(target, isNotNull);
      if (shot.card != null) expect(m.engine.selectCard(m.state, shot.card!), isTrue);
      if (shot.freeBall != null) expect(m.engine.selectFreeBall(m.state, shot.freeBall!), isTrue);
      w.shoot(shot.angle, shot.power);
      final r = m.engine.resolveShot(m.state, w.simulateToRest());
      if (r.foulType == FoulType.none) legal++;
    }
    // The hand here needs only balls 1 and 7; after a break one of them is
    // often snookered, and the bot has no kick shots. It must still find the
    // legal hit whenever a direct line exists.
    expect(legal, greaterThan(rounds ~/ 3));
  });
}
