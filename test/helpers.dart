import 'dart:math';

import 'package:billiard_poker/game/models/match_state.dart';
import 'package:billiard_poker/game/models/player_state.dart';
import 'package:billiard_poker/game/models/playing_card.dart';
import 'package:billiard_poker/game/rules/rules_engine.dart';

const s = Suit.spades, h = Suit.hearts, d = Suit.diamonds, c = Suit.clubs;

PlayingCard card(int rank, Suit suit) => PlayingCard(rank, suit);

/// A match in the normal-turn phase (break already taken) with fixed hands.
/// Turn order is player 0, 1, 2, 3. The penalty pile is every card not held.
({MatchState state, RulesEngine engine}) matchWith(List<List<PlayingCard>> hands,
    {List<PlayingCard>? penaltyPile}) {
  final players = [
    for (var i = 0; i < 4; i++) PlayerState(id: 'p$i', name: 'P$i', avatar: '')
  ];
  for (var i = 0; i < 4; i++) {
    players[i].hand.addAll(hands[i].map(HandCard.new));
  }
  final held = {for (final hand in hands) ...hand};
  final state = MatchState(players: players)
    ..turnOrder = [0, 1, 2, 3]
    ..deck = Deck.of(penaltyPile ??
        [
          for (var i = 0; i < 52; i++)
            if (!held.contains(PlayingCard.fromId(i))) PlayingCard.fromId(i)
        ])
    ..isBreakShot = false
    ..phase = GamePhase.playerTurn;
  return (state: state, engine: RulesEngine(random: Random(1)));
}

final defaultHands = [
  [card(1, s), card(1, h), card(1, d), card(1, c), card(7, h), card(7, d), card(7, c)],
  [card(2, s), card(8, h), card(5, d), card(5, c), card(7, s), card(12, d), card(13, c)],
  [card(3, s), card(3, h), card(4, d), card(4, c), card(6, s), card(9, d), card(10, c)],
  [card(11, s), card(11, h), card(12, s), card(12, c), card(13, s), card(9, h), card(10, h)],
];
