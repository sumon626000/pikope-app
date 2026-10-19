import 'package:billiard_poker/core/app_state.dart';
import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/features/game/game_controller.dart';
import 'package:billiard_poker/features/game/game_screen.dart';
import 'package:billiard_poker/features/game/widgets/card_view.dart';
import 'package:billiard_poker/features/game/widgets/hud.dart';
import 'package:billiard_poker/features/game/widgets/table_view.dart';
import 'package:billiard_poker/features/home/home_screen.dart';
import 'package:billiard_poker/features/lobby/lobby_screen.dart';
import 'package:billiard_poker/features/pool/pool_controller.dart';
import 'package:billiard_poker/features/pool/pool_screen.dart';
import 'package:billiard_poker/game/physics/table_geometry.dart';
import 'package:billiard_poker/game/pool/pool_rules.dart';
import 'package:billiard_poker/game/models/playing_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget home) => ProviderScope(
      overrides: [audioProvider.overrideWithValue(AudioService(enabled: false))],
      child: MaterialApp(theme: buildAppTheme(), home: home),
    );

Future<void> useLandscape(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1950, 900));
  tester.view.devicePixelRatio = 1;
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> advance(WidgetTester tester, double seconds) async {
  for (var t = 0.0; t < seconds; t += 0.05) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('card face shows the rank top-left and bottom-right', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: CardFace(card: PlayingCard(12, Suit.hearts))),
    ));
    expect(find.text('Q'), findsNWidgets(2));
    expect(
        find.descendant(of: find.byType(CardFace), matching: find.byType(CustomPaint)), findsWidgets);
  });

  testWidgets('home leads to match setup', (tester) async {
    await useLandscape(tester);
    await tester.pumpWidget(app(const HomeScreen()));
    expect(find.text('PLAY VS BOTS'), findsOneWidget);
    expect(find.text('PASS & PLAY'), findsOneWidget);
    await tester.tap(find.text('PLAY VS BOTS'));
    await tester.pumpAndSettle();
    expect(find.byType(LobbyScreen), findsOneWidget);
    expect(find.text('BOT'), findsNWidgets(3));
    expect(find.text('START MATCH'), findsOneWidget);
  });

  testWidgets('match flow: break spread, pick, order, 7 cards dealt face-up to the viewer',
      (tester) async {
    await useLandscape(tester);
    final config = MatchConfig(seed: 11, shotSeconds: 30, seats: [
      const SeatConfig(name: 'PLAYER1', avatar: 'asset:avatar_1'),
      for (var i = 0; i < 3; i++)
        SeatConfig(name: 'ENEMY ${i + 1}', avatar: 'asset:avatar_2', isBot: true),
    ]);
    await tester.pumpWidget(app(GameScreen(config: config)));
    await tester.pump();

    expect(find.byType(CardBack), findsNWidgets(30));
    expect(find.textContaining('PICK A CARD'), findsOneWidget);
    expect(find.byType(SeatView), findsNWidgets(4));

    await tester.tap(find.byType(CardBack).at(16));
    await advance(tester, 3.6);
    expect(find.text('1ST'), findsOneWidget);
    expect(find.text('4TH'), findsOneWidget);

    await advance(tester, 4.5);
    // Viewer's 7 cards are face-up; 21 opponent cards stay face-down.
    expect(find.byType(CardFace), findsNWidgets(7));
    expect(find.byType(CardBack), findsNWidgets(21));
    expect(find.byType(ObjectivePanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a human reveals a card, pulls the power bar and the shot is played', (tester) async {
    await useLandscape(tester);
    final config = MatchConfig(seed: 11, shotSeconds: 30, seats: [
      const SeatConfig(name: 'PLAYER1', avatar: 'asset:avatar_1'),
      for (var i = 0; i < 3; i++)
        SeatConfig(name: 'ENEMY ${i + 1}', avatar: 'asset:avatar_2', isBot: true),
    ]);
    await tester.pumpWidget(app(GameScreen(config: config)));
    await tester.pump();
    await tester.tap(find.byType(CardBack).at(16));

    // Wait for the human's turn (bots may shoot first).
    await tester.pump();
    final myTurn = find.textContaining(RegExp('PLAYER1: (TAP|BREAK)'));
    for (var i = 0; i < 4000 && myTurn.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(myTurn, findsOneWidget);

    if (find.textContaining('TAP ONE OF YOUR CARDS').evaluate().isNotEmpty) {
      // Shooting without a revealed card is refused.
      await tester.drag(find.byType(PowerBar), const Offset(0, 250));
      await tester.pump();
      expect(find.textContaining('SHOOTS'), findsNothing);

      // Tapping one of your own balls on the cloth reveals its card.
      final table = tester.widget<TableView>(find.byType(TableView));
      final c = table.controller as GameController;
      final ball = c.current.pendingBalls.first;
      final projection = TableProjection(tester.getSize(find.byType(TableView)), c.viewRotated);
      await tester.tapAt(
          tester.getTopLeft(find.byType(TableView)) + projection.toLocal(c.world.balls[ball].pos));
      await tester.pump();
      expect(c.state.targetBall, ball);
      expect(c.state.selectedCard!.card.ball, ball);
      expect(find.textContaining('HIT BALL $ball FIRST'), findsOneWidget);
      expect(find.byType(ShootHint), findsOneWidget);

      // A ball that is not on your cards cannot be picked that way.
      final foreign = [for (var n = 1; n <= 13; n++) n]
          .firstWhere((n) => !c.current.requiredBalls.contains(n));
      expect(c.selectBall(foreign), isFalse);
      expect(c.state.targetBall, ball);
    }

    // Dragging on the cloth only aims; it must never fire the shot.
    await tester.drag(find.byType(TableView), const Offset(0, -150));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(TableView)) + const Offset(120, 40));
    await tester.pump();
    expect(find.text('PLAYER1 SHOOTS'), findsNothing);

    // The pull also works from the wide margin beside the thin bar.
    final bar = tester.getRect(find.byType(PowerBar));
    await tester.dragFrom(Offset(bar.right - 12, bar.top + 120), const Offset(0, 250));
    await tester.pump();
    expect(find.text('PLAYER1 SHOOTS'), findsOneWidget);

    // The shot resolves and play moves on without errors.
    await advance(tester, 12);
    expect(find.text('PLAYER1 SHOOTS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home offers four games; a pool game starts with two seats and can be played',
      (tester) async {
    await useLandscape(tester);
    await tester.pumpWidget(app(const HomeScreen()));
    for (final title in ['BILLIARD POKER', '8-BALL', '9-BALL', '10-BALL']) {
      expect(find.text(title), findsWidgets);
    }
    await tester.tap(find.text('9-BALL'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('PLAY VS BOT'));
    await tester.pumpAndSettle();
    expect(find.text('9-BALL - MATCH SETUP'), findsOneWidget);
    expect(find.text('BOT'), findsOneWidget);
    await tester.tap(find.text('START MATCH'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PoolScreen), findsOneWidget);
    expect(find.byType(AvatarSeat), findsNWidgets(2));

    // Play until the human has shot once (the bot may break first).
    final c = tester.widget<TableView>(find.byType(TableView)).controller as PoolController;
    for (var i = 0; i < 3000 && c.players[0].shots == 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (c.choosingPushOut) {
        await tester.tap(find.text('SHOOT'));
      } else if (c.canShoot) {
        await tester.drag(find.byType(PowerBar), const Offset(0, 200));
      }
    }
    expect(c.players[0].shots, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('8-ball: the 8 cannot be shot until a pocket is called by tapping it', (tester) async {
    await useLandscape(tester);
    const config = PoolMatchConfig(game: PoolGame.eightBall, seed: 5, seats: [
      SeatConfig(name: 'YOU', avatar: 'asset:avatar_1'),
      SeatConfig(name: 'PAL', avatar: 'asset:avatar_2'),
    ]);
    await tester.pumpWidget(app(const PoolScreen(config: config)));
    await advance(tester, 2.5);
    final c = tester.widget<TableView>(find.byType(TableView)).controller as PoolController;

    // Jump to the end game: the shooter has cleared their group.
    final me = c.state.turn;
    c.state
      ..isBreakShot = false
      ..ballInHand = false
      ..behindHeadString = false;
    c.players[me].group = PoolGroup.solids;
    c.players[1 - me].group = PoolGroup.stripes;
    for (var b = 1; b <= 7; b++) {
      c.world.balls[b].pocketed = true;
    }
    c.answerPushOut(shoot: true); // no-op outside a push out
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.onEight, isTrue);
    expect(c.canShoot, isFalse);

    final table = find.byType(TableView);
    final projection = TableProjection(tester.getSize(table), c.viewRotated);
    await tester.tapAt(tester.getTopLeft(table) + projection.toLocal(TableGeometry.pockets[2].aim));
    await tester.pump();
    expect(c.state.calledPocket, 2);
    expect(c.canShoot, isTrue);
    expect(tester.takeException(), isNull);
  });
}
