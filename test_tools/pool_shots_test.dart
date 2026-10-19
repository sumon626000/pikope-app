// Dev tool: renders the home screen and the three pool games to PNG files.
//   SHOTS_DIR=/tmp/shots FLUTTER_ROOT=... flutter test test_tools/pool_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:billiard_poker/core/app_state.dart';
import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/features/game/game_controller.dart' show SeatConfig;
import 'package:billiard_poker/features/home/home_screen.dart';
import 'package:billiard_poker/features/pool/pool_controller.dart';
import 'package:billiard_poker/features/pool/pool_screen.dart';
import 'package:billiard_poker/game/pool/pool_rules.dart';
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
  final root = Platform.environment['FLUTTER_ROOT']!;
  await load('MaterialIcons', '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

Widget _app(Widget home) => ProviderScope(
      overrides: [audioProvider.overrideWithValue(AudioService(enabled: false))],
      child: RepaintBoundary(
        key: _key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildAppTheme(), home: home),
      ),
    );

Future<void> _settle(WidgetTester tester, {double seconds = 0}) async {
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
  testWidgets('pool screenshots', (tester) async {
    await tester.runAsync(_loadFonts);
    await tester.binding.setSurfaceSize(const Size(1950, 900));
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(_app(const HomeScreen()));
    await _settle(tester);
    await tester.tap(find.text('8-BALL'));
    await _settle(tester, seconds: 0.4);
    await _shot(tester, 'p0_home');

    for (final game in PoolGame.values) {
      final config = PoolMatchConfig(game: game, seed: 2, seats: const [
        SeatConfig(name: 'PLAYER1', avatar: 'asset:avatar_1', isBot: true, botSkill: 0.9),
        SeatConfig(name: 'ENEMY 1', avatar: 'asset:avatar_2', isBot: true, botSkill: 0.9),
      ]);
      await tester.pumpWidget(_app(PoolScreen(key: ValueKey(game), config: config)));
      await _settle(tester, seconds: 1);
      await _shot(tester, 'p_${game.name}_0_rack');
      await _settle(tester, seconds: 22);
      await _shot(tester, 'p_${game.name}_1_play');
      for (var i = 0; i < 12000 && find.text('REMATCH').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _settle(tester, seconds: 0.6);
      await _shot(tester, 'p_${game.name}_2_over');
    }
  }, skip: _dir == null, timeout: const Timeout(Duration(minutes: 10)));
}
