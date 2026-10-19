import 'dart:math';

import '../models/match_state.dart';
import '../models/player_state.dart';
import '../models/playing_card.dart';

/// Deterministic Billiard Poker rules. Pure Dart: no Flutter, no I/O, so the
/// same logic can run on a trusted backend. All randomness comes from the
/// injected [Random].
class RulesEngine {
  RulesEngine({Random? random}) : random = random ?? Random.secure();

  final Random random;

  static const int cardsPerPlayer = 7;
  static const int playerCount = 4;
  static const Set<int> freeBalls = {14, 15};
  static const int breakSpreadSize = 30;

  // ---------------------------------------------------------------- break

  /// Face-down spread the players pick their break card from.
  List<PlayingCard> newBreakSpread() =>
      Deck.shuffled(random).cards.take(breakSpreadSize).toList();

  /// Player indices sorted highest break card first (K high, A low, then
  /// spades > hearts > diamonds > clubs).
  static List<int> breakOrder(List<PlayingCard> cards) {
    final order = [for (var i = 0; i < cards.length; i++) i];
    order.sort((a, b) => cards[b].compareTo(cards[a]));
    return order;
  }

  void startBreakDraw(MatchState s) {
    for (final p in s.players) {
      p.breakCard = null;
    }
    s.phase = GamePhase.determiningBreak;
  }

  /// Fixes the turn order once every player holds a break card.
  void determineBreak(MatchState s) {
    assert(s.players.every((p) => p.breakCard != null));
    s.turnOrder = breakOrder([for (final p in s.players) p.breakCard!]);
    s.turnPos = 0;
    s.phase = GamePhase.dealing;
  }

  // ----------------------------------------------------------------- deal

  /// Deals 7 cards each from a fresh 52-card deck; the rest is the penalty pile.
  void deal(MatchState s) {
    final deck = Deck.shuffled(random);
    for (final p in s.players) {
      p.hand.clear();
      p.completedBalls.clear();
    }
    for (var round = 0; round < cardsPerPlayer; round++) {
      for (final idx in s.turnOrder) {
        s.players[idx].hand.add(HandCard(deck.draw()));
      }
    }
    s
      ..deck = deck
      ..isBreakShot = true
      ..ballInHand = true
      ..extraShots = 0
      ..selectedCard = null
      ..selectedFreeBall = null
      ..shotNumber = 0
      ..winner = null
      ..lastResult = null
      ..phase = GamePhase.playerTurn;
  }

  // ------------------------------------------------------------ selection

  /// Reveal the card for the ball about to be played.
  bool selectCard(MatchState s, HandCard card) {
    if (s.phase != GamePhase.playerTurn) return false;
    final p = s.current;
    if (!p.hand.contains(card) || card.completed) return false;
    if (!p.pendingBalls.contains(card.card.ball)) return false;
    s
      ..selectedCard = card
      ..selectedFreeBall = null;
    return true;
  }

  /// Nominate free ball 14 or 15 (no card needed - they belong to everyone).
  bool selectFreeBall(MatchState s, int ball) {
    if (s.phase != GamePhase.playerTurn || !freeBalls.contains(ball)) return false;
    s
      ..selectedCard = null
      ..selectedFreeBall = ball;
    return true;
  }

  /// The break shot is open; every other shot needs a revealed target.
  bool canShoot(MatchState s) =>
      s.phase == GamePhase.playerTurn && (s.isBreakShot || s.targetBall != null);

  // ----------------------------------------------------------------- shot

  ShotResult resolveShot(MatchState s, ShotOutcome o) {
    assert(s.phase == GamePhase.playerTurn || s.phase == GamePhase.shooting);
    final playerIndex = s.currentIndex;
    final p = s.current;
    final wasBreak = s.isBreakShot;
    final selected = s.selectedCard;
    final target = s.targetBall;
    final required = p.requiredBalls;

    p.stats.shots++;
    s.shotNumber++;

    var foul = FoulType.none;
    var penaltyCount = 0;
    if (!wasBreak) {
      if (o.firstContact == null) {
        foul = FoulType.noContact;
        penaltyCount = 1;
      } else if (o.firstContact != target) {
        foul = FoulType.wrongFirstContact;
        penaltyCount = 1;
      }
      final wrongBall = o.pocketed.any((b) => !freeBalls.contains(b) && !required.contains(b));
      if (wrongBall) {
        foul = FoulType.wrongBallPocketed;
        penaltyCount = 2;
      }
    }
    if (o.cuePocketed && foul == FoulType.none) foul = FoulType.scratch;

    final completed = <int>[];
    final shown = <PlayingCard>[];
    var earnedExtra = 0;
    var turnContinues = false;
    var becameReady = false;
    final penalties = <PlayingCard>[];

    if (foul == FoulType.none) {
      for (final b in o.pocketed) {
        if (freeBalls.contains(b)) {
          earnedExtra++;
        } else if (p.pendingBalls.contains(b)) {
          completed.add(b);
          shown.add(_completeObjective(p, b, selected));
        }
      }
      p.stats.ballsCompleted += completed.length;
      p.stats.extraShots += earnedExtra;
      s.extraShots += earnedExtra;
      if (p.readyToDeclare) {
        becameReady = true;
      } else if (completed.isNotEmpty) {
        turnContinues = true;
      } else if (s.extraShots > 0) {
        s.extraShots--;
        turnContinues = true;
      }
    } else {
      p.stats.fouls++;
      penalties.addAll(_drawPenalties(s, p, penaltyCount));
    }

    s
      ..isBreakShot = false
      ..selectedCard = null
      ..selectedFreeBall = null
      ..ballInHand = o.cuePocketed;
    if (turnContinues) {
      s.phase = GamePhase.playerTurn;
    } else {
      _advanceTurn(s);
    }

    return s.lastResult = ShotResult(
      playerIndex: playerIndex,
      selectedCard: selected?.card,
      selectedBall: target,
      firstContactBall: o.firstContact,
      pocketedBalls: List.unmodifiable(o.pocketed),
      cueBallPocketed: o.cuePocketed,
      railContact: o.railContact,
      legal: foul == FoulType.none,
      foulType: foul,
      completedObjectives: completed,
      shownCards: shown,
      earnedExtraShots: earnedExtra,
      penaltyCards: penalties,
      turnContinues: turnContinues,
      nextPlayer: s.currentIndex,
      becameReadyToDeclare: becameReady,
      wasBreak: wasBreak,
    );
  }

  /// Shot clock ran out: one penalty card and the turn passes on.
  ShotResult applyTimeout(MatchState s) {
    assert(s.phase == GamePhase.playerTurn || s.phase == GamePhase.declarePhase);
    final playerIndex = s.currentIndex;
    final p = s.current;
    p.stats
      ..timeouts += 1
      ..fouls += 1;
    final penalties = _drawPenalties(s, p, 1);
    final selected = s.selectedCard?.card;
    final target = s.targetBall;
    s
      ..selectedCard = null
      ..selectedFreeBall = null;
    _advanceTurn(s);
    return s.lastResult = ShotResult(
      playerIndex: playerIndex,
      selectedCard: selected,
      selectedBall: target,
      firstContactBall: null,
      pocketedBalls: const [],
      cueBallPocketed: false,
      railContact: false,
      legal: false,
      foulType: FoulType.timeout,
      completedObjectives: const [],
      shownCards: const [],
      earnedExtraShots: 0,
      penaltyCards: penalties,
      turnContinues: false,
      nextPlayer: s.currentIndex,
      becameReadyToDeclare: false,
      wasBreak: false,
    );
  }

  /// Only the player whose scheduled turn it is, with every objective done,
  /// can win - and only if nobody has won before.
  bool declareWinner(MatchState s, int playerIndex) {
    if (s.winner != null || s.phase != GamePhase.declarePhase) return false;
    if (s.currentIndex != playerIndex || !s.current.readyToDeclare) return false;
    s
      ..winner = playerIndex
      ..phase = GamePhase.gameOver;
    return true;
  }

  // -------------------------------------------------------------- helpers

  /// Grays out exactly one card for [ball]: the revealed one if it matches,
  /// otherwise a random equivalent card.
  PlayingCard _completeObjective(PlayerState p, int ball, HandCard? selected) {
    p.completedBalls.add(ball);
    final HandCard card;
    if (selected != null && selected.card.ball == ball && !selected.completed) {
      card = selected;
    } else {
      final options = p.hand.where((c) => c.card.ball == ball && !c.completed).toList();
      card = options[random.nextInt(options.length)];
    }
    card
      ..completed = true
      ..revealed = true;
    return card.card;
  }

  /// Penalty cards are real objectives: a rank the player had already
  /// completed is re-opened and must be pocketed again.
  List<PlayingCard> _drawPenalties(MatchState s, PlayerState p, int count) {
    final drawn = <PlayingCard>[];
    final deck = s.deck;
    for (var i = 0; i < count && deck != null && !deck.isEmpty; i++) {
      final card = deck.draw();
      p.hand.add(HandCard(card, isPenalty: true));
      p.completedBalls.remove(card.ball);
      drawn.add(card);
    }
    p.stats.penaltyCards += drawn.length;
    return drawn;
  }

  void _advanceTurn(MatchState s) {
    s.turnPos = (s.turnPos + 1) % s.turnOrder.length;
    s.extraShots = 0;
    s.phase = s.current.readyToDeclare ? GamePhase.declarePhase : GamePhase.playerTurn;
  }
}
