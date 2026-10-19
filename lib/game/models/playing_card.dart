import 'dart:math';

/// Suits ordered by break-draw strength: clubs < diamonds < hearts < spades.
enum Suit { clubs, diamonds, hearts, spades }

/// One of the 52 physical cards. [rank] is 1 (Ace, always lowest) to 13 (King).
class PlayingCard implements Comparable<PlayingCard> {
  const PlayingCard(this.rank, this.suit) : assert(rank >= 1 && rank <= 13);

  final int rank;
  final Suit suit;

  /// Unique identity 0..51 - no two players may hold the same id.
  int get id => (rank - 1) * 4 + suit.index;

  factory PlayingCard.fromId(int id) =>
      PlayingCard(id ~/ 4 + 1, Suit.values[id % 4]);

  /// Ball number this card stands for (Ace -> 1 ... King -> 13), suit-independent.
  int get ball => rank;

  String get rankLabel => switch (rank) {
        1 => 'A',
        11 => 'J',
        12 => 'Q',
        13 => 'K',
        _ => '$rank',
      };

  String get suitSymbol => switch (suit) {
        Suit.spades => '♠',
        Suit.hearts => '♥',
        Suit.diamonds => '♦',
        Suit.clubs => '♣',
      };

  String get label => '$rankLabel$suitSymbol';

  /// Suit spelled out, for fonts without suit glyphs.
  String get spokenName => '$rankLabel OF ${suit.name.toUpperCase()}';

  /// Break-draw ordering: rank first (K high, A low), then suit.
  @override
  int compareTo(PlayingCard other) =>
      rank != other.rank ? rank - other.rank : suit.index - other.suit.index;

  @override
  bool operator ==(Object other) => other is PlayingCard && other.id == id;

  @override
  int get hashCode => id;

  @override
  String toString() => label;
}

class Deck {
  Deck.shuffled(Random random)
      : cards = [for (var i = 0; i < 52; i++) PlayingCard.fromId(i)]
          ..shuffle(random);

  Deck.of(this.cards);

  final List<PlayingCard> cards;

  bool get isEmpty => cards.isEmpty;
  int get length => cards.length;

  PlayingCard draw() => cards.removeLast();
}

/// A card as held by a player. Display state (completed/revealed) is tracked
/// per card and is deliberately separate from the objective state.
class HandCard {
  HandCard(this.card, {this.isPenalty = false, int? key, this.hidden = false}) : key = key ?? card.id;

  /// An opponent's card in an online match: the server has not told this
  /// device what it is, so [card] is only a stand-in.
  HandCard.unknown(int key, {bool isPenalty = false})
      : this(const PlayingCard(1, Suit.clubs), isPenalty: isPenalty, key: key, hidden: true);

  final PlayingCard card;
  final bool isPenalty;

  /// Stable identity within a match (the card id offline, the server's
  /// hand-slot key online, where hidden cards have no id).
  final int key;
  final bool hidden;

  /// Grayed out: this card was used to account for a pocketed ball.
  bool completed = false;

  /// Face-up for every player (shown after its ball was pocketed).
  bool revealed = false;
}
