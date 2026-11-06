import 'package:billiard_poker/core/app_state.dart';
import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/features/carrom/carrom_lobby_screen.dart';
import 'package:billiard_poker/features/duel/bet_level_screen.dart';
import 'package:billiard_poker/features/duel/duel_home_screen.dart';
import 'package:billiard_poker/features/duel/lobby_data.dart';
import 'package:billiard_poker/features/duel/pool_hub_screen.dart';
import 'package:billiard_poker/features/ludo/ludo_lobby_screen.dart';
import 'package:billiard_poker/features/misc/how_to_play_screen.dart';
import 'package:billiard_poker/features/start/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Portrait phone and tablet viewports (9:16 and nearby).
const kPortraitViewports = <Size>[
  Size(360, 640),
  Size(390, 844),
  Size(412, 915),
  Size(768, 1024),
];

LobbyData _minimalTestLobby() => LobbyData(
  levels: const {'billiard': [], 'poker': [], 'eight': [], 'ludo2': []},
  online: 12,
  jackpot: const [2, 3, 5],
  daily: const DailyBonus(
    available: true,
    day: 1,
    rewards: [],
    secondsToNext: 0,
  ),
  cues: const [],
  boardPrices: const {},
  coinShop: const CoinShopInfo(globalDiscountPercent: 0, packs: []),
  redeem: const RedeemConfig(
    enabled: false,
    minCoins: 300,
    maxCoins: 200000,
    maxPendingPerUser: 2,
    coinPerBdt: 1,
    providers: [],
  ),
  coinDeposit: const CoinDepositConfig(
    enabled: false,
    manualEnabled: false,
    autoEnabled: false,
    minBdt: 100,
    maxBdt: 50000,
    coinPerBdt: 1,
    maxPendingPerUser: 3,
    paymentType: 'personal',
    agents: [],
  ),
  coinTransfer: const CoinTransferConfig(
    enabled: false,
    feePercent: 10,
    minCoins: 50,
    maxCoins: 500000,
  ),
  coinTutorials: const CoinTutorialVideos(
    deposit: '',
    redeem: '',
    transfer: '',
  ),
  push: const PushConfig(
    enabled: false,
    channelId: 'test',
    channelName: 'Test',
  ),
  fetchedAt: DateTime(2026, 1, 1),
);

class _TestLobbyNotifier extends LobbyNotifier {
  @override
  Future<LobbyData> build() async => _minimalTestLobby();
}

Widget _app(Widget home) => ProviderScope(
  overrides: [
    audioProvider.overrideWithValue(AudioService(enabled: false)),
    lobbyProvider.overrideWith(_TestLobbyNotifier.new),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: home),
);

Future<void> _portrait(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _expectClean(WidgetTester tester, String label) {
  final err = tester.takeException();
  expect(err, isNull, reason: label);
}

void main() {
  group('Portrait viewports', () {
    for (final size in kPortraitViewports) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('DuelHomeScreen @ $label', (tester) async {
        await _portrait(tester, size);
        await tester.pumpWidget(_app(const DuelHomeScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('POOL'), findsWidgets);
        expect(find.text('LUDO'), findsWidgets);
        expect(find.text('CARROM'), findsWidgets);
        _expectClean(tester, 'home $label');
      });

      testWidgets('PoolHubScreen @ $label', (tester) async {
        await _portrait(tester, size);
        await tester.pumpWidget(_app(const PoolHubScreen()));
        await tester.pump();
        expect(find.byType(PoolHubScreen), findsOneWidget);
        _expectClean(tester, 'pool hub $label');
      });

      testWidgets('LudoLobbyScreen @ $label', (tester) async {
        await _portrait(tester, size);
        await tester.pumpWidget(_app(const LudoLobbyScreen()));
        await tester.pump();
        expect(find.byType(LudoLobbyScreen), findsOneWidget);
        _expectClean(tester, 'ludo $label');
      });

      testWidgets('CarromLobbyScreen @ $label', (tester) async {
        await _portrait(tester, size);
        await tester.pumpWidget(_app(const CarromLobbyScreen()));
        await tester.pump();
        expect(find.byType(CarromLobbyScreen), findsOneWidget);
        _expectClean(tester, 'carrom $label');
      });

      testWidgets('LoginScreen @ $label', (tester) async {
        await _portrait(tester, size);
        await tester.pumpWidget(_app(const LoginScreen()));
        await tester.pump();
        expect(find.byType(LoginScreen), findsOneWidget);
        _expectClean(tester, 'login $label');
      });

      testWidgets('BetLevelScreen @ $label', (tester) async {
        await _portrait(tester, size);
        await tester.pumpWidget(
          _app(const BetLevelScreen(mode: DuelMode.eight)),
        );
        await tester.pump();
        expect(find.byType(BetLevelScreen), findsOneWidget);
        _expectClean(tester, 'stakes $label');
      });

      testWidgets('HowToPlayScreen @ $label', (tester) async {
        await _portrait(tester, size);
        await tester.pumpWidget(_app(const HowToPlayScreen()));
        await tester.pump();
        expect(find.byType(HowToPlayScreen), findsOneWidget);
        _expectClean(tester, 'help $label');
      });
    }
  });
}
