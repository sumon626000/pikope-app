import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/push_service.dart';
import '../../data/api_client.dart';
import '../online/session.dart';

/// The two staked modes of the lobby.
enum DuelMode { billiard, eight, nine, ten, poker, ludo2, ludo4, carrom }

extension DuelModeInfo on DuelMode {
  String get apiName => name;
  String get title => switch (this) {
        DuelMode.billiard => 'BILLIARD',
        DuelMode.eight => '8-BALL',
        DuelMode.nine => '9-BALL',
        DuelMode.ten => '10-BALL',
        DuelMode.poker => 'BILLIARD POKER',
        DuelMode.ludo2 || DuelMode.ludo4 => 'LUDO',
        DuelMode.carrom => 'CARROM',
      };
  int get seats => this == DuelMode.poker || this == DuelMode.ludo4 ? 4 : 2;

  /// The server lobby only lists 'billiard' and 'poker' stakes; Ludo and
  /// carrom reuse the billiard ladder (prize scales with the seat count instead).
  String get stakeKey => this == DuelMode.poker ? 'poker' : 'billiard';
  bool get isPoker => this == DuelMode.poker;
}

/// API game key from a waiting room or challenge payload.
DuelMode? duelModeFromApi(String game) => switch (game) {
      'poker' => DuelMode.poker,
      'eight' => DuelMode.eight,
      'nine' => DuelMode.nine,
      'ten' => DuelMode.ten,
      'billiard' => DuelMode.billiard,
      'ludo2' => DuelMode.ludo2,
      'ludo4' => DuelMode.ludo4,
      'carrom' => DuelMode.carrom,
      _ => null,
    };

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.round() ?? fallback;
  return fallback;
}

class BetLevel {
  const BetLevel({
    required this.level,
    required this.name,
    required this.stake,
    required this.fee,
    required this.buyIn,
    required this.players,
    this.prize,
    this.minPrize,
    this.maxPrize,
  });

  final int level;
  final String name;
  final int stake;
  final int fee;
  final int buyIn;
  final int players;

  String get displayName => name.isNotEmpty ? name : '$stake';

  /// Billiard: what the winner takes.
  final int? prize;

  /// Billiard Poker: the smallest and the largest prize the jackpot can draw.
  final int? minPrize;
  final int? maxPrize;

  factory BetLevel.fromJson(Map<String, dynamic> j) => BetLevel(
        level: _asInt(j['level']),
        name: (j['name'] as String?)?.trim() ?? '',
        stake: _asInt(j['stake']),
        fee: _asInt(j['fee']),
        buyIn: _asInt(j['buyIn']),
        players: _asInt(j['players']),
        prize: j['prize'] == null ? null : _asInt(j['prize']),
        minPrize: j['minPrize'] == null ? null : _asInt(j['minPrize']),
        maxPrize: j['maxPrize'] == null ? null : _asInt(j['maxPrize']),
      );
}

class CoinShopPack {
  const CoinShopPack({
    required this.id,
    required this.name,
    required this.coins,
    required this.discountPercent,
    required this.globalDiscountPercent,
    required this.receiveCoins,
    required this.priceCoins,
    required this.free,
    required this.claimed,
  });

  final String id;
  final String name;
  final int coins;
  final int discountPercent;
  final int globalDiscountPercent;
  final int receiveCoins;
  final int priceCoins;
  final bool free;
  final bool claimed;

  factory CoinShopPack.fromJson(Map<String, dynamic> j) => CoinShopPack(
        id: j['id'] as String,
        name: j['name'] as String,
        coins: _asInt(j['coins']),
        discountPercent: _asInt(j['discountPercent']),
        globalDiscountPercent: _asInt(j['globalDiscountPercent']),
        receiveCoins: _asInt(j['receiveCoins']),
        priceCoins: _asInt(j['priceCoins']),
        free: j['free'] as bool? ?? false,
        claimed: j['claimed'] as bool? ?? false,
      );
}

class CoinDepositConfig {
  const CoinDepositConfig({
    required this.enabled,
    required this.manualEnabled,
    required this.autoEnabled,
    required this.minBdt,
    required this.maxBdt,
    required this.coinPerBdt,
    required this.maxPendingPerUser,
    required this.paymentType,
    required this.agents,
  });

  final bool enabled;
  final bool manualEnabled;
  final bool autoEnabled;
  final int minBdt;
  final int maxBdt;
  final int coinPerBdt;
  final int maxPendingPerUser;
  final String paymentType;
  final List<({String id, String label, String number})> agents;

  factory CoinDepositConfig.fromJson(Map<String, dynamic> j) => CoinDepositConfig(
        enabled: j['enabled'] as bool? ?? false,
        manualEnabled: j['manualEnabled'] as bool? ?? j['enabled'] as bool? ?? false,
        autoEnabled: j['autoEnabled'] as bool? ?? false,
        minBdt: j['minBdt'] as int? ?? 100,
        maxBdt: j['maxBdt'] as int? ?? 50000,
        coinPerBdt: j['coinPerBdt'] as int? ?? 1,
        maxPendingPerUser: j['maxPendingPerUser'] as int? ?? 3,
        paymentType: j['paymentType'] as String? ?? 'personal',
        agents: [
          for (final a in (j['agents'] as List? ?? const []).cast<Map<String, dynamic>>())
            (id: a['id'] as String, label: a['label'] as String, number: a['number'] as String),
        ],
      );
}

class CoinTransferConfig {
  const CoinTransferConfig({
    required this.enabled,
    required this.feePercent,
    required this.minCoins,
    required this.maxCoins,
  });

  final bool enabled;
  final int feePercent;
  final int minCoins;
  final int maxCoins;

  factory CoinTransferConfig.fromJson(Map<String, dynamic> j) => CoinTransferConfig(
        enabled: j['enabled'] as bool? ?? false,
        feePercent: j['feePercent'] as int? ?? 10,
        minCoins: j['minCoins'] as int? ?? 10,
        maxCoins: j['maxCoins'] as int? ?? 500000,
      );
}

class RedeemConfig {
  const RedeemConfig({
    required this.enabled,
    required this.minCoins,
    required this.maxCoins,
    required this.maxPendingPerUser,
    required this.coinPerBdt,
    required this.providers,
  });

  final bool enabled;
  final int minCoins;
  final int maxCoins;
  final int maxPendingPerUser;
  final int coinPerBdt;
  final List<({String id, String label})> providers;

  factory RedeemConfig.fromJson(Map<String, dynamic> j) => RedeemConfig(
        enabled: j['enabled'] as bool? ?? false,
        minCoins: j['minCoins'] as int? ?? 1000,
        maxCoins: j['maxCoins'] as int? ?? 200000,
        maxPendingPerUser: j['maxPendingPerUser'] as int? ?? 2,
        coinPerBdt: j['coinPerBdt'] as int? ?? 1,
        providers: [
          for (final p in (j['providers'] as List? ?? const []).cast<Map<String, dynamic>>())
            (id: p['id'] as String, label: p['label'] as String),
        ],
      );
}

class CoinShopInfo {
  const CoinShopInfo({required this.globalDiscountPercent, required this.packs});

  final int globalDiscountPercent;
  final List<CoinShopPack> packs;

  factory CoinShopInfo.fromJson(Map<String, dynamic> j) => CoinShopInfo(
        globalDiscountPercent: j['globalDiscountPercent'] as int? ?? 0,
        packs: [for (final p in (j['packs'] as List? ?? const []).cast<Map<String, dynamic>>()) CoinShopPack.fromJson(p)],
      );
}

class CueOffer {
  const CueOffer({required this.id, required this.name, required this.price, required this.currency, required this.owned});

  final String id;
  final String name;
  final int price;
  final String currency;
  final bool owned;

  factory CueOffer.fromJson(Map<String, dynamic> j) => CueOffer(
        id: j['id'] as String,
        name: j['name'] as String,
        price: j['price'] as int,
        currency: j['currency'] as String,
        owned: j['owned'] as bool,
      );
}

class PushConfig {
  const PushConfig({required this.enabled, required this.channelId, required this.channelName});

  final bool enabled;
  final String channelId;
  final String channelName;

  factory PushConfig.fromJson(Map<String, dynamic>? j) => PushConfig(
        enabled: j?['enabled'] as bool? ?? false,
        channelId: j?['channelId'] as String? ?? 'pikope_default',
        channelName: j?['channelName'] as String? ?? 'PikoPe',
      );
}

class DailyBonus {
  const DailyBonus({required this.available, required this.day, required this.rewards, required this.secondsToNext});

  final bool available;

  /// Step of the ladder that can be claimed now (or was claimed today).
  final int day;
  final List<({int coins, int gems})> rewards;
  final int secondsToNext;

  factory DailyBonus.fromJson(Map<String, dynamic> j) => DailyBonus(
        available: j['available'] as bool,
        day: j['day'] as int,
        rewards: [
          for (final r in (j['rewards'] as List).cast<Map<String, dynamic>>()) (coins: r['coins'] as int, gems: r['gems'] as int),
        ],
        secondsToNext: j['secondsToNext'] as int,
      );
}

class LobbyData {
  const LobbyData({
    required this.levels,
    required this.online,
    required this.jackpot,
    required this.daily,
    required this.cues,
    required this.boardPrices,
    required this.coinShop,
    required this.redeem,
    required this.coinDeposit,
    required this.coinTransfer,
    required this.push,
    required this.fetchedAt,
  });

  final Map<String, List<BetLevel>> levels;

  List<BetLevel> levelsFor(DuelMode mode) => levels[mode.stakeKey] ?? const [];
  final int online;
  final List<int> jackpot;
  final DailyBonus daily;
  final List<CueOffer> cues;
  final Map<String, Map<String, int>> boardPrices;
  final CoinShopInfo coinShop;
  final RedeemConfig redeem;
  final CoinDepositConfig coinDeposit;
  final CoinTransferConfig coinTransfer;
  final PushConfig push;
  final DateTime fetchedAt;

  static Map<String, Map<String, int>> _boardPricesFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, Map<String, int>>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      out[entry.key.toString()] = {
        for (final p in (entry.value as Map).entries)
          p.key.toString(): (p.value as num).toInt(),
      };
    }
    return out;
  }

  factory LobbyData.fromJson(Map<String, dynamic> j) => LobbyData(
        levels: {
          for (final key in const ['billiard', 'poker'])
            key: [
              for (final l in ((j['levels'] as Map<String, dynamic>)[key] as List).cast<Map<String, dynamic>>())
                BetLevel.fromJson(l),
            ],
        },
        online: j['online'] as int,
        jackpot: (j['jackpot'] as List).cast<int>(),
        daily: DailyBonus.fromJson(j['daily'] as Map<String, dynamic>),
        cues: [for (final c in (j['cues'] as List).cast<Map<String, dynamic>>()) CueOffer.fromJson(c)],
        boardPrices: _boardPricesFromJson(j['boardPrices']),
        coinShop: CoinShopInfo.fromJson(j['coinShop'] as Map<String, dynamic>? ?? const {'globalDiscountPercent': 0, 'packs': []}),
        redeem: RedeemConfig.fromJson(j['redeem'] as Map<String, dynamic>? ?? const {'enabled': false}),
        coinDeposit: CoinDepositConfig.fromJson(j['coinDeposit'] as Map<String, dynamic>? ?? const {'enabled': false}),
        coinTransfer: CoinTransferConfig.fromJson(j['coinTransfer'] as Map<String, dynamic>? ?? const {'enabled': false}),
        push: PushConfig.fromJson(j['push'] as Map<String, dynamic>?),
        fetchedAt: DateTime.now(),
      );
}

/// Wallet, bet levels, daily bonus and the cue shop, as the server has them.
class LobbyNotifier extends AsyncNotifier<LobbyData> {
  ApiClient get _api => ref.read(apiProvider)!;
  SessionNotifier get _session => ref.read(sessionProvider.notifier);

  @override
  Future<LobbyData> build() => _fetch();

  Future<LobbyData> _fetch() async {
    if (!Env.hasBackend) {
      throw ApiException(0, 'offline', 'This build has no game server.');
    }
    await _session.ensureSignedIn();
    final j = await _api.get('/lobby');
    _session.adopt(j['user'] as Map<String, dynamic>);
    final lobby = LobbyData.fromJson(j);
    if (lobby.push.enabled) {
      await PushService.configure(
        api: _api,
        enabled: true,
        channelId: lobby.push.channelId,
        channelName: lobby.push.channelName,
      );
    }
    return lobby;
  }

  /// Reloads quietly: the screens keep showing what they have meanwhile.
  Future<void> refresh() async {
    try {
      state = AsyncData(await _fetch());
    } on ApiException {
      // Keep the last good data; the next refresh tries again.
    }
  }

  Future<({int coins, int gems})> claimDaily() async {
    final j = await _api.post('/daily/claim');
    _session.adopt(j['user'] as Map<String, dynamic>);
    final reward = j['reward'] as Map<String, dynamic>;
    await refresh();
    return (coins: reward['coins'] as int, gems: reward['gems'] as int);
  }

  Future<void> buyCue(String id) async {
    _session.adopt((await _api.post('/cues/buy', {'id': id}))['user'] as Map<String, dynamic>);
    await refresh();
  }

  Future<void> equipCue(String id) async {
    _session.adopt((await _api.post('/me/cue', {'id': id}))['user'] as Map<String, dynamic>);
  }

  Future<int> buyCoinPack(String id) async {
    final j = await _api.post('/shop/coins/buy', {'id': id});
    _session.adopt(j['user'] as Map<String, dynamic>);
    await refresh();
    return j['receiveCoins'] as int;
  }
}

final lobbyProvider = AsyncNotifierProvider<LobbyNotifier, LobbyData>(LobbyNotifier.new);
