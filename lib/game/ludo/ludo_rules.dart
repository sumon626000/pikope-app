
/// Classic Ludo (Ludo King style), server-authoritative like the pool games.
///
/// Board: a 52-cell main ring plus a 6-cell home column per colour. A token's
/// position is a single [step]:
///   -1            in its base (yard), not yet out
///   0 .. 50       on the main ring (cell = (start[colour] + step) % 52)
///   51 .. 55      in the home column (5 visible cells)
///   56            home (finished); must be reached by an exact roll
///
/// Rules implemented: need a 6 to leave the base and to roll again; capturing
/// an opponent (landing on it off a safe cell) sends it home and grants another
/// roll; finishing a token grants another roll; three 6s in a row forfeit the
/// turn; the home column cannot be overshot. Blockades (two tokens forming a
/// wall) are intentionally not implemented - see docs/PROJECT_DECISIONS.md.
class LudoRules {
  static const ring = 52;
  static const homeStep = 56; // exact step a token must reach to finish

  /// Where each colour joins the ring. Colours: 0 red, 1 green, 2 yellow, 3 blue.
  static const start = [0, 13, 26, 39];

  /// Cells where a token is never captured: each colour's start plus the four
  /// star cells between them.
  static const safeCells = {0, 8, 13, 21, 26, 34, 39, 47};

  /// Absolute ring cell of a token on the main path (step 0..50).
  static int ringCell(int colour, int step) => (start[colour] + step) % ring;

  /// True while a token is on the shared main ring (can capture / be captured).
  static bool onRing(int step) => step >= 0 && step <= 50;

  /// Can this token move by [die] (ignoring whose turn it is)?
  static bool canMove(LudoState s, int seat, int token, int die) {
    final step = s.players[seat].tokens[token];
    if (step == homeStep) return false; // already home
    if (step == -1) return die == 6; // leave base only on a 6
    return step + die <= homeStep; // cannot overshoot home
  }

  /// Tokens the player may move with [die]; empty means the turn is dead.
  static List<int> movable(LudoState s, int seat, int die) =>
      [for (var t = 0; t < 4; t++) if (canMove(s, seat, t, die)) t];

  /// Applies a die roll. Returns the tokens that can move; when none can, the
  /// turn passes (or, on a third six, is forfeited) and the return is empty.
  static List<int> roll(LudoState s, int die) {
    s.die = die;
    final six = die == 6;
    if (six) s.sixes++;
    // Three sixes in a row: the turn is void, nothing moves.
    if (s.sixes >= 3) {
      _pass(s);
      return const [];
    }
    final moves = movable(s, s.turn, die);
    if (moves.isEmpty) {
      // A fruitless roll: a non-six (or a six with no exit) ends the turn,
      // unless the six still entitles another roll with tokens stuck in base.
      if (six) {
        // Six but nothing to move: the turn still passes (no legal move).
        _pass(s);
      } else {
        _pass(s);
      }
      return const [];
    }
    s.mustRoll = false;
    s.movable = moves;
    return moves;
  }

  /// Moves [token] by the current die. Must follow a [roll] that made it movable.
  /// Returns a short outcome for the UI (capture / finished / extra turn).
  static LudoMove move(LudoState s, int token) {
    final die = s.die!;
    final seat = s.turn;
    final p = s.players[seat];
    final from = p.tokens[token];
    final six = die == 6;

    var captured = <int>[]; // [seat, token] pairs flattened as seat*4+token
    int to;
    if (from == -1) {
      to = 0; // onto the start square
    } else {
      to = from + die;
    }
    p.tokens[token] = to;

    // Capture: landing on a non-safe ring cell occupied only by opponents.
    if (onRing(to)) {
      final cell = ringCell(seat, to);
      if (!safeCells.contains(cell)) {
        for (var os = 0; os < s.seats; os++) {
          if (os == seat || s.players[os].out) continue;
          for (var ot = 0; ot < 4; ot++) {
            final ostep = s.players[os].tokens[ot];
            if (onRing(ostep) && ringCell(s.colourOf(os), ostep) == cell) {
              s.players[os].tokens[ot] = -1; // sent home
              captured.add(os * 4 + ot);
            }
          }
        }
      }
    }

    final finishedToken = to == homeStep;
    if (finishedToken) p.finished++;

    final won = p.finished == 4;
    s.shotNumber++;
    final extra = six || captured.isNotEmpty || finishedToken;

    s.lastResult = LudoResult(
      seq: ++s.resultSeq,
      player: seat,
      token: token,
      from: from,
      to: to,
      die: die,
      captured: captured,
      finishedToken: finishedToken,
      extraTurn: extra && !won,
    );

    if (won) {
      s.winner = seat;
      s.winReason = 'ALL TOKENS HOME';
      s.phase = LudoPhase.gameOver;
      s.die = null;
      s.movable = null;
      s.mustRoll = false;
      return LudoMove(captured: captured, finished: finishedToken, extraTurn: false, won: true);
    }

    s.die = null;
    s.movable = null;
    if (extra) {
      // Same player rolls again; the six count only matters for a six.
      if (!six) s.sixes = 0;
      s.mustRoll = true;
    } else {
      _advanceTurn(s);
    }
    return LudoMove(captured: captured, finished: finishedToken, extraTurn: extra, won: false);
  }

  /// The turn ends with no move played (dead roll or three sixes).
  static void _pass(LudoState s) {
    s.die = null;
    s.movable = null;
    _advanceTurn(s);
  }

  static void _advanceTurn(LudoState s) {
    s.sixes = 0;
    s.mustRoll = true;
    // Skip players who have left the match.
    var next = s.turn;
    for (var i = 0; i < s.seats; i++) {
      next = (next + 1) % s.seats;
      if (!s.players[next].out) break;
    }
    s.turn = next;
  }

  /// A player who ran out of time too often leaves. With one player left on a
  /// 2-seat board the other wins; otherwise play continues.
  static void timeOut(LudoState s) {
    final p = s.players[s.turn];
    p.missed++;
    if (p.missed >= 3) {
      p.out = true;
      final active = [for (var i = 0; i < s.seats; i++) if (!s.players[i].out) i];
      if (active.length == 1) {
        s.winner = active.first;
        s.winReason = 'OPPONENTS LEFT';
        s.phase = LudoPhase.gameOver;
        s.die = null;
        s.movable = null;
        return;
      }
    }
    _pass(s);
  }
}

enum LudoPhase { playerTurn, gameOver }

class LudoPlayer {
  LudoPlayer({required this.name, required this.avatar, required this.colour, this.isBot = false});

  final String name;
  final String avatar;

  /// 0 red, 1 green, 2 yellow, 3 blue.
  int colour;
  final bool isBot;

  /// Step of each of the four tokens (see [LudoRules]).
  final List<int> tokens = [-1, -1, -1, -1];
  int finished = 0;
  int missed = 0;
  bool out = false;

  Map<String, dynamic> toJson() => {
        'name': name,
        'avatar': avatar,
        'colour': colour,
        'tokens': tokens,
        'finished': finished,
        'missed': missed,
        'out': out,
      };

  factory LudoPlayer.fromJson(Map<String, dynamic> j) {
    final p = LudoPlayer(
      name: j['name'] as String,
      avatar: j['avatar'] as String,
      colour: j['colour'] as int,
      isBot: j['isBot'] as bool? ?? false,
    );
    final t = (j['tokens'] as List).cast<int>();
    for (var i = 0; i < 4; i++) {
      p.tokens[i] = t[i];
    }
    p.finished = j['finished'] as int;
    p.missed = j['missed'] as int? ?? 0;
    p.out = j['out'] as bool? ?? false;
    return p;
  }
}

class LudoResult {
  LudoResult({
    required this.seq,
    required this.player,
    required this.token,
    required this.from,
    required this.to,
    required this.die,
    required this.captured,
    required this.finishedToken,
    required this.extraTurn,
  });

  final int seq;
  final int player;
  final int token;
  final int from;
  final int to;
  final int die;

  /// Opponent tokens sent home, encoded as seat*4 + token.
  final List<int> captured;
  final bool finishedToken;
  final bool extraTurn;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'player': player,
        'token': token,
        'from': from,
        'to': to,
        'die': die,
        'captured': captured,
        'finishedToken': finishedToken,
        'extraTurn': extraTurn,
      };

  factory LudoResult.fromJson(Map<String, dynamic> j) => LudoResult(
        seq: j['seq'] as int,
        player: j['player'] as int,
        token: j['token'] as int,
        from: j['from'] as int,
        to: j['to'] as int,
        die: j['die'] as int,
        captured: (j['captured'] as List).cast<int>(),
        finishedToken: j['finishedToken'] as bool,
        extraTurn: j['extraTurn'] as bool,
      );
}

/// Return of [LudoRules.move], for the controller to animate.
class LudoMove {
  const LudoMove({required this.captured, required this.finished, required this.extraTurn, required this.won});

  final List<int> captured;
  final bool finished;
  final bool extraTurn;
  final bool won;
}

class LudoState {
  LudoState({required this.seats, required this.players, required this.shotSeconds});

  final int seats;
  final List<LudoPlayer> players;
  final int shotSeconds;

  LudoPhase phase = LudoPhase.playerTurn;
  int turn = 0;

  /// The current die once rolled, else null (awaiting a roll).
  int? die;

  /// Consecutive sixes this turn.
  int sixes = 0;

  /// True while awaiting a roll; false while awaiting a token move.
  bool mustRoll = true;

  /// Tokens the current player may move (set after a roll).
  List<int>? movable;

  int shotNumber = 0;
  int? winner;
  String? winReason;
  LudoResult? lastResult;
  int resultSeq = 0;
  int deadlineMs = 0;

  int colourOf(int seat) => players[seat].colour;

  Map<String, dynamic> toJson() => {
        'kind': 'ludo',
        'phase': phase.name,
        'seats': seats,
        'players': [for (final p in players) p.toJson()],
        'turn': turn,
        'die': die,
        'sixes': sixes,
        'mustRoll': mustRoll,
        'movable': movable,
        'shotNumber': shotNumber,
        'winner': winner,
        'winReason': winReason,
        'lastResult': lastResult?.toJson(),
        'resultSeq': resultSeq,
        'shotSeconds': shotSeconds,
      };

  factory LudoState.fromJson(Map<String, dynamic> j) {
    final s = LudoState(
      seats: j['seats'] as int,
      players: [for (final p in (j['players'] as List).cast<Map<String, dynamic>>()) LudoPlayer.fromJson(p)],
      shotSeconds: j['shotSeconds'] as int,
    );
    s.phase = LudoPhase.values.byName(j['phase'] as String);
    s.turn = j['turn'] as int;
    s.die = j['die'] as int?;
    s.sixes = j['sixes'] as int? ?? 0;
    s.mustRoll = j['mustRoll'] as bool? ?? true;
    s.movable = (j['movable'] as List?)?.cast<int>();
    s.shotNumber = j['shotNumber'] as int? ?? 0;
    s.winner = j['winner'] as int?;
    s.winReason = j['winReason'] as String?;
    final lr = j['lastResult'];
    s.lastResult = lr == null ? null : LudoResult.fromJson(lr as Map<String, dynamic>);
    s.resultSeq = j['resultSeq'] as int? ?? 0;
    return s;
  }

  /// A fresh match. [colours] gives each seat its colour (red/green/yellow/blue).
  static LudoState initial(List<LudoPlayer> players, int shotSeconds) =>
      LudoState(seats: players.length, players: players, shotSeconds: shotSeconds);
}
