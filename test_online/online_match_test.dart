// End-to-end online matches against a running backend, with real HTTP and
// real physics on every client:
//   API_BASE_URL=http://127.0.0.1:8080 flutter test test_online/online_match_test.dart
// Every seat is a separate client (own account, own controller); bots stand
// in for the human at each client and play through the public controller API.
import 'dart:io';
import 'dart:math';

import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/data/api_client.dart';
import 'package:billiard_poker/features/game/game_controller.dart';
import 'package:billiard_poker/features/online/game_link.dart';
import 'package:billiard_poker/features/pool/pool_controller.dart';
import 'package:billiard_poker/game/ai/bot_player.dart';
import 'package:billiard_poker/game/models/match_state.dart';
import 'package:billiard_poker/game/pool/pool_bot.dart';
import 'package:billiard_poker/game/pool/pool_rules.dart';
import 'package:flutter_test/flutter_test.dart';

final base = Platform.environment['API_BASE_URL'] ?? 'http://127.0.0.1:8080';

/// WebSocket server under test; set WS_URL= (empty) to run over HTTP polling only.
final String? wsUrl = () {
  final v = Platform.environment['WS_URL'] ?? 'ws://127.0.0.1:8081';
  return v.isEmpty ? null : v;
}();

class Client {
  Client(this.api, this.userId, this.name);
  final ApiClient api;
  final int userId;
  final String name;
  late OnlineGameDriver driver;
  final errors = <ApiException>[];
  int cooldown = 0;
}

Future<Client> guest(String name) async {
  final api = ApiClient(base);
  final r = await api.post('/auth/guest', {'displayName': name});
  api.token = r['token'] as String;
  return Client(api, (r['user'] as Map)['id'] as int, name);
}

/// Seats [clients] in one room of [game]; returns the started room.
Future<Map<String, dynamic>> seatAll(List<Client> clients, String game, {int? level}) async {
  late Map<String, dynamic> room;
  for (final c in clients) {
    room = await c.api.post('/rooms/quick', {'game': game, 'level': ?level});
  }
  expect(room['status'], 'playing');
  return room;
}

List<SeatConfig> seatsOf(Map<String, dynamic> room) => [
      for (final p in (room['players'] as List).cast<Map<String, dynamic>>())
        SeatConfig(name: p['name'] as String, avatar: p['avatar'] as String),
    ];

int seatFor(Map<String, dynamic> room, Client c) =>
    (room['players'] as List).cast<Map<String, dynamic>>().firstWhere((p) => p['id'] == c.userId)['seat'] as int;

/// With a WebSocket server the match must really have run over it.
void transportCheck(List<Client> clients, String game) {
  final pushed = clients.fold<int>(0, (n, c) => n + c.driver.pushedStates);
  final polled = clients.fold<int>(0, (n, c) => n + c.driver.polledStates);
  // ignore: avoid_print
  print('$game transport: $pushed states pushed over WebSocket, $polled over HTTP');
  if (wsUrl != null) {
    // A match can be over in a handful of shots (the 9 on the break).
    expect(pushed, greaterThan(pushed + polled >= 30 ? polled * 5 : polled), reason: 'the match did not run over the WebSocket');
    for (final c in clients) {
      expect(c.driver.realtime, isTrue, reason: 'a client lost its socket');
    }
  } else {
    expect(pushed, 0);
  }
}

void main() {
  HttpOverrides.global = null; // real network

  test('Billiard Poker: four online clients play a whole match', () async {
    final clients = [for (var i = 0; i < 4; i++) await guest('P$i')];
    final room = await seatAll(clients, 'poker');
    final gameId = room['gameId'] as int;
    final rng = Random(7);

    final controllers = <GameController>[];
    for (final c in clients) {
      c.driver = OnlineGameDriver(c.api, gameId, seatFor(room, c),
          wsUrl: wsUrl, pollInterval: const Duration(milliseconds: 70));
      final controller = GameController(
        MatchConfig(seats: seatsOf(room), shotSeconds: room['shotSeconds'] as int),
        AudioService(enabled: false),
        link: c.driver,
      );
      c.driver
        ..onState = controller.applyRemote
        ..onError = c.errors.add
        ..start();
      controllers.add(controller);
    }

    var sawPenalty = false, sawReady = false, shots = 0, rejoined = false;
    final publiclyShown = <int>{};
    final deadline = DateTime.now().add(const Duration(minutes: 6));
    while (controllers.any((c) => c.state.phase != GamePhase.gameOver)) {
      expect(DateTime.now().isBefore(deadline), isTrue, reason: 'match did not finish');
      if (shots == 12 && !rejoined) {
        // Client 0's app is closed and reopened: it asks the server which
        // match it is in and takes its seat again.
        rejoined = true;
        final gone = clients[0];
        gone.driver.dispose();
        controllers[0].dispose();
        final match = (await gone.api.get('/me/active'))['match'] as Map<String, dynamic>;
        expect(match['gameId'], gameId);
        gone.driver = OnlineGameDriver(gone.api, gameId, match['seat'] as int,
            wsUrl: wsUrl, pollInterval: const Duration(milliseconds: 70));
        final controller = GameController(
          MatchConfig(seats: [
            for (final p in (match['players'] as List).cast<Map<String, dynamic>>())
              SeatConfig(name: p['name'] as String, avatar: p['avatar'] as String),
          ], shotSeconds: match['shotSeconds'] as int),
          AudioService(enabled: false),
          link: gone.driver,
        );
        gone.driver
          ..onState = controller.applyRemote
          ..onError = gone.errors.add
          ..start();
        controllers[0] = controller;
      }
      for (var i = 0; i < clients.length; i++) {
        final c = controllers[i];
        final me = clients[i];
        c.tick(0.05);
        if (me.cooldown > 0) {
          me.cooldown--;
          continue;
        }
        final seat = me.driver.seat;
        if (c.breakPicker == seat) {
          final free = [for (var k = 0; k < c.breakSpread.length; k++) if (c.breakSpread[k] != null) k];
          c.pickBreakCard(free[rng.nextInt(free.length)]);
          me.cooldown = 12;
        } else if (c.canDeclare) {
          c.declareWinner();
          me.cooldown = 12;
        } else if (c.canAim) {
          final shot = BotPlayer(rng).chooseShot(c.world, c.state);
          if (shot.cuePos != null) c.moveCue(shot.cuePos!);
          if (shot.card != null) c.selectCard(shot.card!);
          if (shot.freeBall != null) c.selectFreeBall(shot.freeBall!);
          c.aimAngle = shot.angle;
          c.setPower(shot.power);
          c.releaseShot();
          shots++;
          me.cooldown = 4;
        }
        // Hidden information: a client may only know an opponent's card
        // once it was shown to everyone (revealed for a shot, or grayed out).
        final selected = c.state.selectedCard;
        if (selected != null) publiclyShown.add(selected.key);
        for (var j = 0; j < c.players.length; j++) {
          if (j == seat || c.state.phase == GamePhase.gameOver) continue;
          for (final card in c.players[j].hand) {
            expect(card.hidden || card.revealed || publiclyShown.contains(card.key), isTrue,
                reason: 'client $seat knows a hidden card of player $j: ${card.card} key ${card.key}');
          }
        }
        sawPenalty |= c.players[seat].hand.any((h) => h.isPenalty);
        sawReady |= c.state.winner == null && c.players.any((p) => p.readyToDeclare);
      }
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }

    final winner = controllers.first.state.winner;
    expect(winner, isNotNull);
    // The server simulates every shot itself; each client's own animation of
    // the same stroke must have ended in exactly the same place.
    final drift = controllers.map((c) => c.replayDrift).reduce(max);
    expect(drift, lessThan(1e-9), reason: 'app and server physics disagree');
    for (final c in controllers) {
      expect(c.state.winner, winner, reason: 'clients disagree on the winner');
    }
    expect(sawReady, isTrue, reason: 'nobody had to wait a turn before declaring');
    expect(rejoined, isTrue);
    // The server booked the result.
    final me = await clients.firstWhere((c) => c.driver.seat == winner).api.get('/me');
    expect((me['user'] as Map)['wins'], 1);
    expect((me['user'] as Map)['coins'], 2000, reason: 'a friendly match moves no coins');
    expect((me['user'] as Map)['xp'], 60);
    transportCheck(clients, 'poker');
    final unexpected = [
      for (final c in clients) ...c.errors.where((e) => e.code != 'card_taken' && e.code != 'already_picked')
    ];
    expect(unexpected, isEmpty, reason: unexpected.map((e) => '${e.code}: ${e.message}').join('; '));
    // ignore: avoid_print
    print('poker online: seat $winner won after $shots shots (penalties seen: $sawPenalty, physics drift $drift)');
    for (final c in clients) {
      c.driver.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('9-BALL with an unreachable WebSocket server falls back to HTTP', () async {
    final clients = [await guest('A'), await guest('B')];
    final room = await seatAll(clients, 'nine');
    final gameId = room['gameId'] as int;
    final rng = Random(5);
    final controllers = <PoolController>[];
    for (final c in clients) {
      c.driver = OnlineGameDriver(c.api, gameId, seatFor(room, c),
          wsUrl: 'ws://127.0.0.1:9', pollInterval: const Duration(milliseconds: 70));
      final controller = PoolController(
        PoolMatchConfig(game: PoolGame.nineBall, seats: seatsOf(room), shotSeconds: room['shotSeconds'] as int),
        AudioService(enabled: false),
        link: c.driver,
      );
      c.driver
        ..onState = controller.applyRemote
        ..onError = c.errors.add
        ..start();
      controllers.add(controller);
    }
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (controllers.any((c) => c.state.phase != PoolPhase.gameOver)) {
      expect(DateTime.now().isBefore(deadline), isTrue, reason: 'match did not finish');
      for (var i = 0; i < 2; i++) {
        final c = controllers[i];
        c.tick(0.05);
        if (clients[i].cooldown > 0) {
          clients[i].cooldown--;
        } else if (c.choosingPushOut) {
          c.answerPushOut(shoot: true);
          clients[i].cooldown = 12;
        } else if (c.canAim) {
          final shot = PoolBot(c.rules, rng).chooseShot(c.world, c.state);
          if (shot.cuePos != null) c.moveCue(shot.cuePos!);
          c.aimAngle = shot.angle;
          c.setPower(shot.power);
          c.releaseShot();
          clients[i].cooldown = 4;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    expect(controllers[0].state.winner, controllers[1].state.winner);
    for (final c in clients) {
      expect(c.driver.realtime, isFalse);
      expect(c.driver.pushedStates, 0);
      expect(c.driver.polledStates, greaterThan(5));
      c.driver.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 6)));

  // The last entry is the staked queue: the server draws 8-, 9- or 10-ball.
  for (final entry in <String, PoolGame?>{'nine': PoolGame.nineBall, 'eight': PoolGame.eightBall, 'ten': PoolGame.tenBall, 'billiard': null}.entries) {
    test('${entry.value?.title ?? 'STAKED BILLIARD'}: two online clients play a whole match', () async {
      final clients = [await guest('A'), await guest('B')];
      final room = await seatAll(clients, entry.key, level: entry.value == null ? 0 : null);
      final game = const {'eight': PoolGame.eightBall, 'nine': PoolGame.nineBall, 'ten': PoolGame.tenBall}[room['game']]!;
      if (entry.value == null) {
        expect(room['buyIn'], 21);
        expect(room['prize'], 40);
        for (final c in clients) {
          expect(((await c.api.get('/me'))['user'] as Map)['coins'], 2000 - 21, reason: 'buy-in taken at the start');
        }
      }
      final gameId = room['gameId'] as int;
      final rng = Random(3);

      final controllers = <PoolController>[];
      for (final c in clients) {
        c.driver = OnlineGameDriver(c.api, gameId, seatFor(room, c),
          wsUrl: wsUrl, pollInterval: const Duration(milliseconds: 70));
        final controller = PoolController(
          PoolMatchConfig(game: game, seats: seatsOf(room), shotSeconds: room['shotSeconds'] as int),
          AudioService(enabled: false),
          link: c.driver,
        );
        c.driver
          ..onState = controller.applyRemote
          ..onError = c.errors.add
          ..start();
        controllers.add(controller);
      }

      var shots = 0, replayChecks = 0, lastCompared = -1;
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (controllers.any((c) => c.state.phase != PoolPhase.gameOver)) {
        expect(DateTime.now().isBefore(deadline), isTrue, reason: 'match did not finish');
        for (var i = 0; i < 2; i++) {
          final c = controllers[i];
          final me = clients[i];
          c.tick(0.05);
          if (me.cooldown > 0) {
            me.cooldown--;
            continue;
          }
          if (c.choosingPushOut) {
            c.answerPushOut(shoot: true);
            me.cooldown = 12;
          } else if (c.canAim) {
            final shot = PoolBot(c.rules, rng).chooseShot(c.world, c.state);
            if (shot.cuePos != null) c.moveCue(shot.cuePos!);
            if (shot.calledPocket != null) c.tapPocket(shot.calledPocket!);
            c.aimAngle = shot.angle;
            c.setPower(shot.power);
            c.releaseShot();
            shots++;
            me.cooldown = 4;
          }
        }
        // Between shots both tables must be identical.
        final a = controllers[0], b = controllers[1];
        if (a.state.phase == PoolPhase.playerTurn && b.state.phase == PoolPhase.playerTurn &&
            !a.world.isMoving && !b.world.isMoving &&
            a.inSync && b.inSync && // neither is waiting for the server's ruling
            a.onTable.isNotEmpty && b.onTable.isNotEmpty && // both have the server's rack
            a.state.shotNumber == b.state.shotNumber && a.state.shotNumber != lastCompared) {
          lastCompared = a.state.shotNumber;
          for (var n = 0; n < 16; n++) {
            expect(a.world.balls[n].pocketed, b.world.balls[n].pocketed, reason: 'ball $n pocketed differs');
            expect(a.world.balls[n].pos.distanceTo(b.world.balls[n].pos), lessThan(0.01),
                reason: 'ball $n rests in different places');
          }
          expect(a.onTable, b.onTable);
          expect(a.state.turn, b.state.turn);
          replayChecks++;
        }
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }

      expect(controllers[0].state.winner, isNotNull);
      expect(controllers[0].state.winner, controllers[1].state.winner);
      final drift = controllers.map((c) => c.replayDrift).reduce(max);
      expect(drift, lessThan(1e-9), reason: 'app and server physics disagree');
      expect(controllers[0].state.winReason, controllers[1].state.winReason);
      transportCheck(clients, entry.key);
      final errors = [for (final c in clients) ...c.errors];
      expect(errors, isEmpty, reason: errors.map((e) => '${e.code}: ${e.message}').join('; '));
      // ignore: avoid_print
      print('${entry.value?.title ?? 'STAKED ${game.title}'} online: seat ${controllers[0].state.winner} won by '
          '"${controllers[0].state.winReason}" after $shots shots ($replayChecks table comparisons, physics drift $drift)');
      if (entry.value == null) {
        // Winner takes the prize, the loser's buy-in is gone, the fee stays with the house.
        final winner = controllers[0].state.winner!;
        for (final c in clients) {
          final coins = ((await c.api.get('/me'))['user'] as Map)['coins'];
          expect(coins, c.driver.seat == winner ? 2000 - 21 + 40 : 2000 - 21);
        }
      }
      for (final c in clients) {
        c.driver.dispose();
      }
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
