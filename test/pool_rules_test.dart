import 'dart:math';

import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/features/game/game_controller.dart' show SeatConfig;
import 'package:billiard_poker/features/pool/pool_controller.dart';
import 'package:billiard_poker/game/models/match_state.dart' show ShotOutcome;
import 'package:billiard_poker/game/physics/physics_world.dart';
import 'package:billiard_poker/game/physics/table_geometry.dart';
import 'package:billiard_poker/game/pool/pool_rules.dart';
import 'package:flutter_test/flutter_test.dart';

PoolState newGame(PoolGame game, {bool afterBreak = true}) {
  final s = PoolState(game: game, players: [
    PoolPlayer(name: 'A', avatar: ''),
    PoolPlayer(name: 'B', avatar: ''),
  ]);
  if (afterBreak) {
    s
      ..isBreakShot = false
      ..ballInHand = false
      ..behindHeadString = false;
  }
  return s;
}

Set<int> balls(int n) => {for (var i = 1; i <= n; i++) i};

void main() {
  final rules = PoolRules(random: Random(1));

  group('racks', () {
    test('9-ball: diamond of 9, 1 on the apex, 9 in the centre', () {
      final w = PhysicsWorld();
      rules.rack(newGame(PoolGame.nineBall), w);
      final on = w.balls.where((b) => !b.pocketed && b.number != 0).toList();
      expect(on.map((b) => b.number).toSet(), balls(9));
      expect(w.balls[1].pos.x, TableGeometry.footSpot.x);
      expect(on.every((b) => b.pos.x >= w.balls[1].pos.x), isTrue);
      final xs = on.map((b) => b.pos.x), ys = on.map((b) => b.pos.y);
      expect(w.balls[9].pos.x, closeTo((xs.reduce(min) + xs.reduce(max)) / 2, 0.01));
      expect(w.balls[9].pos.y, closeTo((ys.reduce(min) + ys.reduce(max)) / 2, 0.01));
    });

    test('10-ball: triangle of 10, 1 in front, 10 in the middle', () {
      final w = PhysicsWorld();
      rules.rack(newGame(PoolGame.tenBall), w);
      final on = w.balls.where((b) => !b.pocketed && b.number != 0).toList();
      expect(on.map((b) => b.number).toSet(), balls(10));
      expect(on.every((b) => b.pos.x >= w.balls[1].pos.x), isTrue);
      expect(w.balls[10].pos.y, closeTo(TableGeometry.footSpot.y, 0.01));
    });

    test('8-ball: 15 balls, 8 in the centre of the third row', () {
      final w = PhysicsWorld();
      rules.rack(newGame(PoolGame.eightBall), w);
      expect(w.balls.where((b) => !b.pocketed && b.number != 0).length, 15);
      expect(w.balls[8].pos.y, closeTo(TableGeometry.footSpot.y, 0.01));
      final rowX = w.balls.where((b) => !b.pocketed && b.number != 0).map((b) => b.pos.x).toSet().toList()..sort();
      expect(w.balls[8].pos.x, closeTo(rowX[2], 0.01));
    });
  });

  group('9-ball', () {
    test('lowest ball must be hit first', () {
      final s = newGame(PoolGame.nineBall);
      expect(rules.legalTargets(s, {3, 5, 9}), {3});
      final r = rules.resolveShot(s, const ShotOutcome(firstContact: 5, railAfterContact: true), {3, 5, 9});
      expect(r.foul, PoolFoul.wrongBallFirst);
      expect(s.turn, 1);
      expect(s.ballInHand, isTrue);
    });

    test('pocketing any ball legally keeps the turn', () {
      final s = newGame(PoolGame.nineBall);
      final r = rules.resolveShot(s, const ShotOutcome(firstContact: 1, pocketed: [4]), balls(9));
      expect(r.legal, isTrue);
      expect(r.turnContinues, isTrue);
      expect(s.turn, 0);
    });

    test('a combination on the 9 wins at once', () {
      final s = newGame(PoolGame.nineBall);
      final r = rules.resolveShot(s, const ShotOutcome(firstContact: 2, pocketed: [9]), {2, 6, 9});
      expect(r.winner, 0);
      expect(s.phase, PoolPhase.gameOver);
    });

    test('9 on the break wins', () {
      final s = newGame(PoolGame.nineBall, afterBreak: false);
      expect(rules.resolveShot(s, const ShotOutcome(firstContact: 1, pocketed: [9]), balls(9)).winner, 0);
    });

    test('9 pocketed on a foul is spotted and the opponent has ball in hand', () {
      final s = newGame(PoolGame.nineBall);
      final r = rules.resolveShot(
          s, const ShotOutcome(firstContact: 2, pocketed: [9], cuePocketed: true), {2, 9});
      expect(r.winner, isNull);
      expect(r.respot, [9]);
      expect(r.foul, PoolFoul.scratch);
      expect(s.turn, 1);
      expect(s.ballInHand, isTrue);
    });

    test('no rail after contact is a foul when nothing drops', () {
      final s = newGame(PoolGame.nineBall);
      expect(rules.resolveShot(s, const ShotOutcome(firstContact: 1), balls(9)).foul, PoolFoul.noRail);
    });

    test('break needs a pocketed ball or four balls to a rail', () {
      var s = newGame(PoolGame.nineBall, afterBreak: false);
      expect(
          rules.resolveShot(s,
              const ShotOutcome(firstContact: 1, railAfterContact: true, objectBallsToRail: 3), balls(9)).foul,
          PoolFoul.illegalBreak);
      s = newGame(PoolGame.nineBall, afterBreak: false);
      final ok = rules.resolveShot(
          s, const ShotOutcome(firstContact: 1, railAfterContact: true, objectBallsToRail: 4), balls(9));
      expect(ok.legal, isTrue);
      expect(s.pushOutAvailable, isTrue);
    });

    test('three consecutive fouls lose the game; a legal shot resets the count', () {
      final s = newGame(PoolGame.nineBall);
      for (var i = 0; i < 2; i++) {
        s.turn = 0;
        rules.resolveShot(s, const ShotOutcome(), balls(9));
      }
      expect(s.players[0].consecutiveFouls, 2);
      s.turn = 0;
      rules.resolveShot(s, const ShotOutcome(firstContact: 1, railAfterContact: true), balls(9));
      expect(s.players[0].consecutiveFouls, 0);
      for (var i = 0; i < 3; i++) {
        s.turn = 0;
        rules.resolveShot(s, const ShotOutcome(), balls(9));
      }
      expect(s.winner, 1);
      expect(s.winReason, 'THREE FOULS IN A ROW');
    });

    test('push out: no contact needed, then the opponent shoots or passes back', () {
      final s = newGame(PoolGame.nineBall)..pushOutAvailable = true;
      expect(rules.togglePushOut(s), isTrue);
      final r = rules.resolveShot(s, const ShotOutcome(), balls(9));
      expect(r.legal, isTrue);
      expect(r.wasPushOut, isTrue);
      expect(s.phase, PoolPhase.pushOutChoice);
      expect(s.turn, 1);
      expect(s.ballInHand, isFalse);
      rules.answerPushOut(s, shoot: false);
      expect(s.turn, 0);
      expect(s.phase, PoolPhase.playerTurn);
      expect(s.pushOutAvailable, isFalse);
    });
  });

  group('10-ball', () {
    test('lowest first; 10 by combination wins', () {
      final s = newGame(PoolGame.tenBall);
      expect(rules.legalTargets(s, {1, 3, 5, 10}), {1});
      expect(rules.resolveShot(s, const ShotOutcome(firstContact: 3, pocketed: [10]), {3, 5, 10}).winner, 0);
    });

    test('10 pocketed illegally is spotted, opponent gets ball in hand', () {
      final s = newGame(PoolGame.tenBall);
      final r = rules.resolveShot(s, const ShotOutcome(firstContact: 5, pocketed: [10]), {3, 5, 10});
      expect(r.winner, isNull);
      expect(r.respot, [10]);
      expect(s.turn, 1);
      expect(s.ballInHand, isTrue);
    });

    test('no three-foul loss and no push out in 10-ball', () {
      final s = newGame(PoolGame.tenBall, afterBreak: false);
      rules.resolveShot(s, const ShotOutcome(firstContact: 1, pocketed: [4]), balls(10));
      expect(s.pushOutAvailable, isFalse);
      for (var i = 0; i < 4; i++) {
        s.turn = 0;
        rules.resolveShot(s, const ShotOutcome(), balls(10));
      }
      expect(s.winner, isNull);
    });
  });

  group('8-ball', () {
    test('table is open after the break, even if the breaker pockets a ball', () {
      final s = newGame(PoolGame.eightBall, afterBreak: false);
      final r = rules.resolveShot(s, const ShotOutcome(firstContact: 1, pocketed: [3]), balls(15));
      expect(r.turnContinues, isTrue);
      expect(s.players[0].group, PoolGroup.none);
      expect(rules.legalTargets(s, balls(15)..remove(3)), isNot(contains(8)));
    });

    test('first legally pocketed ball assigns the groups', () {
      final s = newGame(PoolGame.eightBall);
      final r = rules.resolveShot(s, const ShotOutcome(firstContact: 11, pocketed: [11]), balls(15));
      expect(r.groupAssigned, PoolGroup.stripes);
      expect(s.players[0].group, PoolGroup.stripes);
      expect(s.players[1].group, PoolGroup.solids);
      expect(r.turnContinues, isTrue);
    });

    test('must hit your own group first', () {
      final s = newGame(PoolGame.eightBall)
        ..players[0].group = PoolGroup.solids
        ..players[1].group = PoolGroup.stripes;
      expect(rules.legalTargets(s, {1, 2, 8, 9, 10}), {1, 2});
      final r = rules.resolveShot(s, const ShotOutcome(firstContact: 9), {1, 2, 8, 9, 10});
      expect(r.foul, PoolFoul.wrongBallFirst);
      expect(s.ballInHand, isTrue);
    });

    test('opponent ball pocketed off a legal hit is legal; turn continues only with an own ball', () {
      PoolState fresh() => newGame(PoolGame.eightBall)
        ..players[0].group = PoolGroup.solids
        ..players[1].group = PoolGroup.stripes;
      var s = fresh();
      var r = rules.resolveShot(s, const ShotOutcome(firstContact: 1, pocketed: [9]), balls(15));
      expect(r.legal, isTrue);
      expect(r.turnContinues, isFalse);
      expect(s.ballInHand, isFalse);
      s = fresh();
      r = rules.resolveShot(s, const ShotOutcome(firstContact: 1, pocketed: [9, 1]), balls(15));
      expect(r.turnContinues, isTrue);
    });

    test('8 before clearing the group loses', () {
      final s = newGame(PoolGame.eightBall)..players[0].group = PoolGroup.solids;
      final r = rules.resolveShot(s, const ShotOutcome(firstContact: 1, pocketed: [8]), {1, 8, 9});
      expect(r.winner, 1);
    });

    PoolState onTheEight() => newGame(PoolGame.eightBall)
      ..players[0].group = PoolGroup.solids
      ..players[1].group = PoolGroup.stripes;

    test('the 8 needs a called pocket before shooting', () {
      final s = onTheEight();
      expect(rules.onEight(s, {8, 9}), isTrue);
      expect(rules.legalTargets(s, {8, 9}), {8});
      expect(rules.canShoot(s, {8, 9}), isFalse);
      expect(rules.callPocket(s, {8, 9}, 2), isTrue);
      expect(rules.canShoot(s, {8, 9}), isTrue);
    });

    test('8 in the called pocket wins', () {
      final s = onTheEight()..calledPocket = 2;
      final r = rules.resolveShot(
          s, const ShotOutcome(firstContact: 8, pocketed: [8], pocketOf: {8: 2}), {8, 9});
      expect(r.winner, 0);
    });

    test('8 in the wrong pocket loses', () {
      final s = onTheEight()..calledPocket = 2;
      final r = rules.resolveShot(
          s, const ShotOutcome(firstContact: 8, pocketed: [8], pocketOf: {8: 4}), {8, 9});
      expect(r.winner, 1);
      expect(r.reason, '8-BALL IN THE WRONG POCKET');
    });

    test('scratching while pocketing the 8 loses', () {
      final s = onTheEight()..calledPocket = 2;
      final r = rules.resolveShot(
          s,
          const ShotOutcome(firstContact: 8, pocketed: [8], pocketOf: {8: 2}, cuePocketed: true),
          {8, 9});
      expect(r.winner, 1);
    });

    test('missing the 8 just ends the turn', () {
      final s = onTheEight()..calledPocket = 2;
      final r = rules.resolveShot(s, const ShotOutcome(firstContact: 8), {8, 9});
      expect(r.winner, isNull);
      expect(r.legal, isTrue);
      expect(s.turn, 1);
      expect(s.calledPocket, isNull);
    });
  });

  group('timeout', () {
    test('passes the turn with ball in hand', () {
      final s = newGame(PoolGame.eightBall);
      final r = rules.timeout(s);
      expect(r.foul, PoolFoul.timeout);
      expect(s.turn, 1);
      expect(s.ballInHand, isTrue);
    });
  });

  group('full matches (bots, real physics)', () {
    for (final game in PoolGame.values) {
      for (final seed in [1, 2]) {
        test('${game.title} plays to a winner (seed $seed)', () {
          final c = PoolController(
            PoolMatchConfig(game: game, seed: seed, seats: const [
              SeatConfig(name: 'BOT A', avatar: '', isBot: true, botSkill: 0.9),
              SeatConfig(name: 'BOT B', avatar: '', isBot: true, botSkill: 0.9),
            ]),
            AudioService(enabled: false),
          );
          var ticks = 0;
          while (c.state.phase != PoolPhase.gameOver && ticks++ < 400000) {
            c.tick(0.05);
            if (c.state.phase == PoolPhase.playerTurn && !c.presenting) {
              expect(c.world.cue.pocketed, isFalse);
              for (final b in c.world.balls.where((b) => !b.pocketed)) {
                expect(TableGeometry.insidePlayfield(b.pos, margin: 0), isTrue);
              }
            }
          }
          expect(c.state.phase, PoolPhase.gameOver, reason: 'match did not finish');
          expect(c.state.winner, isNotNull);
          expect(c.state.winReason, isNotNull);
          // ignore: avoid_print
          print('${game.title} seed $seed: ${c.players[c.state.winner!].name} wins by '
              '"${c.state.winReason}" after ${c.state.shotNumber} shots');
          c.dispose();
        });
      }
    }

    test('rematch re-racks', () {
      final c = PoolController(
        const PoolMatchConfig(game: PoolGame.nineBall, seed: 3, seats: [
          SeatConfig(name: 'A', avatar: '', isBot: true),
          SeatConfig(name: 'B', avatar: '', isBot: true),
        ]),
        AudioService(enabled: false),
      );
      for (var i = 0; i < 400000 && c.state.phase != PoolPhase.gameOver; i++) {
        c.tick(0.05);
      }
      c.rematch();
      expect(c.state.winner, isNull);
      expect(c.onTable, balls(9));
      c.dispose();
    });
  });
}
