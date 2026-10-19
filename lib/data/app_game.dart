import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/pool/pool_rules.dart';

/// The four games in the app.
enum AppGame { poker, eightBall, nineBall, tenBall }

extension AppGameInfo on AppGame {
  String get title => switch (this) {
        AppGame.poker => 'BILLIARD POKER',
        AppGame.eightBall => '8-BALL',
        AppGame.nineBall => '9-BALL',
        AppGame.tenBall => '10-BALL',
      };

  String get tagline => switch (this) {
        AppGame.poker => '4 PLAYERS - CARDS PICK YOUR BALLS',
        AppGame.eightBall => '1 V 1 - SOLIDS VS STRIPES',
        AppGame.nineBall => '1 V 1 - LOWEST FIRST, 9 WINS',
        AppGame.tenBall => '1 V 1 - LOWEST FIRST, 10 WINS',
      };

  int get players => this == AppGame.poker ? 4 : 2;

  /// Ball shown on the game's tile (null: the poker tile shows a card).
  int? get iconBall => switch (this) {
        AppGame.poker => null,
        AppGame.eightBall => 8,
        AppGame.nineBall => 9,
        AppGame.tenBall => 10,
      };

  /// Name of the game in the backend API.
  String get apiName => switch (this) {
        AppGame.poker => 'poker',
        AppGame.eightBall => 'eight',
        AppGame.nineBall => 'nine',
        AppGame.tenBall => 'ten',
      };

  static AppGame fromApi(String name) => AppGame.values.firstWhere((g) => g.apiName == name);

  /// Title for any game key the backend uses, including the games that are
  /// not [AppGame]s (Ludo, Carrom). Unknown keys are shown upper-cased.
  /// Prefer [l10n.gameTitleKey] when showing text in the UI.
  static String titleOf(String key) {
    if (key.startsWith('ludo')) return key == 'ludo4' ? 'LUDO (4 PLAYERS)' : 'LUDO';
    if (key == 'carrom') return 'CARROM';
    for (final g in AppGame.values) {
      if (g.apiName == key) return g.title;
    }
    return key.toUpperCase();
  }

  PoolGame? get poolGame => switch (this) {
        AppGame.poker => null,
        AppGame.eightBall => PoolGame.eightBall,
        AppGame.nineBall => PoolGame.nineBall,
        AppGame.tenBall => PoolGame.tenBall,
      };
}

/// Game picked on the home screen.
final selectedGameProvider = StateProvider<AppGame>((ref) => AppGame.poker);
