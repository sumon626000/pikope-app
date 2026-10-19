import 'carrom_physics.dart';

/// Carrom in the "disc pool" style of Carrom Pool: two players, nine pieces
/// each (white vs black) and the red queen.
///
/// - Pocketing one of your own pieces keeps your turn.
/// - Pocketing an opponent's piece counts for them.
/// - The queen must be covered: pocket one of your own pieces in the same or
///   the very next stroke, or she comes back to the centre.
/// - Your last piece may not drop while the queen is still unowned: it comes
///   back to the centre.
/// - Pocketing the striker is a foul: everything that dropped in that stroke
///   comes back, plus one piece you had already pocketed.
/// - First to pocket all nine of their pieces wins.
///
/// backend/src/Game/CarromEngine.php mirrors this file line for line.
enum CarromPhase { playerTurn, gameOver }

class CarromPlayer {
  CarromPlayer({required this.name, required this.avatar, required this.colour, this.isBot = false, this.cue = 'classic'});

  final String name;
  final String avatar;
  final String cue;
  final bool isBot;

  /// 0 white (discs 1..9), 1 black (discs 10..18).
  final int colour;
  int pocketed = 0;
  bool hasQueen = false;
  int missed = 0;
  bool out = false;
}

class CarromShotResult {
  const CarromShotResult({
    required this.player,
    required this.foul,
    required this.pocketed,
    required this.returned,
    required this.penalty,
    required this.queenCovered,
    required this.queenReturned,
    required this.queenPending,
    required this.lastPieceReturned,
    required this.extraTurn,
    required this.nextPlayer,
    required this.winner,
    required this.reason,
    this.timeout = false,
  });

  final int player;
  final bool foul;

  /// Discs that dropped in this stroke (before any were returned).
  final List<int> pocketed;

  /// Discs put back on the centre (foul, uncovered queen, early last piece).
  final List<int> returned;

  /// Piece already pocketed earlier that came back as the foul penalty.
  final int? penalty;
  final bool queenCovered;
  final bool queenReturned;

  /// The queen dropped and still needs covering next stroke.
  final bool queenPending;
  final bool lastPieceReturned;
  final bool extraTurn;
  final int nextPlayer;
  final int? winner;
  final String? reason;
  final bool timeout;

  factory CarromShotResult.fromJson(Map<String, dynamic> r) => CarromShotResult(
        player: r['player'] as int,
        foul: r['foul'] as bool,
        pocketed: (r['pocketed'] as List).cast<int>(),
        returned: (r['returned'] as List).cast<int>(),
        penalty: r['penalty'] as int?,
        queenCovered: r['queenCovered'] as bool,
        queenReturned: r['queenReturned'] as bool,
        queenPending: r['queenPending'] as bool,
        lastPieceReturned: r['lastPieceReturned'] as bool,
        extraTurn: r['extraTurn'] as bool,
        nextPlayer: r['nextPlayer'] as int,
        winner: r['winner'] as int?,
        reason: r['reason'] as String?,
        timeout: r['timeout'] as bool? ?? false,
      );
}

class CarromState {
  CarromState({required this.players, required this.turn, this.shotSeconds = 30});

  final List<CarromPlayer> players;
  int turn;
  CarromPhase phase = CarromPhase.playerTurn;
  int shotNumber = 0;

  /// Seat that pocketed the queen and must cover her this stroke, if any.
  int? queenPending;
  int? winner;
  String? winReason;
  int shotSeconds;
  CarromShotResult? lastResult;

  CarromPlayer get current => players[turn];
  int other(int seat) => 1 - seat;

  /// Applies the server's rule state (not the discs: those go to the world).
  void applyJson(Map<String, dynamic> v) {
    final ps = (v['players'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < players.length && i < ps.length; i++) {
      players[i]
        ..pocketed = ps[i]['pocketed'] as int
        ..hasQueen = ps[i]['hasQueen'] as bool
        ..missed = ps[i]['missed'] as int? ?? 0
        ..out = ps[i]['out'] as bool? ?? false;
    }
    turn = v['turn'] as int;
    phase = CarromPhase.values.byName(v['phase'] as String);
    shotNumber = v['shotNumber'] as int;
    queenPending = v['queenPending'] as int?;
    winner = v['winner'] as int?;
    winReason = v['winReason'] as String?;
    shotSeconds = v['shotSeconds'] as int? ?? shotSeconds;
  }
}

class CarromRules {
  static const piecesEach = 9;

  /// Pieces of [colour] still on the board.
  static List<int> onBoard(CarromWorld w, int colour) =>
      [for (var i = 1; i < CarromWorld.count; i++) if (!w.gone[i] && CarromWorld.colourOf(i) == colour) i];

  static bool queenOnBoard(CarromWorld w) => !w.gone[CarromWorld.queen];

  /// Rules on a finished stroke by [seat]: credits pieces, returns what has to
  /// come back (moving discs in [w]) and decides who plays next.
  static CarromShotResult resolve(CarromState s, CarromWorld w, int seat) {
    final me = s.players[seat];
    final other = s.other(seat);
    final them = s.players[other];
    final pocketed = List.of(w.pocketed);
    final foul = w.strikerPocketed;
    final own = [for (final d in pocketed) if (CarromWorld.colourOf(d) == me.colour) d];
    final opp = [for (final d in pocketed) if (CarromWorld.colourOf(d) == them.colour) d];
    final queenIn = pocketed.contains(CarromWorld.queen);
    final returned = <int>[];
    var queenReturned = false, queenCovered = false, lastPieceReturned = false, queenPendingNow = false;
    int? penalty;
    var extra = false;
    int? winner;
    String? reason;

    if (foul) {
      for (final d in pocketed) {
        w.returnToCentre(d);
        returned.add(d);
      }
      if (s.queenPending == seat) {
        w.returnToCentre(CarromWorld.queen);
        queenReturned = true;
        s.queenPending = null;
      }
      if (me.pocketed > 0) {
        // One piece already won comes back: the lowest-numbered one still off the board.
        for (var i = 1; i < CarromWorld.count; i++) {
          if (w.gone[i] && CarromWorld.colourOf(i) == me.colour) {
            w.returnToCentre(i);
            penalty = i;
            me.pocketed--;
            break;
          }
        }
      }
    } else {
      final queenOwned = me.hasQueen || them.hasQueen || queenIn || s.queenPending == seat;
      var ownCount = own.length;
      var oppCount = opp.length;
      // The last piece may not drop before the queen is owned.
      if (me.pocketed + ownCount >= piecesEach && !queenOwned) {
        final last = own.last;
        w.returnToCentre(last);
        returned.add(last);
        ownCount--;
        lastPieceReturned = true;
      }
      if (them.pocketed + oppCount >= piecesEach && !(me.hasQueen || them.hasQueen || queenIn)) {
        final last = opp.last;
        w.returnToCentre(last);
        returned.add(last);
        oppCount--;
      }
      them.pocketed += oppCount;
      if (s.queenPending == seat) {
        if (ownCount > 0) {
          me.hasQueen = true;
          queenCovered = true;
        } else {
          w.returnToCentre(CarromWorld.queen);
          queenReturned = true;
        }
        s.queenPending = null;
      }
      if (queenIn) {
        if (ownCount > 0) {
          me.hasQueen = true;
          queenCovered = true;
        } else {
          s.queenPending = seat;
          queenPendingNow = true;
        }
      }
      me.pocketed += ownCount;
      extra = ownCount > 0 || queenIn;
      if (me.pocketed >= piecesEach) {
        winner = seat;
        reason = 'ALL PIECES POCKETED';
      } else if (them.pocketed >= piecesEach) {
        winner = other;
        reason = 'ALL PIECES POCKETED';
      }
    }
    // The striker leaves the board between strokes.
    w.gone[CarromWorld.striker] = true;
    w.vx[CarromWorld.striker] = 0;
    w.vy[CarromWorld.striker] = 0;
    me.missed = 0;
    s.shotNumber++;
    final next = winner != null ? seat : (extra ? seat : other);
    final r = CarromShotResult(
      player: seat,
      foul: foul,
      pocketed: pocketed,
      returned: returned,
      penalty: penalty,
      queenCovered: queenCovered,
      queenReturned: queenReturned,
      queenPending: queenPendingNow,
      lastPieceReturned: lastPieceReturned,
      extraTurn: extra && winner == null,
      nextPlayer: next,
      winner: winner,
      reason: reason,
    );
    s.lastResult = r;
    if (winner != null) {
      s.winner = winner;
      s.winReason = reason;
      s.phase = CarromPhase.gameOver;
    } else {
      s.turn = next;
    }
    return r;
  }

  /// The shot clock ran out: the turn passes (an uncovered queen comes back);
  /// three misses in a row and the player is out.
  static CarromShotResult timeout(CarromState s, CarromWorld w) {
    final seat = s.turn;
    final me = s.players[seat];
    final other = s.other(seat);
    me.missed++;
    var queenReturned = false;
    if (s.queenPending == seat) {
      w.returnToCentre(CarromWorld.queen);
      queenReturned = true;
      s.queenPending = null;
    }
    int? winner;
    String? reason;
    if (me.missed >= 3) {
      me.out = true;
      winner = other;
      reason = 'OPPONENT LEFT';
    }
    final r = CarromShotResult(
      player: seat,
      foul: false,
      pocketed: const [],
      returned: const [],
      penalty: null,
      queenCovered: false,
      queenReturned: queenReturned,
      queenPending: false,
      lastPieceReturned: false,
      extraTurn: false,
      nextPlayer: other,
      winner: winner,
      reason: reason,
      timeout: true,
    );
    s.lastResult = r;
    s.shotNumber++;
    if (winner != null) {
      s.winner = winner;
      s.winReason = reason;
      s.phase = CarromPhase.gameOver;
    } else {
      s.turn = other;
    }
    return r;
  }
}
