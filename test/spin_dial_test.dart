import "package:billiard_poker/core/app_state.dart";
import "package:billiard_poker/core/app_theme.dart";
import "package:billiard_poker/core/audio_service.dart";
import "package:billiard_poker/features/game/game_controller.dart" show SeatConfig;
import "package:billiard_poker/features/game/widgets/hud.dart";
import "package:billiard_poker/features/game/widgets/table_view.dart";
import "package:billiard_poker/features/pool/pool_controller.dart";
import "package:billiard_poker/features/pool/pool_screen.dart";
import "package:billiard_poker/game/physics/physics_world.dart";
import "package:billiard_poker/game/physics/vec2.dart";
import "package:billiard_poker/game/pool/pool_rules.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

Future<void> advance(WidgetTester tester, double seconds) async {
  for (var t = 0.0; t < seconds; t += 0.05) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets("portrait spin tap and drag update hit point", (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const config = PoolMatchConfig(
      game: PoolGame.eightBall,
      seed: 5,
      seats: [
        SeatConfig(name: "YOU", avatar: "asset:avatar_1"),
        SeatConfig(name: "PAL", avatar: "asset:avatar_2"),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [audioProvider.overrideWithValue(AudioService(enabled: false))],
      child: MaterialApp(theme: buildAppTheme(), home: const PoolScreen(config: config)),
    ));
    await advance(tester, 2.5);
    final c = tester.widget<TableView>(find.byType(TableView)).controller as PoolController;
    expect(c.canAim, isTrue);

    final spin = find.byType(SpinControl);
    expect(spin, findsOneWidget);
    final rect = tester.getRect(spin);
    expect(rect.width, greaterThan(40));

    await tester.tapAt(rect.center + const Offset(12, -10));
    await tester.pump();
    expect(c.spin.length, greaterThan(0.15));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.timedDrag(spin, const Offset(-22, 18), const Duration(milliseconds: 200));
    await tester.pump();
    expect(c.spin.x, lessThan(0));
    expect(c.spin.y, lessThan(0));
  });

  test("follow spin pushes cue forward after contact", () {
    Vec2 after(double spinY) {
      final w = PhysicsWorld();
      for (final b in w.balls) { b.pocketed = true; b.vel = Vec2.zero; }
      w.balls[0].pocketed = false;
      w.balls[0].pos = const Vec2(400, 200);
      w.balls[1].pocketed = false;
      w.balls[1].pos = const Vec2(520, 200);
      w.shoot(0, 0.4, spinY: spinY);
      Vec2? vel;
      for (var i = 0; i < 5000 && w.isMoving; i++) {
        final had = w.outcome.firstContact != null;
        w.step();
        if (!had && w.outcome.firstContact != null) vel = w.cue.vel;
      }
      return vel ?? Vec2.zero;
    }
    expect(after(1).x, greaterThan(100));
    expect(after(-1).x, lessThan(-100));
  });
}
