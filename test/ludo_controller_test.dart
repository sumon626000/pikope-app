import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/features/game/game_controller.dart' show SeatConfig;
import 'package:billiard_poker/features/ludo/ludo_controller.dart';
import 'package:billiard_poker/game/ludo/ludo_rules.dart';
import 'package:flutter_test/flutter_test.dart';

LudoMatchConfig _config(int seats, int humans, int seed) => LudoMatchConfig(
      seats: seats,
      players: [for (var i = 0; i < seats; i++) SeatConfig(name: 'P$i', avatar: 'a', isBot: i >= humans)],
      seed: seed,
      humanSeats: humans,
    );

/// Runs the controller like the screen's ticker does; the human (seat 0)
/// rolls and taps the first movable token, as a player would.
LudoController _play(int seats, int humans, int seed, {int maxSteps = 400000}) {
  final c = LudoController(_config(seats, humans, seed), AudioService(enabled: false));
  c.start();
  for (var i = 0; i < maxSteps && !c.over; i++) {
    if (c.canRoll) c.roll();
    if (c.movable.isNotEmpty) c.moveToken(c.movable.first);
    c.tick(1 / 30);
  }
  return c;
}

void main() {
  test('a human vs bots match plays through to a winner (2 players)', () {
    for (var seed = 1; seed <= 6; seed++) {
      final c = _play(2, 1, seed);
      expect(c.over, isTrue, reason: 'seed $seed did not finish');
      expect(c.winner, isNotNull);
      expect(c.state!.players[c.winner!].finished, 4);
    }
  });

  test('a 4-player match with bots plays through to a winner', () {
    for (var seed = 1; seed <= 4; seed++) {
      final c = _play(4, 1, seed);
      expect(c.over, isTrue, reason: 'seed $seed did not finish');
      expect(c.state!.players[c.winner!].finished, 4);
    }
  });

  test('tokens hop cell by cell and land on the rules position', () {
    final c = LudoController(_config(2, 1, 3), AudioService(enabled: false));
    c.start();
    // Roll until a token is out, then check the drawn position settles on its cell.
    for (var i = 0; i < 20000 && !c.over; i++) {
      if (c.canRoll) c.roll();
      if (c.movable.isNotEmpty) c.moveToken(c.movable.first);
      c.tick(1 / 30);
    }
    final st = c.state!;
    for (var seat = 0; seat < st.seats; seat++) {
      for (var t = 0; t < 4; t++) {
        expect(c.tokenPos(seat, t), isNotNull);
      }
    }
    expect(st.phase, LudoPhase.gameOver);
  });

  test('dead roll keeps the dice on the roller and then passes', () {
    final c = LudoController(_config(2, 1, 11), AudioService(enabled: false));
    c.start();
    var sawHeld = false;
    for (var i = 0; i < 3000; i++) {
      if (c.canRoll) c.roll();
      if (c.diceSeat != c.turn) sawHeld = true;
      if (c.movable.isNotEmpty) c.moveToken(c.movable.first);
      c.tick(1 / 30);
    }
    expect(sawHeld, isTrue);
  });

  test('quick chat shows a bubble for the speaker', () {
    final c = LudoController(_config(2, 1, 5), AudioService(enabled: false));
    c.sayChat(2);
    expect(c.chatOf(0), 2);
    for (var i = 0; i < 200; i++) {
      c.tick(1 / 30);
    }
    expect(c.chatOf(0), isNull);
  });
}
