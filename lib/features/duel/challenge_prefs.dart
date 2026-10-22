import '../../core/app_state.dart';

/// Pool (billiard variants), Ludo, or Carrom — how incoming challenges are grouped.
enum ChallengeFamily { pool, ludo, carrom }

ChallengeFamily? challengeFamilyForGame(String game) {
  if (game.startsWith('ludo')) return ChallengeFamily.ludo;
  if (game == 'carrom') return ChallengeFamily.carrom;
  if (game == 'billiard' || game == 'eight' || game == 'nine' || game == 'ten' || game == 'poker') {
    return ChallengeFamily.pool;
  }
  return null;
}

bool challengeFamilyEnabled(AppSettings s, ChallengeFamily family) => switch (family) {
      ChallengeFamily.pool => s.challengePoolEnabled,
      ChallengeFamily.ludo => s.challengeLudoEnabled,
      ChallengeFamily.carrom => s.challengeCarromEnabled,
    };

/// Whether this device should show / accept an incoming invite for [game].
bool acceptsIncomingChallenge(AppSettings s, String game) {
  final family = challengeFamilyForGame(game);
  if (family == null) return false;
  return challengeFamilyEnabled(s, family);
}

bool anyChallengeReceiveEnabled(AppSettings s) =>
    s.challengePoolEnabled || s.challengeLudoEnabled || s.challengeCarromEnabled;
