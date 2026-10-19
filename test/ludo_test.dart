import 'dart:math';

import 'package:billiard_poker/game/ludo/ludo_bot.dart';
import 'package:billiard_poker/game/ludo/ludo_rules.dart';
import 'package:flutter_test/flutter_test.dart';

LudoState _game(int seats, Random rng) {
  final colours = seats == 2 ? [0, 2] : [0, 1, 2, 3];
  return LudoState.initial(
    [for (var i = 0; i < seats; i++) LudoPlayer(name: 'P$i', avatar: 'asset:avatar_1', colour: colours[i], isBot: true)],
    30,
  );
}

/// Plays a whole match with bots and a seeded die; returns the winning seat.
int _playOut(LudoState s, Random rng, {int cap = 5000}) {
  final bot = LudoBot(rng);
  for (var i = 0; i < cap && s.phase == LudoPhase.playerTurn; i++) {
    final die = rng.nextInt(6) + 1;
    final moves = LudoRules.roll(s, die);
    if (moves.isNotEmpty) {
      LudoRules.move(s, bot.chooseToken(s, s.turn, die, moves));
    }
    _check(s);
  }
  return s.winner ?? -1;
}

void _check(LudoState s) {
  for (final p in s.players) {
    var home = 0;
    for (final step in p.tokens) {
      expect(step >= -1 && step <= LudoRules.homeStep, isTrue, reason: 'token step out of range: $step');
      if (step == LudoRules.homeStep) home++;
    }
    expect(p.finished, home, reason: 'finished count must match tokens at home');
  }
}

void main() {
  test('leaving base needs a six; others are stuck', () {
    final s = _game(2, Random(1));
    expect(LudoRules.movable(s, 0, 3), isEmpty);
    expect(LudoRules.movable(s, 0, 6), [0, 1, 2, 3]);
    LudoRules.roll(s, 6);
    LudoRules.move(s, 0);
    expect(s.players[0].tokens[0], 0); // on its start square
    expect(s.turn, 0, reason: 'a six grants another roll');
  });

  test('capture sends the opponent token home and grants another roll', () {
    final s = _game(2, Random(1)); // seat0 red (start 0), seat1 yellow (start 26)
    // Yellow token on ring cell 27 (not safe); red one short, lands on it.
    s.players[1].tokens[0] = 1; // yellow step 1 -> ring (26+1)=27
    s.players[0].tokens[0] = 26; // red step 26 -> ring 26
    s.turn = 0;
    s.mustRoll = true;
    final moves = LudoRules.roll(s, 1); // red -> step 27 = ring 27
    expect(moves.contains(0), isTrue);
    LudoRules.move(s, 0);
    expect(s.players[1].tokens[0], -1, reason: 'yellow token sent home');
    expect(s.turn, 0, reason: 'capture grants another roll');
  });

  test('home must be reached exactly; overshoot is illegal', () {
    final s = _game(2, Random(1));
    s.players[0].tokens[0] = 54; // two short of home (56)
    expect(LudoRules.canMove(s, 0, 0, 3), isFalse, reason: 'would overshoot');
    expect(LudoRules.canMove(s, 0, 0, 2), isTrue);
    s.turn = 0;
    s.mustRoll = true;
    LudoRules.roll(s, 2);
    final m = LudoRules.move(s, 0);
    expect(s.players[0].tokens[0], LudoRules.homeStep);
    expect(s.players[0].finished, 1);
    expect(m.extraTurn, isTrue, reason: 'finishing a token grants another roll');
  });

  test('a safe cell cannot be captured', () {
    final s = _game(2, Random(1));
    s.players[1].tokens[0] = 0; // yellow start = ring cell 26 (safe)
    s.players[0].tokens[0] = 25; // red ring 25
    s.turn = 0;
    s.mustRoll = true;
    LudoRules.roll(s, 1); // red -> ring 26 (yellow's safe start)
    LudoRules.move(s, 0);
    expect(s.players[1].tokens[0], 0, reason: 'yellow is safe on its start cell');
  });

  test('three sixes in a row forfeit the turn', () {
    final s = _game(2, Random(1));
    s.players[0].tokens[0] = 5; // on the ring
    s.turn = 0;
    s.mustRoll = true;
    LudoRules.roll(s, 6);
    LudoRules.move(s, 0); // extra turn
    expect(s.turn, 0);
    LudoRules.roll(s, 6);
    LudoRules.move(s, 0); // extra turn, sixes=2
    expect(s.turn, 0);
    final moves = LudoRules.roll(s, 6); // third six -> void
    expect(moves, isEmpty);
    expect(s.turn, 1, reason: 'turn forfeited to the next player');
  });

  test('2-player games always finish with a winner', () {
    for (var seed = 0; seed < 40; seed++) {
      final rng = Random(seed);
      final s = _game(2, rng);
      final w = _playOut(s, rng);
      expect(w, isNot(-1), reason: 'seed $seed did not finish');
      expect(s.players[w].finished, 4);
    }
  });

  test('4-player games always finish with a winner', () {
    for (var seed = 0; seed < 40; seed++) {
      final rng = Random(seed + 100);
      final s = _game(4, rng);
      final w = _playOut(s, rng);
      expect(w, isNot(-1), reason: 'seed ${seed + 100} did not finish');
      expect(s.players[w].finished, 4);
    }
  });
}
