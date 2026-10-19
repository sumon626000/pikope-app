// Stand-in opponents for testing the app's online mode by hand or from an
// integration test: they sign in as guests, quick-match into a room of
// BOT_GAME (poker | eight | nine | ten) and play it out.
//   BOT_GAME=nine BOT_COUNT=1 API_BASE_URL=http://127.0.0.1:8080 \
//     flutter test test_online/opponent_bot_test.dart
// Staked queues: BOT_GAME=billiard (or poker) with BOT_LEVEL=0..4.
import 'dart:io';
import 'dart:math';

import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/data/api_client.dart';
import 'package:billiard_poker/data/app_game.dart';
import 'package:billiard_poker/features/game/game_controller.dart';
import 'package:billiard_poker/features/online/game_link.dart';
import 'package:billiard_poker/features/pool/pool_controller.dart';
import 'package:billiard_poker/game/ai/bot_player.dart';
import 'package:billiard_poker/game/models/match_state.dart';
import 'package:billiard_poker/game/pool/pool_bot.dart';
import 'package:billiard_poker/game/pool/pool_rules.dart';
import 'package:flutter_test/flutter_test.dart';

final base = Platform.environment['API_BASE_URL'] ?? 'http://127.0.0.1:8080';
final gameName = Platform.environment['BOT_GAME'] ?? 'nine';
final count = int.parse(Platform.environment['BOT_COUNT'] ?? '1');

/// Bet level to queue at (BOT_GAME=billiard or poker), or unset for a free match.
final level = int.tryParse(Platform.environment['BOT_LEVEL'] ?? '');

void main() {
  HttpOverrides.global = null;

  test('online opponents', () async {
    final rng = Random();
    final apis = <ApiClient>[];
    final ids = <int>[];
    late Map<String, dynamic> room;
    for (var i = 0; i < count; i++) {
      final api = ApiClient(base);
      final r = await api.post('/auth/guest', {'displayName': 'RIVAL ${i + 1}', 'avatar': 'asset:avatar_${i + 2}'});
      api.token = r['token'] as String;
      apis.add(api);
      ids.add((r['user'] as Map)['id'] as int);
      room = await api.post('/rooms/quick', {'game': gameName, 'level': ?level});
    }
    // ignore: avoid_print
    print('BOTS waiting in room ${room['code']}');
    while (room['status'] != 'playing') {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      for (final api in apis) {
        room = await api.get('/rooms/${room['id']}'); // heartbeat for every bot
      }
    }
    // The staked billiard queue draws its game when the room fills.
    final game = AppGameInfo.fromApi(room['game'] as String);
    final players = (room['players'] as List).cast<Map<String, dynamic>>();
    final seats = [for (final p in players) SeatConfig(name: p['name'] as String, avatar: p['avatar'] as String)];
    final gameId = room['gameId'] as int;
    // ignore: avoid_print
    print('BOTS playing game $gameId');

    final ticks = <void Function()>[];
    final over = <bool Function()>[];
    for (var i = 0; i < count; i++) {
      final seat = players.firstWhere((p) => p['id'] == ids[i])['seat'] as int;
      final driver = OnlineGameDriver(apis[i], gameId, seat,
          wsUrl: Platform.environment['WS_URL'] ?? 'ws://127.0.0.1:8081',
          pollInterval: const Duration(milliseconds: 300));
      var cooldown = 0;
      if (game.poolGame == null) {
        final c = GameController(MatchConfig(seats: seats, shotSeconds: room['shotSeconds'] as int),
            AudioService(enabled: false), link: driver);
        driver
          ..onState = c.applyRemote
          ..start();
        over.add(() => c.state.phase == GamePhase.gameOver);
        ticks.add(() {
          c.tick(0.02);
          if (cooldown-- > 0) return;
          if (c.breakPicker == seat) {
            final free = [for (var k = 0; k < c.breakSpread.length; k++) if (c.breakSpread[k] != null) k];
            c.pickBreakCard(free[rng.nextInt(free.length)]);
            cooldown = 60;
          } else if (c.canDeclare) {
            c.declareWinner();
            cooldown = 60;
          } else if (c.canAim) {
            final shot = BotPlayer(rng).chooseShot(c.world, c.state);
            if (shot.cuePos != null) c.moveCue(shot.cuePos!);
            if (shot.card != null) c.selectCard(shot.card!);
            if (shot.freeBall != null) c.selectFreeBall(shot.freeBall!);
            c.aimAngle = shot.angle;
            c.setPower(shot.power);
            c.releaseShot();
            cooldown = 20;
          }
        });
      } else {
        final c = PoolController(
            PoolMatchConfig(game: game.poolGame!, seats: seats, shotSeconds: room['shotSeconds'] as int),
            AudioService(enabled: false),
            link: driver);
        driver
          ..onState = c.applyRemote
          ..start();
        over.add(() => c.state.phase == PoolPhase.gameOver);
        ticks.add(() {
          c.tick(0.02);
          if (cooldown-- > 0) return;
          if (c.choosingPushOut) {
            c.answerPushOut(shoot: true);
            cooldown = 60;
          } else if (c.canAim) {
            final shot = PoolBot(c.rules, rng).chooseShot(c.world, c.state);
            if (shot.cuePos != null) c.moveCue(shot.cuePos!);
            if (shot.calledPocket != null) c.tapPocket(shot.calledPocket!);
            c.aimAngle = shot.angle;
            c.setPower(shot.power);
            c.releaseShot();
            cooldown = 20;
          }
        });
      }
    }
    // Real time: these bots share the table with a person watching the shots.
    while (!over.every((f) => f())) {
      for (final t in ticks) {
        t();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // ignore: avoid_print
    print('BOTS done');
  }, timeout: const Timeout(Duration(minutes: 40)));
}
