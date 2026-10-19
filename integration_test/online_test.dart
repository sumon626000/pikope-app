// On-device online match. Needs the backend and stand-in opponents:
//   BOT_GAME=nine API_BASE_URL=http://127.0.0.1:8080 flutter test test_online/opponent_bot_test.dart &
//   flutter test integration_test/online_test.dart -d <device> \
//     --dart-define=API_BASE_URL=http://10.0.2.2:8080 --dart-define=ONLINE_GAME=9-BALL
import 'package:billiard_poker/features/game/game_controller.dart';
import 'package:billiard_poker/features/game/widgets/card_view.dart';
import 'package:billiard_poker/features/game/widgets/hud.dart';
import 'package:billiard_poker/features/game/widgets/table_view.dart';
import 'package:billiard_poker/features/online/game_link.dart';
import 'package:billiard_poker/features/pool/pool_controller.dart';
import 'package:billiard_poker/game/physics/table_geometry.dart';
import 'package:billiard_poker/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const gameTitle = String.fromEnvironment('ONLINE_GAME', defaultValue: '9-BALL');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> wait(WidgetTester tester, [int ms = 600]) => tester.pump(Duration(milliseconds: ms));
  bool has(Finder f) => f.evaluate().isNotEmpty;

  testWidgets('online $gameTitle against remote opponents', (tester) async {
    app.main();
    // Loading screen, then (first run) the sign-in screen.
    for (var i = 0; i < 20 && !has(find.text('PLAY AS GUEST')) && !has(find.text('LEADERBOARD')); i++) {
      await wait(tester, 500);
    }
    if (has(find.text('PLAY AS GUEST'))) {
      await tester.tap(find.text('PLAY AS GUEST'));
      await wait(tester, 1200);
    }
    await tester.tap(find.text(gameTitle).first);
    await wait(tester);
    await tester.tap(find.text('ONLINE'));
    for (var i = 0; i < 40 && !has(find.textContaining('GUEST')); i++) {
      await wait(tester, 500);
    }
    expect(find.textContaining('GUEST'), findsOneWidget, reason: 'guest sign-in failed');
    // ignore: avoid_print
    print('STEP: signed in as guest');
    await tester.tap(find.text('QUICK MATCH'));
    await wait(tester, 1500);

    // The room fills, then the match screen opens.
    final deadline = DateTime.now().add(const Duration(minutes: 30));
    for (var i = 0; i < 240 && !has(find.byType(TableView)); i++) {
      await wait(tester, 500);
    }
    expect(find.byType(TableView), findsOneWidget, reason: 'the match never started');
    // ignore: avoid_print
    print('STEP: match started');

    final table = tester.widget<TableView>(find.byType(TableView)).controller;
    var shots = 0, calls = 0;
    while (!has(find.text('HOME'))) {
      expect(DateTime.now().isBefore(deadline), isTrue, reason: 'match did not finish');
      await wait(tester, 250);
      if (table is PoolController) {
        if (table.choosingPushOut) {
          await tester.tap(find.text('SHOOT'));
        } else if (table.needsPocketCall) {
          final rect = tester.getRect(find.byType(TableView));
          final at = TableProjection(rect.size, table.viewRotated).toLocal(TableGeometry.pockets[calls++ % 6].aim);
          await tester.tapAt(rect.topLeft + at);
        } else if (table.canShoot) {
          await tester.drag(find.byType(PowerBar), const Offset(0, 36));
          shots++;
          await wait(tester, 400);
        }
      } else if (table is GameController) {
        if (table.breakPicker != null && has(find.byType(CardBack))) {
          await tester.tap(find.byType(CardBack).at(4 + shots % 20), warnIfMissed: false);
          await wait(tester, 800);
        } else if (has(find.text('DECLARE WINNER'))) {
          await tester.tap(find.text('DECLARE WINNER'));
        } else if (table.canShoot) {
          await tester.drag(find.byType(PowerBar), const Offset(0, 36));
          shots++;
          await wait(tester, 400);
        } else if (table.canAim) {
          final playable = find.byWidgetPredicate((w) => w is CardFace && !w.completed && !w.disabled);
          if (has(playable)) await tester.tap(playable.first, warnIfMissed: false);
        }
      }
    }
    expect(find.textContaining('WINNER'), findsWidgets);
    // The server simulated every shot; this device's animation of the same
    // strokes must have ended exactly where the server's did.
    final drift = table is PoolController ? table.replayDrift : (table as GameController).replayDrift;
    final link = (table is PoolController ? table.link : (table as GameController).link)! as OnlineGameDriver;
    // ignore: avoid_print
    print('STEP: transport ${link.pushedStates} states over WebSocket, ${link.polledStates} over HTTP');
    expect(link.pushedStates, greaterThan(link.polledStates), reason: 'the match did not run over the WebSocket');
    // ignore: avoid_print
    print('STEP: physics drift vs server $drift');
    expect(drift, lessThan(1e-9));
    expect(find.text('PLAY AGAIN'), findsOneWidget);
    expect(find.textContaining('COINS'), findsWidgets);
    // ignore: avoid_print
    print('STEP: online match finished after $shots of my shots');
    await tester.tap(find.text('HOME'));
    await wait(tester, 1500);
    expect(find.text('QUICK MATCH'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 40)));
}
