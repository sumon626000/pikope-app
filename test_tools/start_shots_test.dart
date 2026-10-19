// Dev tool: renders the loading and sign-in screens to PNG files.
//   SHOTS_DIR=/tmp/shots FLUTTER_ROOT=... flutter test test_tools/start_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:billiard_poker/core/app_state.dart';
import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/features/start/loading_screen.dart';
import 'package:billiard_poker/features/start/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _dir = Platform.environment['SHOTS_DIR'];
final _key = GlobalKey();

void main() {
  testWidgets('start screens', (tester) async {
    await tester.runAsync(() async {
      Future<void> load(String family, String path) async {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
        await loader.load();
      }

      await load('Orbitron', 'assets/fonts/Orbitron.ttf');
      await load('MaterialIcons',
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    });
    await tester.binding.setSurfaceSize(const Size(1950, 900));
    tester.view.devicePixelRatio = 1;

    Future<void> shot(Widget home, String name) async {
      await tester.pumpWidget(ProviderScope(
        key: ValueKey(name),
        overrides: [audioProvider.overrideWithValue(AudioService(enabled: false))],
        child: RepaintBoundary(
          key: _key,
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildAppTheme(), home: home),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.runAsync(() async {
        final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await shot(const LoginScreen(), 's_login');
    await shot(const LoadingScreen(), 's_loading');
    // Let the loading screen's timers finish so the test can end.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
  }, skip: _dir == null);
}
