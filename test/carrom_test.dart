import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:billiard_poker/game/carrom/carrom_bot.dart';
import 'package:billiard_poker/game/carrom/carrom_physics.dart';
import 'package:billiard_poker/game/carrom/carrom_rules.dart';
import 'package:billiard_poker/game/physics/vec2.dart';
import 'package:flutter_test/flutter_test.dart';

CarromState _state({int turn = 0}) => CarromState(
      players: [
        CarromPlayer(name: 'A', avatar: 'x', colour: 0),
        CarromPlayer(name: 'B', avatar: 'x', colour: 1, isBot: true),
      ],
      turn: turn,
    );

/// Marks [discs] pocketed in the world and rules on it as a stroke by [seat].
CarromShotResult _stroke(CarromState s, CarromWorld w, int seat, {List<int> pocketed = const [], bool striker = false}) {
  w.shoot(const Vec2(0, -1), 0);
  for (final d in pocketed) {
    w.gone[d] = true;
    w.pocketed.add(d);
  }
  w.strikerPocketed = striker;
  return CarromRules.resolve(s, w, seat);
}

void main() {
  group('opening layout', () {
    test('nine white, nine black, the queen on the centre, nothing overlapping', () {
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      expect(CarromRules.onBoard(w, 0).length, 9);
      expect(CarromRules.onBoard(w, 1).length, 9);
      expect(w.gone[CarromWorld.queen], isFalse);
      expect(w.gone[CarromWorld.striker], isTrue);
      expect(w.x[CarromWorld.queen], 500);
      expect(w.y[CarromWorld.queen], 500);
      for (var i = 1; i < CarromWorld.count; i++) {
        for (var j = i + 1; j < CarromWorld.count; j++) {
          final d = Vec2(w.x[i] - w.x[j], w.y[i] - w.y[j]).length;
          expect(d, greaterThanOrEqualTo(2 * CarromWorld.pieceR), reason: '$i and $j overlap');
        }
      }
    });
  });

  group('rules', () {
    test('own piece pocketed: counted, shoot again', () {
      final s = _state();
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      final r = _stroke(s, w, 0, pocketed: [3]);
      expect(s.players[0].pocketed, 1);
      expect(r.extraTurn, isTrue);
      expect(s.turn, 0);
      expect(w.gone[CarromWorld.striker], isTrue);
    });

    test("opponent's piece pocketed: counted for them, turn passes", () {
      final s = _state();
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      final r = _stroke(s, w, 0, pocketed: [12]);
      expect(s.players[1].pocketed, 1);
      expect(r.extraTurn, isFalse);
      expect(s.turn, 1);
    });

    test('striker pocketed: a foul, the pocketed pieces and a penalty piece come back', () {
      final s = _state();
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      _stroke(s, w, 0, pocketed: [1]);
      expect(s.players[0].pocketed, 1);
      final r = _stroke(s, w, 0, pocketed: [2], striker: true);
      expect(r.foul, isTrue);
      expect(r.returned, [2]);
      expect(r.penalty, 1);
      expect(s.players[0].pocketed, 0);
      expect(w.gone[1], isFalse);
      expect(w.gone[2], isFalse);
      expect(s.turn, 1);
    });

    test('queen needs a cover: covered next stroke, or returned', () {
      final s = _state();
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      var r = _stroke(s, w, 0, pocketed: [CarromWorld.queen]);
      expect(r.queenPending, isTrue);
      expect(s.queenPending, 0);
      expect(r.extraTurn, isTrue);
      r = _stroke(s, w, 0, pocketed: [4]);
      expect(r.queenCovered, isTrue);
      expect(s.players[0].hasQueen, isTrue);
      expect(s.queenPending, isNull);

      final s2 = _state();
      final w2 = CarromWorld()..setDiscs(CarromWorld.opening());
      _stroke(s2, w2, 0, pocketed: [CarromWorld.queen]);
      r = _stroke(s2, w2, 0);
      expect(r.queenReturned, isTrue);
      expect(w2.gone[CarromWorld.queen], isFalse);
      expect(s2.turn, 1);
    });

    test('queen and own piece in one stroke covers her at once', () {
      final s = _state();
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      final r = _stroke(s, w, 0, pocketed: [CarromWorld.queen, 5]);
      expect(r.queenCovered, isTrue);
      expect(s.players[0].hasQueen, isTrue);
    });

    test('the last piece may not drop before the queen is owned', () {
      final s = _state();
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      for (var i = 1; i <= 8; i++) {
        _stroke(s, w, 0, pocketed: [i]);
      }
      expect(s.players[0].pocketed, 8);
      final r = _stroke(s, w, 0, pocketed: [9]);
      expect(r.lastPieceReturned, isTrue);
      expect(s.players[0].pocketed, 8);
      expect(w.gone[9], isFalse);
      expect(s.phase, CarromPhase.playerTurn);
      // With the queen owned the ninth piece wins.
      _stroke(s, w, 0, pocketed: [CarromWorld.queen, 9]);
      expect(s.phase, CarromPhase.gameOver);
      expect(s.winner, 0);
    });

    test('timeouts: the turn passes, three in a row lose', () {
      final s = _state();
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      CarromRules.timeout(s, w);
      expect(s.turn, 1);
      CarromRules.timeout(s, w);
      CarromRules.timeout(s, w);
      expect(s.players[0].missed, 2);
      CarromRules.timeout(s, w);
      CarromRules.timeout(s, w);
      expect(s.phase, CarromPhase.gameOver);
      expect(s.winner, 1);
    });
  });

  group('physics', () {
    test('a stroke comes to rest and a straight shot drops the far piece or stops', () {
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      w.placeStriker(0, 500);
      w.shoot(const Vec2(0, -1), 0.6);
      final seconds = w.simulate();
      expect(seconds, greaterThan(0.5));
      expect(seconds, lessThan(8));
      expect(w.isMoving, isFalse);
      expect(w.firstContact, isNotNull);
    });

    test('striker never sits on a piece', () {
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      // Park a piece on the base line where the striker wants to go.
      w.x[1] = 500;
      w.y[1] = CarromWorld.baseNear;
      final x = w.placeStriker(0, 500);
      expect((x - 500).abs(), greaterThan(CarromWorld.strikerR));
      expect(w.strikerFits(0, x), isTrue);
    });

    test('the bot plays a whole match against itself', () {
      final rng = Random(3);
      final bot = CarromBot(rng, skill: 0.8);
      final s = _state();
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      var strokes = 0;
      while (s.phase != CarromPhase.gameOver && strokes < 150) {
        final shot = bot.chooseShot(w, s, s.turn);
        w.placeStriker(s.turn, shot.x);
        w.shoot(shot.dir, shot.power);
        w.simulate();
        CarromRules.resolve(s, w, s.turn);
        strokes++;
      }
      expect(s.phase, CarromPhase.gameOver);
      expect(s.players[s.winner!].pocketed, 9);
    });
  });

  group('server mirror', () {
    test('the PHP simulation leaves every disc exactly where Dart does', () async {
      final phpProbe = Platform.isWindows
          ? await Process.run('where', ['php'], runInShell: true)
          : await Process.run('which', ['php']);
      if (phpProbe.exitCode != 0 || (phpProbe.stdout as String).trim().isEmpty) {
        markTestSkipped('php not installed');
        return;
      }
      final shots = [
        [0, 500.0, 0.0, -1.0, 0.7],
        [1, 406.0, -0.3, 0.953939201416946, 0.9],
        [0, 700.0, -0.5, -0.8660254037844386, 1.0],
        [1, 260.0, 0.6, 0.8, 0.45],
        [0, 330.0, 0.2, -0.9797958971132712, 0.8],
      ];
      final w = CarromWorld()..setDiscs(CarromWorld.opening());
      final dartTrace = <List<dynamic>>[];
      for (final sh in shots) {
        final seat = sh[0] as int;
        w.placeStriker(seat, sh[1] as double);
        w.shoot(Vec2(sh[2] as double, sh[3] as double), sh[4] as double);
        w.simulate();
        dartTrace.add([List.of(w.pocketed), w.strikerPocketed, w.toDiscs()]);
        w.gone[CarromWorld.striker] = true;
        for (final d in w.pocketed) {
          w.returnToCentre(d);
        }
      }
      final root = Directory.current.path;
      final r = await Process.run('php', ['$root/backend/tests/carrom_mirror.php', jsonEncode(shots)], workingDirectory: '$root/backend');
      expect(r.exitCode, 0, reason: r.stderr.toString());
      final phpTrace = jsonDecode(r.stdout as String) as List;
      for (var i = 0; i < shots.length; i++) {
        final d = dartTrace[i], p = phpTrace[i] as List;
        expect(p[0], d[0], reason: 'stroke $i pocketed');
        expect(p[1], d[1], reason: 'stroke $i striker');
        final dd = d[2] as List<List<dynamic>>, pd = (p[2] as List).cast<List<dynamic>>();
        for (var k = 0; k < CarromWorld.count; k++) {
          expect(pd[k][2], dd[k][2], reason: 'stroke $i disc $k gone');
          expect((pd[k][0] as num).toDouble(), closeTo(dd[k][0] as double, 1e-9), reason: 'stroke $i disc $k x');
          expect((pd[k][1] as num).toDouble(), closeTo(dd[k][1] as double, 1e-9), reason: 'stroke $i disc $k y');
        }
      }
    });
  });
}
