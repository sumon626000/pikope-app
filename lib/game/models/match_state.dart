import 'player_state.dart';
import 'playing_card.dart';

enum GamePhase {
  loading,
  determiningBreak,
  dealing,
  playerTurn,
  shooting,
  resolvingShot,
  declarePhase,
  gameOver,
}

enum FoulType { none, wrongFirstContact, noContact, wrongBallPocketed, scratch, timeout }

extension FoulTypeLabel on FoulType {
  String get label => switch (this) {
        FoulType.none => '',
        FoulType.wrongFirstContact => 'WRONG FIRST CONTACT',
        FoulType.noContact => 'NO BALL CONTACTED',
        FoulType.wrongBallPocketed => 'WRONG BALL POCKETED',
        FoulType.scratch => 'SCRATCH',
        FoulType.timeout => 'TIME OUT',
      };
}

/// Raw facts reported by the physics simulation for one shot.
class ShotOutcome {
  const ShotOutcome({
    this.firstContact,
    this.pocketed = const [],
    this.cuePocketed = false,
    this.railContact = false,
    this.railAfterContact = false,
    this.objectBallsToRail = 0,
    this.pocketOf = const {},
  });

  final int? firstContact;
  final List<int> pocketed;
  final bool cuePocketed;
  final bool railContact;

  /// Some ball touched a cushion after the cue ball's first contact.
  final bool railAfterContact;

  /// How many different object balls reached a cushion (legal-break test).
  final int objectBallsToRail;

  /// Pocket index each pocketed object ball dropped into.
  final Map<int, int> pocketOf;
}

/// Structured verdict produced by the rules engine for one shot.
class ShotResult {
  ShotResult({
    required this.playerIndex,
    required this.selectedCard,
    required this.selectedBall,
    required this.firstContactBall,
    required this.pocketedBalls,
    required this.cueBallPocketed,
    required this.railContact,
    required this.legal,
    required this.foulType,
    required this.completedObjectives,
    required this.shownCards,
    required this.earnedExtraShots,
    required this.penaltyCards,
    required this.turnContinues,
    required this.nextPlayer,
    required this.becameReadyToDeclare,
    required this.wasBreak,
  });

  final int playerIndex;
  final PlayingCard? selectedCard;
  final int? selectedBall;
  final int? firstContactBall;
  final List<int> pocketedBalls;
  final bool cueBallPocketed;
  final bool railContact;
  final bool legal;
  final FoulType foulType;
  final List<int> completedObjectives;
  final List<PlayingCard> shownCards;
  final int earnedExtraShots;
  final List<PlayingCard> penaltyCards;
  final bool turnContinues;
  final int nextPlayer;
  final bool becameReadyToDeclare;
  final bool wasBreak;
}

/// Authoritative match state. Mutated only through [RulesEngine].
class MatchState {
  MatchState({required this.players});

  /// Players in seat order as they joined.
  final List<PlayerState> players;

  GamePhase phase = GamePhase.loading;

  /// Player indices in shooting order (break-draw winner first). Seats are
  /// laid out clockwise in this order.
  List<int> turnOrder = [];
  int turnPos = 0;

  /// Undealt cards - the penalty pile.
  Deck? deck;

  bool isBreakShot = true;
  bool ballInHand = false;

  /// Banked extra shots (from free balls 14/15) for the current turn.
  int extraShots = 0;

  /// Card revealed for the upcoming shot, or a nominated free ball.
  HandCard? selectedCard;
  int? selectedFreeBall;

  int shotNumber = 0;
  int? winner;
  ShotResult? lastResult;

  int get currentIndex => turnOrder.isEmpty ? 0 : turnOrder[turnPos];
  PlayerState get current => players[currentIndex];

  int? get targetBall => selectedCard?.card.ball ?? selectedFreeBall;
}
