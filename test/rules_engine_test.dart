import 'dart:math';

import 'package:billiard_poker/game/models/match_state.dart';
import 'package:billiard_poker/game/models/player_state.dart';
import 'package:billiard_poker/game/rules/rules_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('break draw', () {
    test('king is highest, ace is always lowest', () {
      expect(card(13, c).compareTo(card(12, s)), greaterThan(0));
      expect(card(2, c).compareTo(card(1, s)), greaterThan(0));
    });

    test('same rank is decided by suit: spades > hearts > diamonds > clubs', () {
      expect(card(1, s).compareTo(card(1, h)), greaterThan(0));
      expect(card(1, h).compareTo(card(1, d)), greaterThan(0));
      expect(card(13, d).compareTo(card(13, c)), greaterThan(0));
    });

    test('players shoot in descending order of their break card', () {
      final order = RulesEngine.breakOrder([card(1, s), card(13, c), card(13, d), card(5, h)]);
      expect(order, [2, 1, 3, 0]);
    });

    test('determineBreak fixes the turn order and moves to dealing', () {
      final m = matchWith(defaultHands);
      final picks = [card(4, h), card(9, s), card(9, h), card(2, c)];
      for (var i = 0; i < 4; i++) {
        m.state.players[i].breakCard = picks[i];
      }
      m.engine.determineBreak(m.state);
      expect(m.state.turnOrder, [1, 2, 0, 3]);
      expect(m.state.phase, GamePhase.dealing);
    });
  });

  group('dealing', () {
    MatchState dealt(int seed) {
      final state = MatchState(players: [
        for (var i = 0; i < 4; i++) PlayerState(id: 'p$i', name: 'P$i', avatar: '')
      ])
        ..turnOrder = [2, 0, 3, 1];
      RulesEngine(random: Random(seed)).deal(state);
      return state;
    }

    test('7 cards each and no physical card is dealt twice', () {
      for (var seed = 0; seed < 50; seed++) {
        final state = dealt(seed);
        final all = [for (final p in state.players) ...p.hand.map((c) => c.card.id)];
        expect(state.players.every((p) => p.hand.length == 7), isTrue);
        expect(all.toSet().length, 28);
        expect(state.deck!.length, 24);
        expect(state.deck!.cards.every((c) => !all.contains(c.id)), isTrue);
      }
    });

    test('the first shot after dealing is the break', () {
      final state = dealt(3);
      expect(state.phase, GamePhase.playerTurn);
      expect(state.isBreakShot, isTrue);
      expect(state.currentIndex, 2);
    });
  });

  group('objectives', () {
    test('card to ball mapping ignores the suit', () {
      expect(card(1, s).ball, 1);
      expect(card(1, h).ball, 1);
      expect(card(11, d).ball, 11);
      expect(card(12, d).ball, 12);
      expect(card(13, c).ball, 13);
    });

    test('duplicate ranks collapse into one objective', () {
      final m = matchWith(defaultHands);
      expect(m.state.players[0].requiredBalls, {1, 7});
      expect(m.state.players[1].requiredBalls, {2, 8, 5, 7, 12, 13});
    });

    test('free balls are never objectives', () {
      final m = matchWith(defaultHands);
      for (final p in m.state.players) {
        expect(p.requiredBalls.intersection(RulesEngine.freeBalls), isEmpty);
      }
    });
  });

  group('normal turn', () {
    test('a shot needs a revealed card, except the break', () {
      final m = matchWith(defaultHands);
      expect(m.engine.canShoot(m.state), isFalse);
      m.engine.selectCard(m.state, m.state.players[0].hand[0]);
      expect(m.engine.canShoot(m.state), isTrue);
      m.state
        ..selectedCard = null
        ..isBreakShot = true;
      expect(m.engine.canShoot(m.state), isTrue);
    });

    test('cannot reveal another player\'s card or a finished objective', () {
      final m = matchWith(defaultHands);
      expect(m.engine.selectCard(m.state, m.state.players[1].hand[0]), isFalse);
      m.state.players[0].completedBalls.add(1);
      expect(m.engine.selectCard(m.state, m.state.players[0].hand[1]), isFalse);
    });

    test('pocketing the revealed ball completes it, grays ONE card, turn continues', () {
      final m = matchWith(defaultHands);
      final p = m.state.players[0];
      m.engine.selectCard(m.state, p.hand[1]);
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 1, pocketed: [1]));
      expect(r.legal, isTrue);
      expect(r.completedObjectives, [1]);
      expect(r.shownCards, [card(1, h)]);
      expect(r.turnContinues, isTrue);
      expect(p.completedBalls, {1});
      expect(p.hand.where((c) => c.completed).length, 1);
      expect(p.hand.where((c) => c.revealed).length, 1);
      expect(p.pendingBalls, {7});
      expect(m.state.currentIndex, 0);
    });

    test('a legal miss ends the turn without penalty', () {
      final m = matchWith(defaultHands);
      m.engine.selectCard(m.state, m.state.players[0].hand[0]);
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 1));
      expect(r.legal, isTrue);
      expect(r.turnContinues, isFalse);
      expect(r.penaltyCards, isEmpty);
      expect(m.state.currentIndex, 1);
    });

    test('turn order rotates 1 -> 2 -> 3 -> 4 -> 1', () {
      final m = matchWith(defaultHands);
      final seen = <int>[];
      for (var i = 0; i < 5; i++) {
        seen.add(m.state.currentIndex);
        final p = m.state.current;
        m.engine.selectCard(m.state, p.hand.first);
        m.engine.resolveShot(m.state, ShotOutcome(firstContact: p.hand.first.card.ball));
      }
      expect(seen, [0, 1, 2, 3, 0]);
    });

    test('an own ball pocketed alongside the revealed one also counts', () {
      final m = matchWith(defaultHands);
      final p = m.state.players[1];
      m.state.turnPos = 1;
      m.engine.selectCard(m.state, p.hand[0]);
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 2, pocketed: [2, 5]));
      expect(r.completedObjectives, [2, 5]);
      expect(p.hand.where((c) => c.completed).length, 2);
    });
  });

  group('penalties', () {
    test('wrong first contact: +1 penalty card and the turn ends', () {
      final m = matchWith(defaultHands);
      final p = m.state.players[0];
      m.engine.selectCard(m.state, p.hand[0]);
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 9));
      expect(r.foulType, FoulType.wrongFirstContact);
      expect(r.penaltyCards.length, 1);
      expect(r.turnContinues, isFalse);
      expect(p.hand.length, 8);
      expect(p.hand.last.isPenalty, isTrue);
      expect(m.state.currentIndex, 1);
    });

    test('touching no ball at all is penalised like a wrong first contact', () {
      final m = matchWith(defaultHands);
      m.engine.selectCard(m.state, m.state.players[0].hand[0]);
      final r = m.engine.resolveShot(m.state, const ShotOutcome());
      expect(r.foulType, FoulType.noContact);
      expect(r.penaltyCards.length, 1);
    });

    test('wrong ball pocketed: +2 penalty cards and the turn ends', () {
      final m = matchWith(defaultHands);
      final p = m.state.players[0];
      m.engine.selectCard(m.state, p.hand[0]);
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 1, pocketed: [9]));
      expect(r.foulType, FoulType.wrongBallPocketed);
      expect(r.penaltyCards.length, 2);
      expect(r.turnContinues, isFalse);
      expect(p.hand.length, 9);
      expect(m.state.currentIndex, 1);
    });

    test('nothing is completed on a foul shot', () {
      final m = matchWith(defaultHands);
      final p = m.state.players[0];
      m.engine.selectCard(m.state, p.hand[0]);
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 1, pocketed: [1, 9]));
      expect(r.completedObjectives, isEmpty);
      expect(p.completedBalls, isEmpty);
    });

    test('penalty cards become real objectives', () {
      final m = matchWith(defaultHands, penaltyPile: [card(9, s)]);
      final p = m.state.players[0];
      m.engine.selectCard(m.state, p.hand[0]);
      m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 3));
      expect(p.requiredBalls, {1, 7, 9});
      expect(p.penaltyBalls, {9});
    });

    test('a penalty card of an already completed rank re-opens that objective', () {
      final m = matchWith(defaultHands, penaltyPile: [card(1, s)]);
      final p = m.state.players[1];
      m.state.turnPos = 1;
      p.completedBalls.addAll({2, 8, 5, 7, 12, 13});
      p.completedBalls.add(1);
      m.engine.selectFreeBall(m.state, 14);
      m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 3));
      expect(p.pendingBalls, {1});
      expect(p.readyToDeclare, isFalse);
    });

    test('timeout: +1 penalty card and the turn passes on', () {
      final m = matchWith(defaultHands);
      final r = m.engine.applyTimeout(m.state);
      expect(r.foulType, FoulType.timeout);
      expect(r.penaltyCards.length, 1);
      expect(m.state.players[0].hand.length, 8);
      expect(m.state.players[0].stats.timeouts, 1);
      expect(m.state.currentIndex, 1);
    });

    test('a scratch ends the turn and gives ball in hand, no card', () {
      final m = matchWith(defaultHands);
      m.engine.selectCard(m.state, m.state.players[0].hand[0]);
      final r = m.engine.resolveShot(
          m.state, const ShotOutcome(firstContact: 1, pocketed: [1], cuePocketed: true));
      expect(r.foulType, FoulType.scratch);
      expect(r.penaltyCards, isEmpty);
      expect(r.completedObjectives, isEmpty);
      expect(m.state.ballInHand, isTrue);
      expect(m.state.currentIndex, 1);
    });

    test('penalty cards are never a card somebody already holds', () {
      final m = matchWith(defaultHands);
      for (var i = 0; i < 24; i++) {
        m.engine.applyTimeout(m.state);
      }
      final all = [for (final p in m.state.players) ...p.hand.map((c) => c.card.id)];
      expect(all.length, 52);
      expect(all.toSet().length, 52);
      // Pile exhausted: a further foul still ends the turn, just without a card.
      final before = m.state.currentIndex;
      expect(m.engine.applyTimeout(m.state).penaltyCards, isEmpty);
      expect(m.state.currentIndex, isNot(before));
    });
  });

  group('free balls', () {
    for (final ball in [14, 15]) {
      test('pocketing ball $ball gives +1 extra shot', () {
        final m = matchWith(defaultHands);
        final p = m.state.players[0];
        m.engine.selectCard(m.state, p.hand[0]);
        final r =
            m.engine.resolveShot(m.state, ShotOutcome(firstContact: 1, pocketed: [ball]));
        expect(r.legal, isTrue);
        expect(r.earnedExtraShots, 1);
        expect(r.completedObjectives, isEmpty);
        expect(r.turnContinues, isTrue);
        expect(m.state.currentIndex, 0);
        expect(p.completedBalls, isEmpty);
      });
    }

    test('a free ball can be nominated without a card', () {
      final m = matchWith(defaultHands);
      expect(m.engine.selectFreeBall(m.state, 14), isTrue);
      expect(m.engine.selectFreeBall(m.state, 9), isFalse);
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 14, pocketed: [14]));
      expect(r.legal, isTrue);
      expect(r.turnContinues, isTrue);
    });

    test('the extra shot is exactly one more shot', () {
      final m = matchWith(defaultHands);
      m.engine.selectFreeBall(m.state, 14);
      m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 14, pocketed: [14]));
      m.engine.selectCard(m.state, m.state.players[0].hand[0]);
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 1));
      expect(r.turnContinues, isFalse);
      expect(m.state.currentIndex, 1);
    });

    test('no extra shot on a foul', () {
      final m = matchWith(defaultHands);
      m.engine.selectCard(m.state, m.state.players[0].hand[0]);
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 14, pocketed: [14]));
      expect(r.foulType, FoulType.wrongFirstContact);
      expect(r.earnedExtraShots, 0);
      expect(r.turnContinues, isFalse);
    });
  });

  group('break shot', () {
    test('is open: no card, no wrong-ball penalty, own balls count', () {
      final m = matchWith(defaultHands);
      m.state.isBreakShot = true;
      final r = m.engine.resolveShot(m.state, const ShotOutcome(firstContact: 9, pocketed: [9, 7]));
      expect(r.legal, isTrue);
      expect(r.penaltyCards, isEmpty);
      expect(r.completedObjectives, [7]);
      expect(r.turnContinues, isTrue);
      expect(m.state.isBreakShot, isFalse);
    });
  });

  group('declaring', () {
    MatchState nearlyDone(({MatchState state, RulesEngine engine}) m) {
      // Player 0 needs balls 1 and 7; ball 7 is already done.
      m.state.players[0].completedBalls.add(7);
      return m.state;
    }

    test('completing every objective does NOT win immediately', () {
      final m = matchWith(defaultHands);
      final state = nearlyDone(m);
      m.engine.selectCard(state, state.players[0].hand[0]);
      final r = m.engine.resolveShot(state, const ShotOutcome(firstContact: 1, pocketed: [1]));
      expect(r.becameReadyToDeclare, isTrue);
      expect(r.turnContinues, isFalse);
      expect(state.players[0].readyToDeclare, isTrue);
      expect(state.winner, isNull);
      expect(state.phase, GamePhase.playerTurn);
      expect(state.currentIndex, 1);
      expect(m.engine.declareWinner(state, 0), isFalse);
    });

    test('the player declares on the next scheduled turn and wins', () {
      final m = matchWith(defaultHands);
      final state = nearlyDone(m);
      m.engine.selectCard(state, state.players[0].hand[0]);
      m.engine.resolveShot(state, const ShotOutcome(firstContact: 1, pocketed: [1]));
      for (var i = 1; i <= 3; i++) {
        expect(state.currentIndex, i);
        m.engine.selectCard(state, state.current.hand.first);
        m.engine.resolveShot(state, ShotOutcome(firstContact: state.targetBall));
      }
      expect(state.currentIndex, 0);
      expect(state.phase, GamePhase.declarePhase);
      expect(m.engine.declareWinner(state, 2), isFalse);
      expect(m.engine.declareWinner(state, 0), isTrue);
      expect(state.winner, 0);
      expect(state.phase, GamePhase.gameOver);
    });

    test('race to declare: whoever reaches their turn first wins', () {
      final m = matchWith(defaultHands);
      final state = nearlyDone(m);
      // Player 0 finishes and waits.
      m.engine.selectCard(state, state.players[0].hand[0]);
      m.engine.resolveShot(state, const ShotOutcome(firstContact: 1, pocketed: [1]));
      // Player 1 misses.
      m.engine.selectCard(state, state.players[1].hand[0]);
      m.engine.resolveShot(state, const ShotOutcome(firstContact: 2));
      // Player 2 had finished earlier in the round, so their turn starts in
      // the declare phase before player 0's turn comes round.
      state.players[2].completedBalls.addAll({3, 4, 6, 9, 10});
      state
        ..turnPos = 1
        ..phase = GamePhase.playerTurn;
      m.engine.selectCard(state, state.players[1].hand[1]);
      m.engine.resolveShot(state, const ShotOutcome(firstContact: 8));
      expect(state.currentIndex, 2);
      expect(state.phase, GamePhase.declarePhase);
      expect(m.engine.declareWinner(state, 0), isFalse);
      expect(m.engine.declareWinner(state, 2), isTrue);
      expect(state.winner, 2);
      // Player 0 was ready first but can no longer win.
      expect(m.engine.declareWinner(state, 0), isFalse);
      expect(state.winner, 2);
    });

    test('timing out in the declare phase costs a card and the win', () {
      final m = matchWith(defaultHands);
      final state = nearlyDone(m);
      state.players[0].completedBalls.add(1);
      state.phase = GamePhase.declarePhase;
      final r = m.engine.applyTimeout(state);
      expect(r.penaltyCards.length, 1);
      expect(state.players[0].readyToDeclare, isFalse);
      expect(state.winner, isNull);
      expect(state.currentIndex, 1);
    });

    test('nobody can declare twice or after the game is over', () {
      final m = matchWith(defaultHands);
      final state = nearlyDone(m);
      state.players[0].completedBalls.add(1);
      state.phase = GamePhase.declarePhase;
      expect(m.engine.declareWinner(state, 0), isTrue);
      expect(m.engine.declareWinner(state, 0), isFalse);
    });
  });
}
