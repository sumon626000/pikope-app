import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/features/duel/refer_screen.dart';
import 'package:billiard_poker/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewports = <Size>[Size(915, 412), Size(640, 360), Size(1280, 800)];

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

Map<String, dynamic> _emptyReferral() => {
  'code': '260734',
  'percent': 1,
  'invited': 0,
  'earnedToday': 0,
  'earnedMonth': 0,
  'earned': 0,
  'referredBy': null,
  'people': <Map<String, dynamic>>[],
};

void main() {
  testWidgets('ReferScreenContent 915x412 empty + friend ID no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(915, 412);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final friend = TextEditingController();
    addTearDown(friend.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 915,
            height: 412,
            child: Column(
              children: [
                const SizedBox(height: 44),
                Expanded(
                  child: ReferScreenContent(
                    info: _emptyReferral(),
                    t: AppStrings.en,
                    phone: true,
                    friendController: friend,
                    applying: false,
                    copied: false,
                    error: null,
                    onCopy: (_) {},
                    onApply: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('260734'), findsOneWidget);
  });

  testWidgets(
    'ReferScreenContent 1544x720 empty Samsung landscape no overflow',
    (tester) async {
      tester.view.physicalSize = const Size(1544, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final friend = TextEditingController();
      addTearDown(friend.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 1544,
              height: 720,
              child: Column(
                children: [
                  const SizedBox(height: 44),
                  Expanded(
                    child: ReferScreenContent(
                      info: _emptyReferral(),
                      t: AppStrings.en,
                      phone: true,
                      friendController: friend,
                      applying: false,
                      copied: false,
                      error: null,
                      onCopy: (_) {},
                      onApply: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ReferScreenContent 915x412 scrolls 120 referral rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(915, 412);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final friend = TextEditingController();
    addTearDown(friend.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 915,
            height: 412,
            child: Column(
              children: [
                const SizedBox(height: 44),
                Expanded(
                  child: ReferScreenContent(
                    info: _manyReferrals(120),
                    t: AppStrings.en,
                    phone: true,
                    friendController: friend,
                    applying: false,
                    copied: false,
                    error: null,
                    onCopy: (_) {},
                    onApply: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('REFERRED FRIENDS'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Player 120 With A Very Long Display Name'),
      200,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text('Player 120 With A Very Long Display Name'),
      findsOneWidget,
    );
  });

  for (final size in _viewports) {
    testWidgets(
      'ReferScreenContent ${size.width.toInt()}x${size.height.toInt()} many rows',
      (tester) async {
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
        expect(
          find.text('Player 1 With A Very Long Display Name'),
          findsOneWidget,
        );

        if (size.shortestSide <= 720) {
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -320),
          );
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
      },
    );
  }
}
