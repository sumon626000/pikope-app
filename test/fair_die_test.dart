import 'dart:math';

import 'package:billiard_poker/game/ludo/fair_die.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FairDie.roll returns 1 through 6 only', () {
    final rng = Random(42);
    for (var i = 0; i < 500; i++) {
      final v = FairDie.roll(rng);
      expect(v, inInclusiveRange(1, 6));
    }
  });

  test('FairDie is roughly uniform over many rolls', () {
    final rng = FairDie.outcomeRandom(seed: 99);
    final counts = List.filled(7, 0);
    const n = 6000;
    for (var i = 0; i < n; i++) {
      counts[FairDie.roll(rng)]++;
    }
    for (var face = 1; face <= 6; face++) {
      expect(counts[face], inInclusiveRange(850, 1150), reason: 'face $face');
    }
  });
}
