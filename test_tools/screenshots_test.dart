// Dev tool: renders the real screens to PNG files for visual review.
//   SHOTS_DIR=/tmp/shots flutter test test_tools/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:billiard_poker/core/app_state.dart';
import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/data/demo_data.dart';
import 'package:billiard_poker/features/game/game_controller.dart';
import 'package:billiard_poker/features/game/widgets/table_art.dart';
import 'package:billiard_poker/features/game/game_screen.dart';
import 'package:billiard_poker/features/game/widgets/card_view.dart';
import 'package:billiard_poker/features/home/home_screen.dart';
import 'package:billiard_poker/features/lobby/lobby_screen.dart';
import 'package:billiard_poker/features/misc/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _dir = Platform.environment['SHOTS_DIR'];
final _key = GlobalKey();

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    await loader.load();
  }

  await load('Orbitron', 'assets/fonts/Orbitron.ttf');
  await load('DMSerifDisplay', 'assets/fonts/DMSerifDisplay-Regular.ttf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  await load('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

Widget _app(Widget home) => ProviderScope(
      overrides: [audioProvider.overrideWithValue(AudioService(enabled: false))],
      child: RepaintBoundary(
        key: _key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildAppTheme(), home: home),
      ),
    );

Future<void> _settle(WidgetTester tester, {double seconds = 0}) async {
  // Let real asset decoding finish, then advance the fake clock in frames.
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  for (var t = 0.0; t < seconds; t += 0.05) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('screenshots', (tester) async {
    await tester.runAsync(_loadFonts);
    await tester.binding.setSurfaceSize(const Size(1950, 900));
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(_app(const HomeScreen()));
    await _settle(tester);
    await _shot(tester, '01_home');

    await tester.pumpWidget(_app(Scaffold(
      backgroundColor: const Color(0xFF1E1E21),
      body: Center(
        child: Wrap(spacing: 20, runSpacing: 20, children: [
          for (final skin in DemoData.tableSkins.take(5)) TableArt(skin: skin, width: 500),
        ]),
      ),
    )));
    await _settle(tester);
    await _shot(tester, '00_tables');

    await tester.pumpWidget(_app(const LobbyScreen()));
    await _settle(tester);
    await _shot(tester, '02_lobby');

    await tester.pumpWidget(_app(const SettingsScreen()));
    await _settle(tester);
    await _shot(tester, '03_settings');

    final config = MatchConfig(seed: 11, shotSeconds: 30, seats: [
      const SeatConfig(name: 'PLAYER1', avatar: 'asset:avatar_1'),
      for (var i = 0; i < 3; i++)
        SeatConfig(name: 'ENEMY ${i + 1}', avatar: 'asset:avatar_${i + 2}', isBot: true, botSkill: 0.9),
    ]);
    await tester.pumpWidget(_app(GameScreen(config: config)));
    await _settle(tester, seconds: 0.5);
    await _shot(tester, '04_break_spread');

    await tester.tap(find.byType(CardBack).at(16));
    await _settle(tester, seconds: 3.6);
    await _shot(tester, '05_break_order');

    await _settle(tester, seconds: 4.5);
    await _shot(tester, '06_dealt');

    for (var i = 0; i < 6; i++) {
      await _settle(tester, seconds: 7);
      final mine = find.byWidgetPredicate((w) => w is CardFace && !w.completed && !w.disabled);
      if (mine.evaluate().isNotEmpty) {
        await tester.tap(mine.first, warnIfMissed: false);
        await _settle(tester, seconds: 0.4);
      }
      await _shot(tester, '07_play_$i');
    }

    // Pass & play: device hand-off screen.
    final humans = MatchConfig(seed: 4, shotSeconds: 30, seats: [
      for (var i = 0; i < 4; i++)
        SeatConfig(name: 'PLAYER ${i + 1}', avatar: 'asset:avatar_${i + 1}'),
    ]);
    await tester.pumpWidget(_app(GameScreen(key: const ValueKey('pp'), config: humans)));
    await _settle(tester, seconds: 0.3);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byType(CardBack).at(i * 3));
      await _settle(tester, seconds: 0.2);
    }
    await _settle(tester, seconds: 8);
    await _shot(tester, '08_pass_and_play');

    // Bots only, played to the end: winner panel.
    final bots = MatchConfig(seed: 3, shotSeconds: 30, seats: [
      for (var i = 0; i < 4; i++)
        SeatConfig(name: 'ENEMY ${i + 1}', avatar: 'asset:avatar_${i + 1}', isBot: true, botSkill: 0.95),
    ]);
    await tester.pumpWidget(_app(GameScreen(key: const ValueKey('bots'), config: bots)));
    await _settle(tester);
    var banners = 0;
    for (var i = 0; i < 30000 && find.text('REMATCH').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (banners < 4 && i % 40 == 0 && find.textContaining('PENALTY').evaluate().isNotEmpty) {
        await _shot(tester, '09_penalty_${banners++}');
      }
    }
    await _settle(tester, seconds: 1);
    await _shot(tester, '10_winner');
  }, skip: _dir == null, timeout: const Timeout(Duration(minutes: 10)));
}
