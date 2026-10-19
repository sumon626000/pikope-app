import 'dart:math';

import 'ludo_rules.dart';

/// A simple Ludo opponent: capture if it can, else bring a token home, else
/// free a token on a six, else advance the one nearest home. Good enough for
/// practice and to stand in for an absent player.
class LudoBot {
  LudoBot([Random? rng]) : _rng = rng ?? Random();

  final Random _rng;

  /// Picks one of [movable] to move, given the current [die].
  int chooseToken(LudoState s, int seat, int die, List<int> movable) {
    final p = s.players[seat];
    int? capture;
    int? finish;
    int? leaveBase;
    var bestAdvance = -1, advanceToken = movable.first;
    for (final t in movable) {
      final from = p.tokens[t];
      final to = from == -1 ? 0 : from + die;
      if (to == LudoRules.homeStep) {
        finish ??= t;
      }
      if (from == -1) {
        leaveBase ??= t;
      }
      if (LudoRules.onRing(to)) {
        final cell = LudoRules.ringCell(p.colour, to);
        if (!LudoRules.safeCells.contains(cell)) {
          for (var os = 0; os < s.seats; os++) {
            if (os == seat || s.players[os].out) continue;
            for (var ot = 0; ot < 4; ot++) {
              final ostep = s.players[os].tokens[ot];
              if (LudoRules.onRing(ostep) && LudoRules.ringCell(s.colourOf(os), ostep) == cell) {
                capture ??= t;
              }
            }
          }
        }
      }
      if (to > bestAdvance) {
        bestAdvance = to;
        advanceToken = t;
      }
    }
    // Priorities, with a little randomness between freeing a token and pushing on.
    return capture ?? finish ?? (die == 6 && leaveBase != null && _rng.nextBool() ? leaveBase : advanceToken);
  }
}
