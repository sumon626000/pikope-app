// On-device end-to-end run of the real app:
//   flutter test integration_test/full_app_test.dart -d <device>
import 'package:billiard_poker/core/env.dart';
import 'package:billiard_poker/features/game/widgets/card_view.dart';
import 'package:billiard_poker/features/game/widgets/hud.dart';
import 'package:billiard_poker/features/game/widgets/table_view.dart';
import 'package:billiard_poker/features/pool/pool_controller.dart';
import 'package:billiard_poker/game/physics/table_geometry.dart';
import 'package:billiard_poker/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> wait(WidgetTester tester, [int ms = 600]) => tester.pump(Duration(milliseconds: ms));

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).first);
    await wait(tester, 900);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back'));
    await wait(tester, 900);
  }

  bool has(Finder f) => f.evaluate().isNotEmpty;

  /// Types into the profile name field. The field is driven directly: with a
  /// real on-screen keyboard attached (emulator), the test framework's
  /// simulated typing is overwritten by the keyboard's own state.
  Future<void> typeName(WidgetTester tester, String name) async {
    final field = tester.widget<TextField>(find.byType(TextField));
    field.controller!.text = name;
    field.onChanged!(name);
    await wait(tester, 1500);
  }

  int gamesPlayed() {
    final text = (find.textContaining('GAMES').evaluate().first.widget as Text).data!;
    return int.parse(RegExp(r'(\d+) GAMES').firstMatch(text)!.group(1)!);
  }

  testWidgets('whole app: menus, settings, all four games to a winner, rematch, quit',
      (tester) async {
    final log = <String>[];
    void step(String s) {
      log.add(s);
      // ignore: avoid_print
      print('STEP: $s');
    }

    app.main();
    // Loading screen, then (first run) the sign-in screen.
    for (var i = 0; i < 20 && !has(find.text('PLAY AS GUEST')) && !has(find.text('LEADERBOARD')); i++) {
      await wait(tester, 500);
    }
    if (has(find.text('PLAY AS GUEST'))) {
      await tester.tap(find.text('PLAY AS GUEST'));
      await wait(tester, 1200);
    }
    expect(find.text('PLAY VS BOTS'), findsOneWidget);
    final gamesBefore = gamesPlayed();
    step('home shown, games so far: $gamesBefore');

    // --- information screens
    await tapText(tester, 'HOW TO PLAY');
    expect(find.text('DECLARING'), findsWidgets);
    await back(tester);
    await tapText(tester, 'LEADERBOARD');
    // With a game server the table is fetched (after a guest sign-in).
    for (var i = 0; i < 30 && !has(find.textContaining('WINS')); i++) {
      await wait(tester, 500);
    }
    expect(find.textContaining('WINS'), findsWidgets);
    await back(tester);
    await tapText(tester, 'ONLINE');
    if (Env.hasBackend) {
      // Signs in as a guest and offers the online options.
      await wait(tester, 2500);
      expect(find.text('QUICK MATCH'), findsOneWidget);
      expect(find.textContaining('GUEST'), findsOneWidget);
      await back(tester);
    } else {
      expect(find.textContaining('online rooms are off'), findsOneWidget);
      await tapText(tester, 'GOT IT');
      expect(find.textContaining('online rooms are off'), findsNothing);
    }
    step('how-to-play, leaderboard, online notice ok');

    // --- profile & settings
    await tapText(tester, 'PROFILE & TABLES');
    await typeName(tester, 'FARID');
    final scrollable = find.byType(Scrollable).first;
    for (final label in ['CLASSIC GREEN', 'OFF', 'ON', '20 SEC', 'HARD']) {
      await tester.scrollUntilVisible(find.text(label), 120, scrollable: scrollable);
      await wait(tester, 300);
      await tapText(tester, label);
    }
    await back(tester);
    expect(find.text('FARID'), findsOneWidget);
    step('name, table, sound, shot clock, bot level changed and shown on home');

    // --- pass & play setup
    await tapText(tester, 'PASS & PLAY');
    expect(find.text('HUMAN'), findsNWidgets(3));
    await tapText(tester, 'HUMAN');
    expect(find.text('HUMAN'), findsNWidgets(2));
    expect(find.text('BOT'), findsOneWidget);
    await back(tester);
    step('pass & play setup toggles ok');

    // --- a full match against bots
    await tapText(tester, 'PLAY VS BOTS');
    expect(find.text('BOT'), findsNWidgets(3));
    await tapText(tester, 'START MATCH');
    await wait(tester, 1200);
    expect(find.byType(CardBack), findsNWidgets(30));
    await tester.tap(find.byType(CardBack).at(12));
    step('match started, break card picked');

    // Pause and resume once the cards are dealt.
    await wait(tester, 9000);
    await tester.tap(find.text('MENU').first);
    await wait(tester, 800);
    expect(find.text('QUIT MATCH'), findsOneWidget);
    await tapText(tester, 'RESUME');
    expect(find.text('QUIT MATCH'), findsNothing);
    step('pause / resume ok');

    var myShots = 0, declared = 0, aimDrags = 0;
    final deadline = DateTime.now().add(const Duration(minutes: 25));
    while (!has(find.text('REMATCH'))) {
      expect(DateTime.now().isBefore(deadline), isTrue, reason: 'match did not finish in time');
      await wait(tester, 250);
      if (has(find.text('DECLARE WINNER'))) {
        await tester.tap(find.text('DECLARE WINNER'));
        declared++;
        continue;
      }
      if (has(find.textContaining('TAP ONE OF YOUR CARDS'))) {
        final playable = find.byWidgetPredicate((w) => w is CardFace && !w.completed && !w.disabled);
        if (has(playable)) await tester.tap(playable.first, warnIfMissed: false);
        continue;
      }
      if (has(find.textContaining('HIT BALL')) || has(find.textContaining('BREAK!'))) {
        if (myShots % 4 == 1) {
          // Exercise drag-aiming too; it must not fire the shot.
          await tester.drag(find.byType(TableView), const Offset(6, -30));
          aimDrags++;
          await wait(tester, 150);
        }
        await tester.drag(find.byType(PowerBar), const Offset(0, 36));
        myShots++;
        await wait(tester, 400);
      }
    }
    step('match finished: my shots $myShots, aim drags $aimDrags, declared $declared');
    expect(find.text('WINNER'), findsWidgets);

    // --- rematch, then quit from the pause menu
    await tapText(tester, 'REMATCH');
    await wait(tester, 1200);
    expect(find.byType(CardBack), findsWidgets);
    expect(find.text('REMATCH'), findsNothing);
    await tester.tap(find.text('MENU').first);
    await wait(tester, 800);
    await tapText(tester, 'QUIT MATCH');
    await wait(tester, 1200);
    expect(find.text('PLAY VS BOTS'), findsOneWidget);
    expect(gamesPlayed(), gamesBefore + 1);
    final afterPoker = gamesPlayed();
    step('rematch and quit ok; games counter ${gamesPlayed()}');

    // --- the three two-player pool games, each played to a winner
    for (final title in ['9-BALL', '8-BALL', '10-BALL']) {
      await tapText(tester, title);
      await tapText(tester, 'PLAY VS BOT');
      expect(find.text('$title - MATCH SETUP'), findsOneWidget);
      expect(find.text('BOT'), findsOneWidget);
      await tapText(tester, 'START MATCH');
      await wait(tester, 1500);
      final c = tester.widget<TableView>(find.byType(TableView)).controller as PoolController;
      final poolDeadline = DateTime.now().add(const Duration(minutes: 12));
      var shots = 0, calls = 0;
      while (!has(find.text('REMATCH'))) {
        expect(DateTime.now().isBefore(poolDeadline), isTrue, reason: '$title did not finish');
        await wait(tester, 250);
        if (c.choosingPushOut) {
          await tester.tap(find.text('SHOOT'));
        } else if (c.needsPocketCall) {
          // Call a pocket by tapping it on the table.
          final rect = tester.getRect(find.byType(TableView));
          final at = TableProjection(rect.size, c.viewRotated).toLocal(TableGeometry.pockets[calls % 6].aim);
          await tester.tapAt(rect.topLeft + at);
          calls++;
        } else if (c.canShoot) {
          await tester.drag(find.byType(PowerBar), const Offset(0, 36));
          shots++;
          await wait(tester, 400);
        }
      }
      expect(find.textContaining('WINNER'), findsWidgets);
      step('$title finished: my shots $shots, pocket calls $calls, '
          'winner ${c.players[c.state.winner!].name} (${c.state.winReason})');
      await tapText(tester, 'HOME');
      await wait(tester, 1200);
      expect(find.text('PLAY VS BOT'), findsOneWidget);
    }
    await tapText(tester, 'BILLIARD POKER');
    expect(gamesPlayed(), afterPoker + 3);

    // --- restore the default name for the next person
    await tapText(tester, 'PROFILE & TABLES');
    await typeName(tester, 'PLAYER1');
    await back(tester);
    expect(find.text('PLAYER1'), findsOneWidget);
    step('done');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
