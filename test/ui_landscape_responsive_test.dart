import 'package:billiard_poker/core/app_state.dart';
import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/core/duel_ui.dart';
import 'package:billiard_poker/features/duel/duel_home_screen.dart';
import 'package:billiard_poker/features/duel/lobby_data.dart';
import 'package:billiard_poker/features/duel/pool_hub_screen.dart';
import 'package:billiard_poker/features/misc/how_to_play_screen.dart';
import 'package:billiard_poker/features/start/loading_screen.dart'
    show LoadingSplashBody;
import 'package:billiard_poker/features/start/login_screen.dart';
import 'package:billiard_poker/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Landscape viewports from docs/ui-overhaul/ROADMAP.md (Phase 7).
const kLandscapeViewports = <Size>[
  Size(640, 360),
  Size(800, 360),
  Size(915, 412),
  Size(1280, 800),
  Size(1920, 1080),
];

LobbyData _minimalTestLobby() => LobbyData(
  levels: const {'billiard': [], 'poker': []},
  online: 0,
  jackpot: const [2, 3, 5],
  daily: const DailyBonus(
    available: false,
    day: 0,
    rewards: [],
    secondsToNext: 3600,
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

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        audioProvider.overrideWithValue(AudioService(enabled: false)),
        lobbyProvider.overrideWith(_TestLobbyNotifier.new),
        ...overrides,
      ],
      child: MaterialApp(theme: buildAppTheme(), home: home),
    );

Future<void> _landscape(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
    tester.view.resetDevicePixelRatio();
  });
}

void _expectCleanLayout(WidgetTester tester, {String? label}) {
  final err = tester.takeException();
  expect(err, isNull, reason: label ?? 'layout should not throw');
}

void main() {
  group('Phase 7 landscape viewports', () {
    for (final size in kLandscapeViewports) {
      testWidgets(
        'DuelHomeScreen @ ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _landscape(tester, size);
          await tester.pumpWidget(_app(const DuelHomeScreen()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byType(DuelHomeScreen), findsOneWidget);
          _expectCleanLayout(tester, label: 'DuelHomeScreen $size');
        },
      );

      testWidgets(
        'LoadingSplashBody @ ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _landscape(tester, size);
          await tester.pumpWidget(
            _app(
              DuelCanvas(
                child: LoadingSplashBody(
                  message: 'Loading…',
                  progress: const SizedBox(height: 12),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(LoadingSplashBody), findsOneWidget);
          _expectCleanLayout(tester, label: 'LoadingSplashBody $size');
        },
      );

      testWidgets(
        'LoginScreen @ ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _landscape(tester, size);
          await tester.pumpWidget(_app(const LoginScreen()));
          await tester.pump();
          expect(find.byType(LoginScreen), findsOneWidget);
          _expectCleanLayout(tester, label: 'LoginScreen $size');
        },
      );

      testWidgets(
        'PoolHubScreen @ ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _landscape(tester, size);
          await tester.pumpWidget(_app(const PoolHubScreen()));
          await tester.pump();
          expect(find.byType(PoolHubScreen), findsOneWidget);
          _expectCleanLayout(tester, label: 'PoolHubScreen $size');
        },
      );

      testWidgets(
        'HowToPlayScreen @ ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _landscape(tester, size);
          await tester.pumpWidget(_app(const HowToPlayScreen()));
          await tester.pump();
          expect(find.byType(HowToPlayScreen), findsOneWidget);
          _expectCleanLayout(tester, label: 'HowToPlayScreen $size');
        },
      );
    }
  });
}
