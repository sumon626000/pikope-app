// A full staked Ludo match played by two LudoControllers through the backend:
//   API_BASE_URL=http://127.0.0.1:8080 flutter test test_online/ludo_online_test.dart
// Proves the server rolls/rules and both app controllers agree and are paid.
import 'dart:io';
import 'dart:math';

import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/data/api_client.dart';
import 'package:billiard_poker/features/game/game_controller.dart' show SeatConfig;
import 'package:billiard_poker/features/ludo/ludo_controller.dart';
import 'package:billiard_poker/game/ludo/ludo_bot.dart';
import 'package:billiard_poker/features/online/game_link.dart';
import 'package:flutter_test/flutter_test.dart';

final base = Platform.environment['API_BASE_URL'] ?? 'http://127.0.0.1:8080';
final wsUrl = () {
  final v = Platform.environment['WS_URL'] ?? 'ws://127.0.0.1:8081';
  return v.isEmpty ? null : v;
}();

void main() {
  HttpOverrides.global = null;

  test('two online clients play a whole staked Ludo match', () async {
    final apis = <ApiClient>[];
    final ids = <int>[];
    for (final name in ['LudoOnA', 'LudoOnB']) {
      final api = ApiClient(base);
      final r = await api.post('/auth/guest', {'displayName': name});
      api.token = r['token'] as String;
      apis.add(api);
      ids.add((r['user'] as Map)['id'] as int);
    }
    final before = [for (final a in apis) ((await a.get('/me'))['user'] as Map)['coins'] as int];

    Map<String, dynamic> room = {};
    for (final a in apis) {
      room = await a.post('/rooms/quick', {'game': 'ludo2', 'level': 0});
    }
    expect(room['status'], 'playing');
    expect(room['buyIn'], 21);
    expect(room['prize'], 40);
    final gameId = room['gameId'] as int;
    final players = (room['players'] as List).cast<Map<String, dynamic>>();
    final seatsOf = [for (final p in players) SeatConfig(name: p['name'] as String, avatar: p['avatar'] as String)];

    final controllers = <LudoController>[];
    for (var i = 0; i < 2; i++) {
      final seat = players.firstWhere((p) => p['id'] == ids[i])['seat'] as int;
      final driver = OnlineGameDriver(apis[i], gameId, seat, wsUrl: wsUrl, pollInterval: const Duration(milliseconds: 80));
      final c = LudoController(LudoMatchConfig(seats: 2, players: seatsOf, shotSeconds: 30), AudioService(enabled: false), link: driver);
      driver
        ..onState = c.applyRemote
        ..onChat = c.showChat
        ..onError = (_) {}
        ..start();
      controllers.add(c);
    }

    // A quick-chat preset reaches the other player over the socket.
    final chatDeadline = DateTime.now().add(const Duration(seconds: 15));
    var heard = false;
    while (!heard && DateTime.now().isBefore(chatDeadline)) {
      if (controllers.every((c) => c.state != null)) controllers[0].sayChat(3);
      for (final c in controllers) {
        c.tick(0.01);
      }
      heard = controllers[1].chatOf(controllers[0].mySeatForChat) == 3;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    expect(heard, isTrue, reason: 'quick chat relayed to the other player');

    final rng = Random(7);
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (controllers.any((c) => c.state == null || !c.over)) {
      expect(DateTime.now().isBefore(deadline), isTrue, reason: 'match did not finish');
      for (final c in controllers) {
        c.tick(0.05);
        final s = c.state;
        if (s == null || c.over) continue;
        if (!c.isMyTurn) continue;
        if (c.canRoll) {
          c.roll();
        } else if (!s.mustRoll) {
          final m = c.movable;
          if (m.isNotEmpty) c.moveToken(LudoBot(rng).chooseToken(s, s.turn, s.die!, m));
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }

    final w0 = controllers[0].winner, w1 = controllers[1].winner;
    expect(w0, isNotNull);
    expect(w0, w1, reason: 'both clients agree on the winner');

    final after = [for (final a in apis) ((await a.get('/me'))['user'] as Map)['coins'] as int];
    final winnerSeat = w0!;
    for (var i = 0; i < 2; i++) {
      final mySeat = players.firstWhere((p) => p['id'] == ids[i])['seat'] as int;
      final expected = before[i] - 21 + (mySeat == winnerSeat ? 40 : 0);
      expect(after[i], expected, reason: 'coins for client $i');
    }
    // ignore: avoid_print
    print('Ludo online: seat $winnerSeat won; coins $before -> $after');
    for (final c in controllers) {
      c.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
