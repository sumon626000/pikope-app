import 'package:billiard_poker/core/app_state.dart';
import 'package:billiard_poker/core/app_theme.dart';
import 'package:billiard_poker/core/audio_service.dart';
import 'package:billiard_poker/features/duel/duel_home_screen.dart';
import 'package:billiard_poker/features/duel/lobby_data.dart';
import 'package:billiard_poker/features/duel/shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewports = <Size>[
  Size(915, 412),
  Size(640, 360),
  Size(1280, 800),
];

LobbyData _shopLobby() => LobbyData(
      levels: const {'billiard': [], 'poker': []},
      online: 0,
      jackpot: const [2, 3, 5],
      daily: const DailyBonus(available: false, day: 0, rewards: [], secondsToNext: 3600),
      cues: const [],
      boardPrices: const {},
      coinShop: CoinShopInfo(
        globalDiscountPercent: 5,
        packs: [
          for (final coins in [100, 200, 300, 500, 1000, 5000, 10000])
            CoinShopPack(
              id: 'pack$coins',
              name: '$coins',
              coins: coins,
              discountPercent: coins == 5000 ? 10 : 0,
              globalDiscountPercent: 5,
              receiveCoins: coins,
              priceCoins: coins,
              free: coins == 100,
              claimed: false,
            ),
        ],
      ),
      redeem: const RedeemConfig(
        enabled: true,
        minCoins: 300,
        maxCoins: 200000,
        maxPendingPerUser: 2,
        coinPerBdt: 1,
        providers: [],
      ),
      coinDeposit: const CoinDepositConfig(
        enabled: true,
        manualEnabled: false,
        autoEnabled: false,
        minBdt: 100,
        maxBdt: 50000,
        coinPerBdt: 1,
        maxPendingPerUser: 3,
        paymentType: 'personal',
        agents: [],
      ),
      coinTransfer: const CoinTransferConfig(enabled: true, feePercent: 10, minCoins: 50, maxCoins: 500000),
      coinTutorials: const CoinTutorialVideos(deposit: '', redeem: '', transfer: ''),
      push: const PushConfig(enabled: false, channelId: 't', channelName: 'T'),
      fetchedAt: DateTime(2026, 1, 1),
    );

class _TestLobbyNotifier extends LobbyNotifier {
  @override
  Future<LobbyData> build() async => _shopLobby();
}

void main() {
  for (final size in _viewports) {
    testWidgets('ShopScreen ${size.width.toInt()}x${size.height.toInt()} no overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioProvider.overrideWithValue(AudioService(enabled: false)),
            lobbyProvider.overrideWith(_TestLobbyNotifier.new),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: const ShopScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  }
}
