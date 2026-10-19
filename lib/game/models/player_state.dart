import 'playing_card.dart';

class PlayerStats {
  int shots = 0;
  int ballsCompleted = 0;
  int fouls = 0;
  int penaltyCards = 0;
  int timeouts = 0;
  int extraShots = 0;
}

class PlayerState {
  PlayerState({
    required this.id,
    required this.name,
    required this.avatar,
    this.isBot = false,
    this.botSkill = 0.6,
  });

  final String id;
  final String name;
  final String avatar;
  final bool isBot;

  /// 0 (sloppy) .. 1 (sharp). Only used for bots.
  final double botSkill;

  PlayingCard? breakCard;
  final List<HandCard> hand = [];

  /// Objective state: balls this player has legally pocketed and that still
  /// count. Kept apart from the per-card gray-out state.
  final Set<int> completedBalls = {};
  final PlayerStats stats = PlayerStats();

  /// Unique balls required by the cards held (duplicates collapse).
  Set<int> get requiredBalls => {for (final c in hand) c.card.ball};

  Set<int> get pendingBalls => requiredBalls.difference(completedBalls);

  /// Balls that entered the objective set only through penalty cards.
  Set<int> get penaltyBalls {
    final dealt = {
      for (final c in hand)
        if (!c.isPenalty) c.card.ball
    };
    return {
      for (final c in hand)
        if (c.isPenalty && !dealt.contains(c.card.ball)) c.card.ball
    };
  }

  bool get hasCards => hand.isNotEmpty;

  /// Online: what the server reports for a player whose hand is hidden.
  bool? remoteReady;
  int? remotePending;

  /// All objectives done - may declare on the next scheduled turn.
  bool get readyToDeclare => remoteReady ?? (hasCards && pendingBalls.isEmpty);

  int get pendingCount => remotePending ?? pendingBalls.length;
}
