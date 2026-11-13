import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/widgets.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import 'lobby_data.dart';
import '../../l10n/strings.dart';
import 'coin_transfer_tab.dart';
import 'coin_tutorial_video.dart';
import 'shop_phone_layout.dart';
import 'shop_tab_insets.dart';
import 'nowpayments_checkout.dart';
import 'payment_method_chooser.dart';
import 'zini_pay_checkout.dart';
import '../start/auth_prompt.dart';

/// Shop-only accents (UI); logic unchanged.
abstract final class _ShopUi {
  // Pool City coin shop: blue pack cards, light rim, gold price button,
  // red "More %" badge.
  static const bestBorder = Color(0xFFF5B942);

  /// BUY tab: six standard packs (100 … 5,000 BDT) — no 10,000 tier on the grid.
  static List<CoinShopPack> packsForBuyTab(List<CoinShopPack> packs) {
    final list = [
      for (final p in packs)
        if (p.coins > 0 && p.coins < 10000) p,
    ]..sort((a, b) => a.coins.compareTo(b.coins));
    if (list.length <= 6) return list;
    return list.sublist(0, 6);
  }

  static String? bestValuePackId(List<CoinShopPack> packs) {
    String? id;
    var bestRatio = -1.0;
    for (final p in packs) {
      if (p.free || p.coins <= 0) continue;
      final ratio = p.depositReceiveCoins / p.coins;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        id = p.id;
      }
    }
    return id;
  }

  static double coinIconSize(int coins, double slot) {
    final base = slot * 0.88;
    if (coins >= 10000) return base.clamp(44, 72);
    if (coins >= 5000) return base.clamp(42, 68);
    if (coins >= 1000) return base.clamp(40, 64);
    if (coins >= 500) return base.clamp(38, 60);
    return base.clamp(36, 56);
  }

  /// [slot] is the square region width reserved for coin art (scales with card width).
  static Widget packCoinArt(int coins, double slot) {
    final icon = coinIconSize(coins, slot);
    final h = slot * 0.82;
    if (coins >= 200) {
      return SizedBox(
        width: slot,
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              left: slot * 0.06,
              bottom: 0,
              child: PikoCoinIcon(size: icon * 0.78),
            ),
            Positioned(
              right: slot * 0.06,
              top: 0,
              child: PikoCoinIcon(size: icon * 0.92),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: slot,
      height: h,
      child: Center(child: PikoCoinIcon(size: icon)),
    );
  }
}

/// Seven standard packs: 4+3 on wide landscape, else 3- or 2-up from measured width.
class _CoinPackGrid extends StatelessWidget {
  const _CoinPackGrid({
    required this.packs,
    required this.columns,
    required this.layoutWidth,
    required this.bestId,
    required this.onBuy,
    this.maxCardHeight,
    this.compact = false,
  });

  final List<CoinShopPack> packs;
  final int columns;
  final double layoutWidth;
  final String? bestId;
  final Future<void> Function(CoinShopPack) onBuy;

  /// When set (BUY tab), keeps two grid rows inside the visible tab viewport.
  final double? maxCardHeight;
  final bool compact;

  static const gap = 10.0;
  static const _gap = gap;

  static int columnsForWidth(double w) {
    if (w >= 820) return 4;
    if (w >= 540) return 3;
    return 2;
  }

  static double _cellWidth(double layoutWidth, int cols) =>
      (layoutWidth - (cols - 1) * _gap) / cols;

  static double cardHeightFor(
    double layoutWidth,
    int cols, {
    bool compact = false,
  }) {
    final cellW = _cellWidth(layoutWidth, cols);
    if (compact) return (cellW * 0.46).clamp(72.0, 176.0);
    return (cellW * 0.64).clamp(158.0, 212.0);
  }

  Widget _card(CoinShopPack pack, double cardH, {bool stretch = false}) {
    final card = _CoinPackCard(
      pack: pack,
      isBestValue: bestId != null && pack.id == bestId,
      onTap: () => onBuy(pack),
    );
    if (stretch) return card;
    return SizedBox(height: cardH, child: card);
  }

  Widget _rowCells(
    List<CoinShopPack> slice,
    double cardH, {
    bool stretch = false,
  }) {
    final gapW = compact ? 6.0 : _gap;
    return Row(
      crossAxisAlignment: stretch
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < slice.length; i++) ...[
          if (i > 0) SizedBox(width: gapW),
          Expanded(child: _card(slice[i], cardH, stretch: stretch)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cols = columns;
    var cardH = cardHeightFor(layoutWidth, cols, compact: compact);
    final cap = maxCardHeight;
    if (cap != null) {
      final minH = compact ? 68.0 : 140.0;
      cardH = cardH.clamp(minH, cap);
    }

    final gapH = compact ? 6.0 : _gap;
    // Reference tiles are a little taller than wide.
    final tileH = layoutWidth / cols * 1.12;
    if (compact && cols == 3 && packs.length == 6) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SizedBox(
              height: tileH,
              child: _rowCells(packs.sublist(0, 3), cardH, stretch: true),
            ),
          ),
          SizedBox(height: gapH),
          Flexible(
            child: SizedBox(
              height: tileH,
              child: _rowCells(packs.sublist(3, 6), cardH, stretch: true),
            ),
          ),
        ],
      );
    }

    // Reference layout: four packs, then three (seven standard packs).
    if (cols >= 4 && packs.length >= 7) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _rowCells(packs.sublist(0, 4), cardH),
          const SizedBox(height: _gap),
          _rowCells(packs.sublist(4, 7), cardH),
        ],
      );
    }

    if (cols >= 3) {
      final rowSlices = <List<CoinShopPack>>[];
      for (var i = 0; i < packs.length; i += cols) {
        final end = (i + cols > packs.length) ? packs.length : i + cols;
        rowSlices.add(packs.sublist(i, end));
      }
      final useFlex = compact && cap != null && rowSlices.length >= 2;
      if (useFlex) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rowSlices.length; r++) ...[
              if (r > 0) SizedBox(height: compact ? 6 : _gap),
              Flexible(
                child: SizedBox(
                  height: tileH,
                  child: _rowCells(rowSlices[r], cardH, stretch: true),
                ),
              ),
            ],
          ],
        );
      }
      final rows = <Widget>[];
      for (var i = 0; i < packs.length; i += cols) {
        final end = (i + cols > packs.length) ? packs.length : i + cols;
        final slice = packs.sublist(i, end);
        if (slice.length < cols) {
          rows.add(
            Row(
              children: [
                for (var j = 0; j < slice.length; j++) ...[
                  if (j > 0) SizedBox(width: compact ? 6 : _gap),
                  Expanded(child: _card(slice[j], cardH)),
                ],
              ],
            ),
          );
        } else {
          rows.add(_rowCells(slice, cardH));
        }
        if (end < packs.length) {
          rows.add(SizedBox(height: compact ? 6 : _gap));
        }
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    }

    final rows = <Widget>[];
    for (var i = 0; i < packs.length;) {
      final remaining = packs.length - i;
      if (remaining == 1) {
        rows.add(_card(packs[i], cardH));
        break;
      }
      rows.add(_rowCells([packs[i], packs[i + 1]], cardH));
      i += 2;
      if (i < packs.length) rows.add(const SizedBox(height: _gap));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// Pico coin: buy packs, redeem to mobile wallet, full activity history.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 3),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String? _freePackBusyId;

  Future<void> _buyFreePack(CoinShopPack pack) async {
    if (_freePackBusyId != null) return;
    final t = ref.read(stringsProvider);
    setState(() => _freePackBusyId = pack.id);
    try {
      final received = await ref
          .read(lobbyProvider.notifier)
          .buyCoinPack(pack.id);
      if (!mounted) return;
      showDuelMessage(
        context,
        title: t.picoCoin,
        body: t.youGetCoins(formatPicoCoins(received)),
        icon: Icons.check_circle_rounded,
      );
    } on ApiException catch (e) {
      if (mounted) {
        showDuelMessage(
          context,
          title: t.picoCoin,
          body: t.maybeApi(e.message),
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _freePackBusyId = null);
    }
  }

  Future<void> _onPackTap(CoinShopPack pack) async {
    final data = ref.read(lobbyProvider).valueOrNull;
    if (data == null) return;
    final cfg = data.coinDeposit;

    if (pack.free) {
      await _buyFreePack(pack);
      return;
    }

    if (!await requireRegisteredAccount(context, ref)) return;
    if (!mounted) return;

    final localOk = shopLocalPayAvailable(cfg);
    final cryptoOk = shopCryptoPayAvailable(cfg);
    final method = await showShopPaymentMethodChooser(
      context,
      localAvailable: localOk,
      cryptoAvailable: cryptoOk,
    );
    if (!mounted || method == null) {
      if (method == null && mounted && !localOk && !cryptoOk) {
        final t = ref.read(stringsProvider);
        showDuelMessage(
          context,
          title: t.picoCoin,
          body: t.paymentUnavailable,
          icon: Icons.payment_rounded,
        );
      }
      return;
    }

    if (method == ShopPayMethod.crypto) {
      await openNowPaymentsDeposit(
        context,
        ref,
        config: cfg,
        bdt: pack.coins,
        packId: pack.id,
      );
      return;
    }

    if (cfg.autoEnabled) {
      await openZiniPayDeposit(
        context,
        ref,
        config: cfg,
        bdt: pack.coins,
        packId: pack.id,
      );
      return;
    }

    if (cfg.manualEnabled && cfg.agents.isNotEmpty) {
      // Cap width on desktop / tablet so the sheet is not edge-to-edge.
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: BoxConstraints(
          maxWidth: PortraitWebLayout.phoneColumnMaxWidth + 24,
        ),
        builder: (ctx) => Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: const Color(0xFF141A2E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: _ManualDepositSheet(config: cfg, pack: pack),
            ),
          ),
        ),
      );
      return;
    }

    final t = ref.read(stringsProvider);
    if (mounted) {
      showDuelMessage(
        context,
        title: t.picoCoin,
        body: t.paymentUnavailable,
        icon: Icons.payment_rounded,
      );
    }
  }

  Widget _shopTabBar(AppStrings t, {required bool phone}) {
    // The reference's tab strip (Currency / Offers); ours has four tabs.
    return AnimatedBuilder(
      animation: _tabs,
      builder: (context, _) => PcTabs(
        labels: [t.tabBuy, t.tabTransfer, t.tabRedeem, t.tabHistory],
        index: _tabs.index,
        onChanged: (i) {
          AudioService.tap();
          _tabs.animateTo(i);
        },
      ),
    );
  }

  Widget _shopTabPanel(LobbyData data, {required bool phone}) {
    const radius = 8.0;
    return DecoratedBox(
      decoration: pcPanelDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: PcLegacyScale(
          child: TabBarView(
            controller: _tabs,
            children: [
              _BuyTab(data: data, onBuy: _onPackTap),
              CoinTransferTab(
                config: data.coinTransfer,
                tutorialUrl: data.coinTutorials.transfer,
              ),
              _RedeemTab(
                config: data.redeem,
                tutorialUrl: data.coinTutorials.redeem,
              ),
              const _ActivityTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shopBody(
    BuildContext context,
    AsyncValue<LobbyData> lobby,
    AppStrings t,
    LobbyData? data, {
    required bool phone,
  }) {
    if (data == null) {
      return Center(
        child: lobby.hasError
            ? Text(
                t.offlineServer,
                style: AppText.label(phone ? 16 : 20, color: DuelColors.red),
              )
            : const CircularProgressIndicator(color: DuelColors.silver),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _shopTabBar(t, phone: phone),
        const SizedBox(height: 18),
        Expanded(child: _shopTabPanel(data, phone: phone)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final lobby = ref.watch(lobbyProvider);
    final data = lobby.valueOrNull;
    final global = data?.coinShop.globalDiscountPercent ?? 0;
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final registered = hasRegisteredAccount(ref);

    // Pool City shop page: player header, tab strip, pack panel, the
    // five-tab bar with Shop lit.
    return PcPage(
      header: PcHeader(
        avatar: settings.avatar,
        name: settings.name,
        registered: registered,
        level: session.level,
        coins: lobbyDisplayCoins(ref),
        gems: registered ? session.gems : null,
        placeholder: t.signUpOrLogin,
        onProfile: () {},
        onWallet: () => _tabs.animateTo(0),
      ),
      panel: false,
      scroll: false,
      bodyPadding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      nav: duelTabNav(context, ref, active: 4),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (global > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
              child: Text(
                t.shopSub(global),
                textAlign: TextAlign.center,
                style: pcText(
                  26,
                  color: DesignColors.pcGold,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          Expanded(child: _shopBody(context, lobby, t, data, phone: false)),
        ],
      ),
    );
  }
}

/// Scrollable tab body; outer TabBarView already provides the panel chrome.
class _ShopTabScroll extends StatelessWidget {
  const _ShopTabScroll({required this.child, this.fitViewport = false});

  final Widget child;
  final bool fitViewport;

  @override
  Widget build(BuildContext context) {
    final phone = DesignBreakpoints.phoneLike(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = SizedBox(width: double.infinity, child: child);
        if (phone && fitViewport) {
          return Padding(
            padding: ShopTabInsets.scrollPhoneFit,
            child: SizedBox(
              height: constraints.maxHeight,
              width: double.infinity,
              child: content,
            ),
          );
        }
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: ShopTabInsets.forViewport(context),
          child: phone
              ? content
              : ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: content,
                ),
        );
      },
    );
  }
}

class _BuyTab extends ConsumerWidget {
  const _BuyTab({required this.data, required this.onBuy});

  final LobbyData data;
  final Future<void> Function(CoinShopPack) onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final packs = _ShopUi.packsForBuyTab(data.coinShop.packs);
    final bestId = _ShopUi.bestValuePackId(packs);
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = ShopPhoneLayout.phone(context);
        final cols = phone || packs.length == 6
            ? 3
            : _CoinPackGrid.columnsForWidth(constraints.maxWidth);
        final tutorials = data.coinTutorials;
        final hasTutorial = youtubeVideoId(tutorials.deposit) != null;
        final tutorialReserve = ShopPhoneLayout.tutorialBlockHeight(
          context,
          visible: hasTutorial,
        );
        final scrollPad = phone ? 20.0 : 28.0;
        final gap = ShopPhoneLayout.gridGap(context);
        final rowCount = packs.length == 6 && cols == 3
            ? 2
            : cols >= 4 && packs.length >= 7
            ? 2
            : (packs.length + cols - 1) ~/ cols;
        double? maxCardH;
        if (rowCount >= 1 && constraints.maxHeight.isFinite) {
          maxCardH = ShopPhoneLayout.cardHeightForRows(
            viewportHeight: constraints.maxHeight,
            rowCount: rowCount,
            gap: gap,
            reservedTop: tutorialReserve + scrollPad,
            safety: phone ? 6 : 0,
          );
        }
        final tutorial = CoinTutorialVideoFrame(
          youtubeUrl: tutorials.deposit,
          title: t.coinTutorialDepositTitle,
          tapHint: t.coinTutorialTapPlay,
          compact: phone,
        );
        if (packs.isEmpty) {
          return _ShopTabScroll(
            fitViewport: phone,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tutorial,
                Expanded(
                  child: Center(
                    child: Text(
                      t.noPacks,
                      style: AppText.label(18, color: DuelColors.dim),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        if (phone) {
          return _ShopTabScroll(
            fitViewport: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tutorial,
                Expanded(
                  child: _CoinPackGrid(
                    packs: packs,
                    columns: cols,
                    layoutWidth: constraints.maxWidth,
                    bestId: bestId,
                    onBuy: onBuy,
                    maxCardHeight: maxCardH,
                    compact: true,
                  ),
                ),
              ],
            ),
          );
        }
        return _ShopTabScroll(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tutorial,
              _CoinPackGrid(
                packs: packs,
                columns: cols,
                layoutWidth: constraints.maxWidth,
                bestId: bestId,
                onBuy: onBuy,
                maxCardHeight: maxCardH,
                compact: false,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Manual bKash/Nagad for the selected pack only (fixed BDT — no custom amount).
class _ManualDepositSheet extends ConsumerStatefulWidget {
  const _ManualDepositSheet({required this.config, required this.pack});

  final CoinDepositConfig config;
  final CoinShopPack pack;

  @override
  ConsumerState<_ManualDepositSheet> createState() =>
      _ManualDepositSheetState();
}

class _ManualDepositSheetState extends ConsumerState<_ManualDepositSheet> {
  final _trx = TextEditingController();
  final _payer = TextEditingController();
  late String _provider;
  bool _busy = false;
  String? _error;

  int get _bdt => widget.pack.coins;

  int get _coins => widget.pack.depositReceiveCoins;

  @override
  void initState() {
    super.initState();
    final agents = widget.config.agents;
    _provider = agents.isNotEmpty ? agents.first.id : 'bkash';
  }

  @override
  void dispose() {
    _trx.dispose();
    _payer.dispose();
    super.dispose();
  }

  Future<void> _copy(String number) async {
    final t = ref.read(stringsProvider);
    await Clipboard.setData(ClipboardData(text: number));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.copiedNumber(number), style: AppText.label(14)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final t = ref.read(stringsProvider);
    final cfg = widget.config;
    final bdt = _bdt;
    if (bdt < cfg.minBdt || bdt > cfg.maxBdt) {
      setState(() => _error = t.bdtRange(cfg.minBdt, cfg.maxBdt));
      return;
    }
    if (_trx.text.trim().length < 6) {
      setState(() => _error = t.enterTrxId);
      return;
    }
    if (_payer.text.replaceAll(RegExp(r'\D'), '').length < 11) {
      setState(() => _error = t.enterPayerPhone);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .submitDeposit(
            bdt: bdt,
            provider: _provider,
            trxId: _trx.text.trim(),
            payerNumber: _payer.text.trim(),
          );
      await ref.read(lobbyProvider.notifier).refresh();
      if (mounted) {
        Navigator.of(context).pop();
        showDuelMessage(
          context,
          title: t.requestSent,
          body: t.depositPendingBody(formatPicoCoins(_coins)),
          icon: Icons.check_circle_rounded,
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = t.maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final cfg = widget.config;
    final input = AppText.label(22, color: Colors.white);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.addCoinTitle,
                style: AppText.label(
                  28,
                  color: DuelColors.gold,
                  weight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.pack.coins} BDT · ${t.youGetCoins(formatPicoCoins(_coins))}',
                style: AppText.label(
                  18,
                  color: DuelColors.silver,
                  weight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t.addCoinSteps,
                style: AppText.label(16, color: DuelColors.dim),
              ),
              const SizedBox(height: 16),
              for (final a in cfg.agents)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.label,
                              style: AppText.label(
                                16,
                                color: DuelColors.silver,
                                weight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              a.number,
                              style: AppText.label(
                                24,
                                color: Colors.white,
                                weight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GameButton(
                        label: t.copy,
                        height: 48,
                        width: 100,
                        fontSize: 14,
                        onPressed: () => _copy(a.number),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  for (final a in cfg.agents)
                    ChoiceChip(
                      label: Text(
                        a.label,
                        style: AppText.label(16, weight: FontWeight.w800),
                      ),
                      selected: _provider == a.id,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _provider = a.id),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _payer,
                style: input,
                keyboardType: TextInputType.phone,
                maxLength: 14,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: pcFieldDecoration(
                  label: t.payerNumber,
                  hint: '01XXXXXXXXX',
                  phone: false,
                  accent: DuelColors.gold,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _trx,
                style: input,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: pcFieldDecoration(
                  label: t.trxId,
                  phone: false,
                  accent: DuelColors.silver,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: AppText.label(16, color: DuelColors.red)),
              ],
              const SizedBox(height: 16),
              GameButton(
                label: _busy ? t.sending : t.submitForApproval,
                height: 56,
                fontSize: 18,
                onPressed: _busy ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RedeemBalanceCard extends StatelessWidget {
  const _RedeemBalanceCard({
    required this.title,
    required this.amount,
    required this.accent,
    this.compact = false,
  });

  final String title;
  final String amount;
  final Color accent;
  final bool compact;

  Widget _amountLine({required double coinSize, required double fontSize}) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PikoCoinIcon(size: coinSize),
          SizedBox(width: compact ? 4 : 8),
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label(
              fontSize,
              color: accent,
              weight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 20,
        vertical: compact ? 6 : 18,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1428),
        borderRadius: BorderRadius.circular(compact ? 10 : 16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(
                    8.5,
                    color: DuelColors.dim,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                _amountLine(coinSize: 15, fontSize: 16),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppText.label(
                      16,
                      color: DuelColors.dim,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                _amountLine(coinSize: 22, fontSize: 28),
              ],
            ),
    );
  }
}

class _PendingRedeemRow extends ConsumerStatefulWidget {
  const _PendingRedeemRow({required this.row, required this.onCancelled});

  final Map<String, dynamic> row;
  final VoidCallback onCancelled;

  @override
  ConsumerState<_PendingRedeemRow> createState() => _PendingRedeemRowState();
}

class _PendingRedeemRowState extends ConsumerState<_PendingRedeemRow> {
  bool _busy = false;

  Future<void> _cancel() async {
    final t = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .cancelRedeem(widget.row['id'] as int);
      await ref.read(lobbyProvider.notifier).refresh();
      if (mounted) {
        widget.onCancelled();
        showDuelMessage(
          context,
          title: t.redeemCancel,
          body: t.redeemCancelled,
          icon: Icons.undo_rounded,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        showDuelMessage(
          context,
          title: t.redeemOff,
          body: t.maybeApi(e.message),
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final r = widget.row;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2140),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DuelColors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${formatCoins(r['coins'] as int)} → ${r['bdt']} BDT · ${r['walletProviderLabel']}',
              style: AppText.label(18, weight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _cancel,
            child: Text(
              _busy ? '…' : t.redeemCancel,
              style: AppText.label(
                18,
                color: DuelColors.red,
                weight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RedeemTab extends ConsumerStatefulWidget {
  const _RedeemTab({required this.config, required this.tutorialUrl});

  final RedeemConfig config;
  final String tutorialUrl;

  @override
  ConsumerState<_RedeemTab> createState() => _RedeemTabState();
}

class _RedeemTabState extends ConsumerState<_RedeemTab> {
  final _coins = TextEditingController();
  final _wallet = TextEditingController();
  String _provider = 'bkash';
  bool _busy = false;
  String? _error;
  late Future<List<Map<String, dynamic>>> _pending;

  @override
  void initState() {
    super.initState();
    if (widget.config.providers.isNotEmpty) {
      _provider = widget.config.providers.first.id;
    }
    _reloadPending();
  }

  void _reloadPending() {
    _pending = ref
        .read(sessionProvider.notifier)
        .redeemRequests()
        .then((list) => list.where((r) => r['status'] == 'pending').toList());
  }

  @override
  void dispose() {
    _coins.dispose();
    _wallet.dispose();
    super.dispose();
  }

  int? get _coinAmount =>
      int.tryParse(_coins.text.replaceAll(RegExp(r'\D'), ''));

  int get _bdt {
    final c = _coinAmount ?? 0;
    final rate = widget.config.coinPerBdt;
    return rate <= 0 ? c : c ~/ rate;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final t = ref.read(stringsProvider);
    if (!await requireRegisteredAccount(context, ref)) return;
    if (!mounted) return;
    final cfg = widget.config;
    final redeemable = ref.read(sessionProvider).redeemableCoins;
    if (!cfg.enabled) {
      setState(() => _error = t.redeemOff);
      return;
    }
    final coins = _coinAmount;
    final cap = redeemable < cfg.maxCoins ? redeemable : cfg.maxCoins;
    if (coins == null || coins < cfg.minCoins || coins > cfg.maxCoins) {
      setState(
        () => _error = t.redeemRange(
          formatCoins(cfg.minCoins),
          formatCoins(cfg.maxCoins),
        ),
      );
      return;
    }
    if (coins > redeemable) {
      setState(() => _error = t.notEnoughRedeemable);
      return;
    }
    if (cap < cfg.minCoins) {
      setState(() => _error = t.notEnoughRedeemable);
      return;
    }
    if (_wallet.text.replaceAll(RegExp(r'\D'), '').length < 11) {
      setState(() => _error = t.walletNumberInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .submitRedeem(
            coins: coins,
            walletProvider: _provider,
            walletNumber: _wallet.text.trim(),
          );
      await ref.read(lobbyProvider.notifier).refresh();
      if (mounted) {
        setState(_reloadPending);
        showDuelMessage(
          context,
          title: t.redeemSent,
          body: t.redeemSentBody(_bdt),
          icon: Icons.check_circle_rounded,
        );
        _coins.clear();
        _wallet.clear();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = t.maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final cfg = widget.config;
    final session = ref.watch(sessionProvider);
    final redeemCap = session.redeemableCoins < cfg.maxCoins
        ? session.redeemableCoins
        : cfg.maxCoins;
    if (!cfg.enabled) {
      return Center(
        child: Text(
          t.redeemTurnedOff,
          style: AppText.label(
            22,
            color: DuelColors.dim,
            weight: FontWeight.w800,
          ),
        ),
      );
    }
    final phone = ShopPhoneLayout.phone(context);
    final input = AppText.label(phone ? 16 : 28, color: Colors.white);
    return _ShopTabScroll(
      fitViewport: phone,
      child: phone
          ? LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _redeemTabFields(
                        t: t,
                        cfg: cfg,
                        redeemCap: redeemCap,
                        input: input,
                        phone: true,
                        scrollable: false,
                      ),
                    ],
                  ),
                );
              },
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _redeemTabFields(
                  t: t,
                  cfg: cfg,
                  redeemCap: redeemCap,
                  input: input,
                  phone: false,
                  scrollable: true,
                ),
              ],
            ),
    );
  }

  Widget _redeemTabFields({
    required AppStrings t,
    required RedeemConfig cfg,
    required int redeemCap,
    required TextStyle input,
    required bool phone,
    required bool scrollable,
  }) {
    final mainBalance = ref.watch(sessionProvider).walletCoins;
    final redeemAvailable = ref.watch(sessionProvider).redeemableCoins;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoinTutorialVideoFrame(
          youtubeUrl: widget.tutorialUrl,
          title: t.coinTutorialRedeemTitle,
          tapHint: t.coinTutorialTapPlay,
          compact: phone,
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _pending,
          builder: (context, snap) {
            final rows = snap.data ?? const [];
            if (rows.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.redeemPendingTitle,
                  style: AppText.label(
                    phone ? 12 : 22,
                    color: DuelColors.silver,
                    weight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: phone ? 4 : 10),
                for (final r in rows)
                  _PendingRedeemRow(
                    row: r,
                    onCancelled: () => setState(_reloadPending),
                  ),
                SizedBox(height: phone ? 6 : 20),
              ],
            );
          },
        ),
        if (!phone)
          Text(
            t.cashOutTitle,
            style: AppText.label(
              36,
              color: DuelColors.gold,
              weight: FontWeight.w900,
            ),
          ),
        if (!phone) const SizedBox(height: 16),
        if (phone)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _RedeemBalanceCard(
                  title: t.mainBalanceShort,
                  amount: formatCoins(mainBalance),
                  accent: DuelColors.silver,
                  compact: true,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _RedeemBalanceCard(
                  title: t.redeemAvailableShort,
                  amount: formatCoins(redeemAvailable),
                  accent: DuelColors.gold,
                  compact: true,
                ),
              ),
            ],
          )
        else ...[
          _RedeemBalanceCard(
            title: t.mainBalanceTitle,
            amount: formatCoins(mainBalance),
            accent: DuelColors.silver,
          ),
          const SizedBox(height: 12),
          _RedeemBalanceCard(
            title: t.redeemAvailableTitle,
            amount: formatCoins(redeemAvailable),
            accent: DuelColors.gold,
          ),
        ],
        SizedBox(height: phone ? 4 : 14),
        Text(
          t.redeemWinOnlyHint,
          maxLines: phone ? 2 : null,
          overflow: phone ? TextOverflow.ellipsis : null,
          style: AppText.label(phone ? 9 : 18, color: DuelColors.dim),
        ),
        if (!phone) ...[
          const SizedBox(height: 10),
          Text(
            t.redeemRateHint(cfg.coinPerBdt),
            style: AppText.label(18, color: DuelColors.dim),
          ),
        ],
        SizedBox(height: phone ? 6 : 22),
        TextField(
          controller: _coins,
          style: input,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: pcFieldDecoration(
            label: t.coinAmountLabel,
            hint: redeemCap >= cfg.minCoins
                ? '${cfg.minCoins} – ${formatCoins(redeemCap)}'
                : t.notEnoughRedeemable,
            phone: phone,
            accent: DuelColors.gold,
          ),
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(height: phone ? 4 : 10),
        Text(
          t.youReceiveBdt(_bdt),
          style: AppText.label(
            phone ? 13 : 26,
            color: DuelColors.silver,
            weight: FontWeight.w800,
          ),
        ),
        if (!phone) ...[
          const SizedBox(height: 18),
          Text(t.walletType, style: AppText.label(20, color: DuelColors.dim)),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: phone ? 4 : 12,
          runSpacing: phone ? 2 : 12,
          children: [
            for (final p in cfg.providers)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: phone ? 6 : 8,
                    vertical: phone ? 0 : 8,
                  ),
                  child: Text(
                    p.label,
                    style: AppText.label(
                      phone ? 10 : 22,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                selected: _provider == p.id,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _provider = p.id),
              ),
          ],
        ),
        SizedBox(height: phone ? 6 : 16),
        TextField(
          controller: _wallet,
          style: input,
          keyboardType: TextInputType.phone,
          maxLength: 14,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: pcFieldDecoration(
            label: t.walletNumber,
            hint: '01XXXXXXXXX',
            phone: phone,
            accent: DuelColors.silver,
          ),
        ),
        if (_error != null) ...[
          SizedBox(height: phone ? 4 : 10),
          Text(
            _error!,
            style: AppText.label(phone ? 11 : 22, color: DuelColors.red),
          ),
        ],
        SizedBox(height: phone ? 8 : 24),
        GameButton(
          label: _busy
              ? t.sending
              : (phone ? t.submitRedeemShort : t.submitRedeem),
          height: phone ? 36 : 88,
          fontSize: phone ? 12 : 26,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
    if (scrollable) return body;
    return Expanded(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: body,
      ),
    );
  }
}

class _ActivityTab extends ConsumerStatefulWidget {
  const _ActivityTab();

  @override
  ConsumerState<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<_ActivityTab> {
  late Future<List<Map<String, dynamic>>> _feed;

  @override
  void initState() {
    super.initState();
    _feed = ref.read(sessionProvider.notifier).activity();
  }

  void _reload() =>
      setState(() => _feed = ref.read(sessionProvider.notifier).activity());

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget body;
        final snap = _feed;
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: snap,
          builder: (context, snap) {
            if (snap.hasError) {
              body = Center(
                child: Text(
                  t.historyLoadFail,
                  style: AppText.label(20, color: DuelColors.red),
                ),
              );
            } else if (!snap.hasData) {
              body = const Center(
                child: CircularProgressIndicator(color: DuelColors.silver),
              );
            } else if (snap.data!.isEmpty) {
              body = Center(
                child: Text(
                  t.historyEmpty,
                  style: AppText.label(22, color: DuelColors.dim),
                ),
              );
            } else {
              final rows = snap.data!;
              body = RefreshIndicator(
                color: DuelColors.gold,
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFF1E2546)),
                  itemBuilder: (context, i) => _ActivityRow(item: rows[i]),
                ),
              );
            }
            return Padding(
              padding: ShopTabInsets.forViewport(context),
              child: SizedBox(
                width: double.infinity,
                height: constraints.maxHeight,
                child: body,
              ),
            );
          },
        );
      },
    );
  }
}

// Shared row layout for shop HISTORY tab.
class _ActivityRow extends ConsumerWidget {
  const _ActivityRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final at = DateTime.fromMillisecondsSinceEpoch(item['at'] as int);
    String two(int v) => v.toString().padLeft(2, '0');
    final time =
        '${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
    final kind = item['kind'] as String;

    if (kind == 'match') {
      final won = item['won'] as bool;
      final coins = item['coins'] as int;
      final practice = item['mode'] == 'bots';
      return _rowShell(
        context,
        badge: won ? t.badgeWin : t.badgeLoss,
        badgeColor: won ? DuelColors.green : DuelColors.red,
        title: t.gameTitleKey(item['game'] as String),
        sub: practice ? t.badgePractice : t.badgeMatch,
        coins: coins,
        time: time,
      );
    }
    if (kind == 'wallet') {
      final amount = item['amount'] as int;
      return _rowShell(
        context,
        badge: t.badgeCoin,
        badgeColor: DuelColors.gold,
        title: item['label'] as String? ?? item['reason'] as String,
        sub: t.balanceLine(formatCoins(item['balanceAfter'] as int)),
        coins: amount,
        time: time,
      );
    }
    if (kind == 'transfer') {
      final sent = item['direction'] == 'sent';
      final amount = item['amount'] as int;
      final fee = item['fee'] as int? ?? 0;
      final peer = sent
          ? (item['toName'] as String? ?? '')
          : (item['fromName'] as String? ?? '');
      final peerId = sent ? item['toGameId'] : item['fromGameId'];
      return _rowShell(
        context,
        badge: sent ? t.badgeTransferSuccess : t.badgeTransfer,
        badgeColor: sent ? DuelColors.green : DuelColors.green,
        title: sent ? '${t.transferHistorySentTitle} → $peer' : '← $peer',
        sub: sent
            ? '${t.transferHistorySuccess(amount, fee)} · ID $peerId'
            : '${t.transferHistoryReceived(amount)} · ID $peerId',
        coins: sent ? -(amount + fee) : amount,
        time: time,
      );
    }
    if (kind == 'redeem') {
      final status = item['status'] as String;
      final color = status == 'approved'
          ? DuelColors.green
          : status == 'rejected'
          ? DuelColors.red
          : status == 'cancelled'
          ? DuelColors.dim
          : DuelColors.gold;
      return _rowShell(
        context,
        badge: t.statusLabel(status),
        badgeColor: color,
        title: '${t.badgeRedeem} · ${item['walletProviderLabel']}',
        sub:
            '${formatCoins(item['coins'] as int)} → ${item['bdt']} BDT · ${item['walletNumber']}',
        coins: -(item['coins'] as int),
        time: time,
      );
    }
    if (kind == 'deposit') {
      final status = item['status'] as String;
      final color = status == 'approved'
          ? DuelColors.green
          : status == 'rejected'
          ? DuelColors.red
          : DuelColors.gold;
      return _rowShell(
        context,
        badge: t.statusLabel(status),
        badgeColor: color,
        title: '${t.badgeAdd} · ${item['providerLabel']}',
        sub: '${item['bdt']} BDT · Trx ${item['trxId']}',
        coins: status == 'approved' ? (item['coins'] as int) : 0,
        time: time,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _rowShell(
    BuildContext context, {
    required String badge,
    required Color badgeColor,
    required String title,
    required String sub,
    required int coins,
    required String time,
  }) {
    final phone = ShopPhoneLayout.phone(context);
    final rowH = phone ? 52.0 : 68.0;
    return SizedBox(
      height: rowH,
      child: Row(
        children: [
          Container(
            width: phone ? 72 : 92,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(vertical: phone ? 4 : 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badgeColor),
            ),
            child: Text(
              badge,
              style: AppText.label(
                phone ? 10 : 13,
                color: badgeColor,
                weight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(width: phone ? 8 : 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(
                    phone ? 12 : 17,
                    weight: FontWeight.w800,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(phone ? 10 : 13, color: DuelColors.dim),
                ),
              ],
            ),
          ),
          if (coins != 0) ...[
            PikoCoinIcon(size: phone ? 16 : 22),
            SizedBox(width: phone ? 4 : 6),
            Text(
              '${coins > 0 ? '+' : ''}${formatCoins(coins)}',
              style: AppText.label(
                phone ? 13 : 18,
                color: coins > 0 ? DuelColors.gold : DuelColors.red,
                weight: FontWeight.w900,
              ),
            ),
          ],
          SizedBox(width: phone ? 6 : 12),
          Text(
            time,
            style: AppText.label(phone ? 10 : 13, color: DuelColors.dim),
          ),
        ],
      ),
    );
  }
}

class _CoinPackCard extends ConsumerWidget {
  const _CoinPackCard({
    required this.pack,
    required this.onTap,
    this.isBestValue = false,
  });

  final CoinShopPack pack;
  final VoidCallback onTap;
  final bool isBestValue;

  /// Reference shop card: the amount on top, the coin pile, the gold price
  /// button, and a red "More x%" burst on packs with a bonus.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final bonus = pack.discountPercent;
        final price = pack.free
            ? titleCase(t.claimNow)
            : '৳ ${formatCoins(pack.coins)}';
        final btnH = (h * 0.2).clamp(22.0, 36.0);
        return GestureDetector(
          onTap: () {
            AudioService.tap();
            onTap();
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF6A56D8),
                  Color(0xFF3F2E9A),
                  Color(0xFF34257F),
                ],
              ),
              border: Border.all(
                color: isBestValue
                    ? _ShopUi.bestBorder
                    : const Color(0xFF9C8CF0),
                width: isBestValue ? 2 : 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(painter: _PackStripePainter()),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      w * 0.05,
                      h * 0.04,
                      w * 0.05,
                      w * 0.05,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatCoins(pack.depositReceiveCoins),
                            maxLines: 1,
                            style: pcText((w * 0.12).clamp(12.0, 18.0)),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: h * 0.03),
                            child: FittedBox(
                              child: _ShopUi.packCoinArt(pack.coins, 80),
                            ),
                          ),
                        ),
                        Container(
                          height: btnH,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFFFFCB45),
                                Color(0xFFF0A51A),
                                Color(0xFFD98A0C),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: const Color(0xFFFFE08A),
                              width: 1,
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              price,
                              maxLines: 1,
                              style: pcText((btnH * 0.5).clamp(11.0, 16.0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (bonus > 0)
                    Positioned(
                      right: -w * 0.04,
                      top: h * 0.36,
                      child: Transform.rotate(
                        angle: 0.22,
                        child: Container(
                          width: w * 0.36,
                          height: w * 0.36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFFF5A5A), Color(0xFFD81E2C)],
                            ),
                            border: Border.all(
                              color: const Color(0xFFFF9A9A),
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x88000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'More\n$bonus%',
                              textAlign: TextAlign.center,
                              style: pcText(10).copyWith(height: 1.05),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Faint diagonal bands across a shop card, as on the reference.
class _PackStripePainter extends CustomPainter {
  const _PackStripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final band = Paint()..color = Colors.white.withValues(alpha: 0.045);
    final step = size.width * 0.34;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawPath(
        Path()
          ..moveTo(x, size.height)
          ..lineTo(x + size.height, 0)
          ..lineTo(x + size.height + step * 0.45, 0)
          ..lineTo(x + step * 0.45, size.height)
          ..close(),
        band,
      );
    }
  }

  @override
  bool shouldRepaint(_PackStripePainter old) => false;
}
