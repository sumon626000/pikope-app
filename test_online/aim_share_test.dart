// The cue of the player at the table is shown to the opponent while they aim:
//   API_BASE_URL=... WS_URL=... flutter test test_online/aim_share_test.dart
// Uses a private room, so it never pairs with real players.
import 'dart:io';

import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/data/api_client.dart';
import 'package:billiard_poker/features/game/game_controller.dart' show SeatConfig;
import 'package:billiard_poker/features/online/game_link.dart';
import 'package:billiard_poker/features/pool/pool_controller.dart';
import 'package:billiard_poker/game/physics/vec2.dart';
import 'package:billiard_poker/game/pool/pool_rules.dart';
import 'package:flutter_test/flutter_test.dart';

final base = Platform.environment['API_BASE_URL'] ?? 'http://127.0.0.1:8080';
final wsUrl = Platform.environment['WS_URL'] ?? 'ws://127.0.0.1:8081';

void main() {
  HttpOverrides.global = null; // real network

  test('the opponent sees the shooter\'s cue move', () async {
    final apis = <ApiClient>[], ids = <int>[];
    for (final name in ['AIM A', 'AIM B']) {
      final api = ApiClient(base);
      final r = await api.post('/auth/guest', {'displayName': name});
      api.token = r['token'] as String;
      apis.add(api);
      ids.add((r['user'] as Map)['id'] as int);
    }
    var room = await apis[0].post('/rooms', {'game': 'nine', 'private': true});
    room = await apis[1].post('/rooms/join', {'code': room['code']});
    expect(room['status'], 'playing');
    final gameId = room['gameId'] as int;
    final players = (room['players'] as List).cast<Map<String, dynamic>>();

    final drivers = <OnlineGameDriver>[], controllers = <PoolController>[];
    for (var i = 0; i < 2; i++) {
      final seat = players.firstWhere((p) => p['id'] == ids[i])['seat'] as int;
      final driver = OnlineGameDriver(apis[i], gameId, seat, wsUrl: wsUrl, pollInterval: const Duration(milliseconds: 100));
      final c = PoolController(
        PoolMatchConfig(game: PoolGame.nineBall, seats: [
          for (final p in players) SeatConfig(name: p['name'] as String, avatar: p['avatar'] as String),
        ], shotSeconds: room['shotSeconds'] as int),
        AudioService(enabled: false),
        link: driver,
      );
      driver
        ..onState = c.applyRemote
        ..onAim = c.applyRemoteAim
        ..start();
      drivers.add(driver);
      controllers.add(c);
    }

    Future<void> run(int ms) async {
      for (var t = 0; t < ms; t += 20) {
        for (final c in controllers) {
          c.tick(0.02);
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    // Let both sign in over the socket and finish the opening banner.
    for (var i = 0; i < 400 && !(controllers.any((c) => c.canAim) && drivers.every((d) => d.realtime)); i++) {
      await run(20);
    }
    final me = controllers.indexWhere((c) => c.canAim);
    expect(me, isNot(-1), reason: 'nobody got the break');
    final shooter = controllers[me], watcher = controllers[1 - me];
    await run(300);
    expect(watcher.showRemoteCue, isTrue, reason: 'the opponent\'s cue is not shown');
    expect(shooter.showRemoteCue, isFalse);

    // Break = ball in hand behind the head string: move the cue ball, swing
    // the cue round and pull the power bar.
    shooter.moveCue(const Vec2(180, 330));
    shooter.aimAt(shooter.world.cue.pos + Vec2.fromAngle(0.6) * 200);
    shooter.setPower(0.55);
    await run(1500);
    // ignore: avoid_print
    print('shooter angle ${shooter.aimAngle.toStringAsFixed(3)} power ${shooter.power} cue ${shooter.world.cue.pos.x},${shooter.world.cue.pos.y}');
    // ignore: avoid_print
    print('watcher angle ${watcher.aimAngle.toStringAsFixed(3)} power ${watcher.power} cue ${watcher.world.cue.pos.x},${watcher.world.cue.pos.y}');
    expect((watcher.aimAngle - shooter.aimAngle).abs(), lessThan(0.02));
    expect(watcher.power, closeTo(0.55, 0.01));
    expect(watcher.world.cue.pos.distanceTo(shooter.world.cue.pos), lessThan(0.5));

    shooter.aimAt(shooter.world.cue.pos + Vec2.fromAngle(-0.4) * 200);
    shooter.setPower(0);
    await run(1200);
    expect((watcher.aimAngle - shooter.aimAngle).abs(), lessThan(0.02));
    expect(watcher.power, closeTo(0, 0.01));

    // End the match so nothing is left running on the server.
    drivers[0].send({'type': 'leave'});
    await drivers[0].idle;
    for (final d in drivers) {
      d.dispose();
    }
    for (final c in controllers) {
      c.dispose();
    }
  });
}
