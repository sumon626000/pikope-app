import 'dart:math';

/// Uniform 1–6 rolls for Ludo. Online matches use the server die only;
/// offline/practice uses [outcomeRandom] so humans and bots share the same odds.
abstract final class FairDie {
  static int roll(Random rng) => rng.nextInt(6) + 1;

  /// Real play: cryptographically fair. Tests: pass a fixed [seed].
  static Random outcomeRandom({int? seed}) =>
      seed == null ? Random.secure() : Random(seed);
}
