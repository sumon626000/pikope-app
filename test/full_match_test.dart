import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/features/game/game_controller.dart';
import 'package:billiard_poker/game/models/match_state.dart';
import 'package:billiard_poker/game/physics/table_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

MatchConfig botMatch(int seed, {double skill = 0.9}) => MatchConfig(
      seed: seed,
      shotSeconds: 30,
      seats: [
        for (var i = 0; i < 4; i++)
          SeatConfig(name: 'BOT ${i + 1}', avatar: '', isBot: true, botSkill: skill),
      ],
    );

/// End-to-end: 4-player room -> break draw -> deal -> real physics shots ->
/// objectives / penalties -> declaration -> winner, with no UI involved.
void main() {
  for (final seed in [1, 2, 3]) {
    test('a full 4-player match plays through to a declared winner (seed $seed)', () {
      final c = GameController(botMatch(seed), AudioService(enabled: false));
      final phases = <GamePhase>{};
      var sawPenalty = false;
      var sawReadyWithoutWin = false;
      var ticks = 0;
      const maxTicks = 400000;

      while (c.state.phase != GamePhase.gameOver && ticks++ < maxTicks) {
        c.tick(0.05);
        phases.add(c.state.phase);
        final s = c.state;
        if (s.deck != null) {
          final ids = [for (final p in s.players) ...p.hand.map((h) => h.card.id)];
          expect(ids.toSet().length, ids.length, reason: 'duplicate physical card');
          expect(ids.length + s.deck!.length, 52);
        }
        sawPenalty |= s.players.any((p) => p.hand.any((h) => h.isPenalty));
        sawReadyWithoutWin |= s.winner == null && s.players.any((p) => p.readyToDeclare);
        if (s.phase == GamePhase.playerTurn && !c.dealing) {
          // Balls always come back, so all 16 are on the cloth between shots.
          expect(c.world.balls.where((b) => !b.pocketed).length, 16);
          for (final b in c.world.balls) {
            expect(TableGeometry.insidePlayfield(b.pos, margin: 0), isTrue);
          }
        }
      }

      expect(c.state.phase, GamePhase.gameOver, reason: 'match did not finish');
      final winner = c.players[c.state.winner!];
      expect(winner.pendingBalls, isEmpty);
      expect(winner.readyToDeclare, isTrue);
      expect(sawReadyWithoutWin, isTrue, reason: 'winner must wait for the next turn');
      expect(
          phases,
          containsAll([
            GamePhase.determiningBreak,
            GamePhase.dealing,
            GamePhase.playerTurn,
            GamePhase.shooting,
            GamePhase.declarePhase,
          ]));
      expect(c.state.turnOrder.toSet(), {0, 1, 2, 3});
      expect(c.players.every((p) => p.hand.length >= 7), isTrue);
      // ignore: avoid_print
      print('seed $seed: winner ${winner.name} after ${c.state.shotNumber} shots, '
          'penalties seen: $sawPenalty');
      c.dispose();
    });
  }

  test('an idle human times out, takes a penalty card and loses the turn', () {
    final config = MatchConfig(seed: 5, shotSeconds: 20, seats: [
      const SeatConfig(name: 'YOU', avatar: ''),
      for (var i = 0; i < 3; i++) SeatConfig(name: 'BOT $i', avatar: '', isBot: true),
    ]);
    final c = GameController(config, AudioService(enabled: false));
    c.pickBreakCard(0);
    var ticks = 0;
    while (c.players[0].stats.timeouts == 0 && ticks++ < 200000) {
      c.tick(0.05);
    }
    expect(c.players[0].stats.timeouts, 1);
    expect(c.players[0].hand.length, 8);
    expect(c.players[0].hand.last.isPenalty, isTrue);
    c.dispose();
  });

  test('rematch starts a clean match', () {
    final c = GameController(botMatch(1), AudioService(enabled: false));
    for (var i = 0; i < 400000 && c.state.phase != GamePhase.gameOver; i++) {
      c.tick(0.05);
    }
    c.rematch();
    expect(c.state.phase, GamePhase.determiningBreak);
    expect(c.state.winner, isNull);
    expect(c.players.every((p) => p.hand.isEmpty && p.completedBalls.isEmpty), isTrue);
    c.dispose();
  });
}
