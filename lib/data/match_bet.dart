/// What a match is played for (decided by the server).
class MatchBet {
  const MatchBet({this.mode = 'friendly', this.stake = 0, this.prize = 0, this.multiplier, this.wheel = const []});

  /// "billiard" (staked 1v1), "poker" (staked 4 players) or "friendly".
  final String mode;
  final int stake;

  /// Coins the winner receives.
  final int prize;

  /// Billiard Poker: the jackpot multiplier drawn for this match.
  final int? multiplier;

  /// Billiard Poker: every prize the jackpot wheel shows (one per slice).
  final List<int> wheel;

  bool get staked => stake > 0;

  factory MatchBet.fromJson(Map<String, dynamic>? j) => j == null
      ? const MatchBet()
      : MatchBet(
          mode: j['mode'] as String? ?? 'friendly',
          stake: j['stake'] as int? ?? 0,
          prize: j['prize'] as int? ?? 0,
          multiplier: j['multiplier'] as int?,
          wheel: (j['wheel'] as List?)?.cast<int>() ?? const [],
        );
}
