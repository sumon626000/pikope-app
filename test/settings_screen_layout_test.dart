import 'package:billiard_poker/core/app_state.dart';
import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/features/misc/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone landscape + typical web landscape for settings (3-card layout).
const _viewports = <Size>[
  Size(915, 412),
  Size(640, 360),
  Size(1280, 800),
  Size(1920, 1080),
];

Widget _app() => ProviderScope(
      overrides: [audioProvider.overrideWithValue(AudioService(enabled: false))],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const SettingsScreen(),
      ),
    );

void main() {
  for (final size in _viewports) {
    testWidgets('SettingsScreen ${size.width.toInt()}x${size.height.toInt()} no overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_app());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);

      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isNotEmpty) {
        await tester.drag(scrollables.first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      expect(find.textContaining('Account', findRichText: true), findsWidgets);
    });
  }
}
