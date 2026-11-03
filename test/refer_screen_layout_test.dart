import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/features/duel/refer_screen.dart';
import 'package:billiard_poker/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewports = <Size>[
  Size(915, 412),
  Size(640, 360),
  Size(1280, 800),
];

Map<String, dynamic> _manyReferrals(int count) => {
      'code': '482910',
      'percent': 5,
      'invited': count,
      'earnedToday': 120,
      'earnedMonth': 4500,
      'earned': 12800,
      'referredBy': '123456',
      'people': [
        for (var i = 0; i < count; i++)
          {
            'name': 'Player ${i + 1} With A Very Long Display Name',
            'earned': 100 + i * 37,
          },
      ],
    };

void main() {
  for (final size in _viewports) {
    testWidgets('ReferScreenContent ${size.width.toInt()}x${size.height.toInt()} many rows', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final friend = TextEditingController();
      addTearDown(friend.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: ReferScreenContent(
                info: _manyReferrals(48),
                t: AppStrings.en,
                phone: size.shortestSide <= 720,
                friendController: friend,
                applying: false,
                copied: false,
                error: null,
                onCopy: (_) {},
                onApply: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('REFERRED FRIENDS'), findsOneWidget);
      expect(find.text('Player 1 With A Very Long Display Name'), findsOneWidget);

      final list = find.byType(ListView);
      for (var i = 0; i < 8; i++) {
        await tester.drag(list, const Offset(0, -280));
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
    });
  }
}
