import 'dart:math';

import '../models/match_state.dart' show ShotOutcome;
import '../physics/physics_world.dart';

enum PoolGame { nineBall, eightBall, tenBall }

extension PoolGameInfo on PoolGame {
  String get title => switch (this) {
        PoolGame.nineBall => '9-BALL',
        PoolGame.eightBall => '8-BALL',
        PoolGame.tenBall => '10-BALL',
      };

  int get ballCount => switch (this) {
        PoolGame.nineBall => 9,
        PoolGame.eightBall => 15,
        PoolGame.tenBall => 10,
      };

  /// The ball that wins the game.
  int get moneyBall => switch (this) {
        PoolGame.nineBall => 9,
        PoolGame.eightBall => 8,
        PoolGame.tenBall => 10,
      };

  /// Rotation games: the lowest ball on the table must be hit first.
  bool get isRotation => this != PoolGame.eightBall;
}

enum PoolGroup { none, solids, stripes }

extension PoolGroupInfo on PoolGroup {
  String get label => switch (this) {
        PoolGroup.none => 'OPEN',
        PoolGroup.solids => 'SOLIDS',
        PoolGroup.stripes => 'STRIPES',
      };

  PoolGroup get other => switch (this) {
        PoolGroup.solids => PoolGroup.stripes,
        PoolGroup.stripes => PoolGroup.solids,
        PoolGroup.none => PoolGroup.none,
      };
}

enum PoolPhase { playerTurn, shooting, pushOutChoice, gameOver }

enum PoolFoul { none, wrongBallFirst, noContact, scratch, noRail, illegalBreak, timeout }

extension PoolFoulLabel on PoolFoul {
  String get label => switch (this) {
        PoolFoul.none => '',
        PoolFoul.wrongBallFirst => 'WRONG BALL FIRST',
        PoolFoul.noContact => 'NO BALL CONTACTED',
        PoolFoul.scratch => 'SCRATCH',
        PoolFoul.noRail => 'NO RAIL AFTER CONTACT',
        PoolFoul.illegalBreak => 'ILLEGAL BREAK',
        PoolFoul.timeout => 'TIME OUT',
      };
}

class PoolPlayer {
  PoolPlayer({required this.name, required this.avatar, this.isBot = false, this.botSkill = 0.6});

  final String name;
  final String avatar;
  final bool isBot;
  final double botSkill;

  PoolGroup group = PoolGroup.none;
  int consecutiveFouls = 0;
  int shots = 0;
  int ballsPocketed = 0;
  int fouls = 0;
  int missed = 0;
}

class PoolShotResult {
  PoolShotResult({
    required this.player,
    required this.foul,
    required this.pocketed,
    required this.respot,
    required this.turnContinues,
    required this.nextPlayer,
    required this.winner,
    required this.reason,
    required this.groupAssigned,
    required this.wasBreak,
    required this.wasPushOut,
  });

  final int player;
  final PoolFoul foul;
  final List<int> pocketed;

  /// Balls that go back on the table (money ball pocketed illegally).
  final List<int> respot;
  final bool turnContinues;
  final int nextPlayer;
  final int? winner;

  /// Why the game ended, when [winner] is set.
  final String? reason;

  /// Group the shooter just took on an open 8-ball table.
  final PoolGroup? groupAssigned;
  final bool wasBreak;
  final bool wasPushOut;

  bool get legal => foul == PoolFoul.none;
}

class PoolState {
  PoolState({required this.game, required this.players, this.turn = 0})
      : assert(players.length == 2);

  final PoolGame game;
  final List<PoolPlayer> players;
  int turn;

  PoolPhase phase = PoolPhase.playerTurn;
  bool isBreakShot = true;
  bool ballInHand = true;

  /// Cue ball in hand is limited to behind the head string (the break).
  bool behindHeadString = true;

  /// 9-ball: the shot right after a legal break may be a push out.
  bool pushOutAvailable = false;
  bool pushOutDeclared = false;

  /// 8-ball: pocket called for the 8.
  int? calledPocket;

  int shotNumber = 0;
  int? winner;
  String? winReason;
  PoolShotResult? lastResult;

  PoolPlayer get current => players[turn];
  PoolPlayer get opponent => players[1 - turn];
}

/// Rules of 9-Ball, 8-Ball and 10-Ball as given in the client's
/// "Rules of Billiards" document. Pure Dart, deterministic.
class PoolRules {
  PoolRules({Random? random}) : random = random ?? Random.secure();

  final Random random;

  static PoolGroup groupOf(int ball) =>
      ball == 8 ? PoolGroup.none : (ball < 8 ? PoolGroup.solids : PoolGroup.stripes);

  // ----------------------------------------------------------------- rack

  void rack(PoolState s, PhysicsWorld world) {
    switch (s.game) {
      case PoolGame.nineBall:
        // Diamond: 1 on the apex, 9 in the centre.
        final rest = [2, 3, 4, 5, 6, 7, 8]..shuffle(random);
        world.rackLayout(const [1, 2, 3, 2, 1],
            [1, rest[0], rest[1], rest[2], 9, rest[3], rest[4], rest[5], rest[6]]);
      case PoolGame.tenBall:
        // Triangle of four rows: 1 in front, 10 in the middle of the third row.
        final rest = [2, 3, 4, 5, 6, 7, 8, 9]..shuffle(random);
        world.rackLayout(const [1, 2, 3, 4],
            [1, rest[0], rest[1], rest[2], 10, rest[3], rest[4], rest[5], rest[6], rest[7]]);
      case PoolGame.eightBall:
        // Full triangle with the 8 in the centre.
        final rest = [for (var i = 1; i <= 15; i++) if (i != 8) i]..shuffle(random);
        world.rackLayout(const [1, 2, 3, 4, 5], [...rest.sublist(0, 4), 8, ...rest.sublist(4)]);
    }
  }

  // -------------------------------------------------------------- queries

  /// 8-ball: the player has cleared their group and is shooting at the 8.
  bool onEight(PoolState s, Set<int> onTable) {
    if (s.game != PoolGame.eightBall) return false;
    final group = s.current.group;
    return group != PoolGroup.none && !onTable.any((b) => groupOf(b) == group);
  }

  /// Balls the cue ball may legally contact first.
  Set<int> legalTargets(PoolState s, Set<int> onTable) {
    if (onTable.isEmpty) return const {};
    if (s.game.isRotation) return {onTable.reduce(min)};
    if (s.isBreakShot) return onTable;
    final group = s.current.group;
    if (group == PoolGroup.none) return {for (final b in onTable) if (b != 8) b};
    final own = {for (final b in onTable) if (groupOf(b) == group) b};
    return own.isEmpty ? {8} : own;
  }

  bool canShoot(PoolState s, Set<int> onTable) =>
      s.phase == PoolPhase.playerTurn && (!onEight(s, onTable) || s.calledPocket != null);

  // ----------------------------------------------------------------- shot

  /// Verdict for a shot, without changing [s].
  PoolShotResult evaluate(PoolState s, ShotOutcome o, Set<int> onTable) {
    final me = s.turn, other = 1 - s.turn;
    final legal = legalTargets(s, onTable);
    final pushOut = s.pushOutDeclared;
    final money = s.game.moneyBall;

    var foul = PoolFoul.none;
    if (!pushOut) {
      if (o.firstContact == null) {
        foul = PoolFoul.noContact;
      } else if (!legal.contains(o.firstContact)) {
        foul = PoolFoul.wrongBallFirst;
      }
    }
    if (o.cuePocketed && foul == PoolFoul.none) foul = PoolFoul.scratch;
    if (foul == PoolFoul.none && !pushOut && s.game.isRotation && o.pocketed.isEmpty) {
      if (!o.railAfterContact) {
        foul = PoolFoul.noRail;
      } else if (s.game == PoolGame.nineBall && s.isBreakShot && o.objectBallsToRail < 4) {
        foul = PoolFoul.illegalBreak;
      }
    }

    int? winner;
    String? reason;
    var continues = false;
    PoolGroup? assigned;
    final respot = <int>[];
    final moneyDown = o.pocketed.contains(money);

    if (s.game.isRotation) {
      if (moneyDown && foul == PoolFoul.none && !pushOut) {
        winner = me;
        reason = '${s.game.moneyBall}-BALL POCKETED';
      } else {
        if (moneyDown) respot.add(money);
        continues = foul == PoolFoul.none && !pushOut && o.pocketed.isNotEmpty;
        if (foul != PoolFoul.none &&
            s.game == PoolGame.nineBall &&
            s.current.consecutiveFouls + 1 >= 3) {
          winner = other;
          reason = 'THREE FOULS IN A ROW';
        }
      }
    } else if (s.isBreakShot) {
      // Not covered by the document: an 8 made on the break is spotted.
      if (moneyDown) respot.add(8);
      continues = foul == PoolFoul.none && o.pocketed.any((b) => b != 8);
    } else if (moneyDown) {
      if (!onEight(s, onTable)) {
        winner = other;
        reason = '8-BALL POCKETED TOO EARLY';
      } else if (foul != PoolFoul.none) {
        winner = other;
        reason = 'FOUL WHILE POCKETING THE 8-BALL';
      } else if (o.pocketOf[8] != s.calledPocket) {
        winner = other;
        reason = '8-BALL IN THE WRONG POCKET';
      } else {
        winner = me;
        reason = '8-BALL IN THE CALLED POCKET';
      }
    } else if (foul == PoolFoul.none) {
      var group = s.current.group;
      if (group == PoolGroup.none && o.pocketed.isNotEmpty) {
        group = groupOf(o.pocketed.first);
        assigned = group;
      }
      continues = group != PoolGroup.none && o.pocketed.any((b) => groupOf(b) == group);
    }

    return PoolShotResult(
      player: me,
      foul: foul,
      pocketed: List.unmodifiable(o.pocketed),
      respot: respot,
      turnContinues: winner == null && continues,
      nextPlayer: winner == null && continues ? me : other,
      winner: winner,
      reason: reason,
      groupAssigned: assigned,
      wasBreak: s.isBreakShot,
      wasPushOut: pushOut,
    );
  }

  void apply(PoolState s, PoolShotResult r) {
    final p = s.current;
    p.shots++;
    s.shotNumber++;
    p.ballsPocketed += r.pocketed.length - r.respot.length;
    if (r.foul != PoolFoul.none) {
      p.fouls++;
      p.consecutiveFouls++;
    } else if (!r.wasPushOut) {
      p.consecutiveFouls = 0;
    }
    if (r.groupAssigned != null) {
      p.group = r.groupAssigned!;
      s.opponent.group = r.groupAssigned!.other;
    }
    final legalBreak = r.wasBreak && r.foul == PoolFoul.none;
    s
      ..pushOutAvailable = s.game == PoolGame.nineBall && legalBreak
      ..pushOutDeclared = false
      ..isBreakShot = false
      ..behindHeadString = false
      ..ballInHand = r.foul != PoolFoul.none
      ..calledPocket = null
      ..lastResult = r;
    if (r.winner != null) {
      s
        ..winner = r.winner
        ..winReason = r.reason
        ..phase = PoolPhase.gameOver;
      return;
    }
    s.turn = r.nextPlayer;
    // After a push out the incoming player decides who shoots next.
    s.phase = r.wasPushOut && r.foul == PoolFoul.none ? PoolPhase.pushOutChoice : PoolPhase.playerTurn;
  }

  PoolShotResult resolveShot(PoolState s, ShotOutcome o, Set<int> onTable) {
    final r = evaluate(s, o, onTable);
    apply(s, r);
    return r;
  }

  /// Shot clock expired: a foul, the opponent gets ball in hand.
  PoolShotResult timeout(PoolState s) {
    final other = 1 - s.turn;
    final threeFouls = s.game == PoolGame.nineBall && s.current.consecutiveFouls + 1 >= 3;
    final r = PoolShotResult(
      player: s.turn,
      foul: PoolFoul.timeout,
      pocketed: const [],
      respot: const [],
      turnContinues: false,
      nextPlayer: other,
      winner: threeFouls ? other : null,
      reason: threeFouls ? 'THREE FOULS IN A ROW' : null,
      groupAssigned: null,
      wasBreak: false,
      wasPushOut: false,
    );
    // The break stays a break if the breaker never shot.
    final stillBreak = s.isBreakShot;
    apply(s, r);
    s
      ..isBreakShot = stillBreak
      ..behindHeadString = stillBreak
      ..pushOutAvailable = false;
    return r;
  }

  // ------------------------------------------------------------- push out

  bool togglePushOut(PoolState s) {
    if (s.phase != PoolPhase.playerTurn || !s.pushOutAvailable) return false;
    s.pushOutDeclared = !s.pushOutDeclared;
    return true;
  }

  /// The incoming player either shoots from where the cue ball lies or hands
  /// the shot back to the player who pushed out.
  void answerPushOut(PoolState s, {required bool shoot}) {
    if (s.phase != PoolPhase.pushOutChoice) return;
    if (!shoot) s.turn = 1 - s.turn;
    s.phase = PoolPhase.playerTurn;
  }

  /// 8-ball: call the pocket for the 8.
  bool callPocket(PoolState s, Set<int> onTable, int pocket) {
    if (s.phase != PoolPhase.playerTurn || !onEight(s, onTable)) return false;
    s.calledPocket = pocket;
    return true;
  }
}
