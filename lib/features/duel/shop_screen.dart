import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
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
import 'zini_pay_checkout.dart';

/// Shop-only accents (UI); logic unchanged.
abstract final class _ShopUi {
  // Matches site / coin-shop reference (navy + sky + green buy).
  static const cardFillTop = Color(0xFF0C1B44);
  static const cardFillMid = Color(0xFF091535);
  static const cardFillBot = Color(0xFF060E24);
  static const cardBorder = Color(0xFF1D3D82);
  static const cardBorderDim = Color(0xFF2A3558);
  static const bestBorder = Color(0xFFFFAA00);
  static const buyGreen = Color(0xFF00C675);
  static const buyGreenText = Color(0xFF032014);
  static const ribbonStart = Color(0xFFFF1B7A);
  static const ribbonEnd = Color(0xFFD40058);
  static const skyLine = Color(0xFF7DD3FC);
  static const tabGlow = Color(0xFF00D2FF);

  static String? bestValuePackId(List<CoinShopPack> packs) {
    String? id;
    var bestRatio = -1.0;
    for (final p in packs) {
      if (p.free || p.coins <= 0) continue;
      final ratio = p.receiveCoins / p.coins;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        id = p.id;
      }
    }
    return id;
  }

  static double coinArtSize(int coins) {
    if (coins >= 10000) return 52;
    if (coins >= 5000) return 48;
    if (coins >= 1000) return 44;
    if (coins >= 500) return 42;
    return 40;
  }

  static Widget packCoinArt(int coins) {
    final size = coinArtSize(coins);
    if (coins >= 200) {
      return SizedBox(
        width: 56,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(left: 2, bottom: 2, child: PikoCoinIcon(size: size * 0.78)),
            Positioned(right: 2, top: 0, child: PikoCoinIcon(size: size * 0.92)),
          ],
        ),
      );
    }
    return SizedBox(
      width: 56,
      height: 48,
      child: Center(child: PikoCoinIcon(size: size)),
    );
  }
}

/// Seven standard packs: 2-up on phones (last row full width), 3-up on wide screens.
class _CoinPackGrid extends StatelessWidget {
  const _CoinPackGrid({
    required this.packs,
    required this.columns,
    required this.bestId,
    required this.onBuy,
  });

  final List<CoinShopPack> packs;
  final int columns;
  final String? bestId;
  final Future<void> Function(CoinShopPack) onBuy;

  static const _gap = 12.0;
  static const _cardH = 168.0;

  Widget _card(CoinShopPack pack) {
    return SizedBox(
      height: _cardH,
      child: _CoinPackCard(
        pack: pack,
        isBestValue: bestId != null && pack.id == bestId,
        onTap: () => onBuy(pack),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (columns >= 3) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: _gap,
          crossAxisSpacing: _gap,
          mainAxisExtent: _cardH,
        ),
        itemCount: packs.length,
        itemBuilder: (context, i) => _card(packs[i]),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < packs.length;) {
      final remaining = packs.length - i;
      if (remaining == 1) {
        rows.add(_card(packs[i]));
        break;
      }
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _card(packs[i])),
            const SizedBox(width: _gap),
            Expanded(child: _card(packs[i + 1])),
          ],
        ),
      );
      i += 2;
      if (i < packs.length) {
        rows.add(const SizedBox(height: _gap));
      }
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

class _ShopScreenState extends ConsumerState<ShopScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _buyFreePack(CoinShopPack pack) async {
    final t = ref.read(stringsProvider);
    try {
      final received = await ref.read(lobbyProvider.notifier).buyCoinPack(pack.id);
      if (!mounted) return;
      showDuelMessage(context,
          title: t.picoCoin,
          body: t.youGetCoins(formatPicoCoins(received)),
          icon: Icons.check_circle_rounded);
    } on ApiException catch (e) {
      if (mounted) {
        showDuelMessage(context, title: t.picoCoin, body: t.maybeApi(e.message), icon: Icons.error_outline_rounded);
      }
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

    if (cfg.autoEnabled) {
      await openZiniPayDeposit(context, ref, config: cfg, bdt: pack.coins, packId: pack.id);
      return;
    }

    if (cfg.manualEnabled && cfg.agents.isNotEmpty) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF141A2E),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: _ManualDepositSheet(config: cfg, pack: pack),
        ),
      );
      return;
    }

    final t = ref.read(stringsProvider);
    if (mounted) {
      showDuelMessage(context, title: t.picoCoin, body: t.paymentUnavailable, icon: Icons.payment_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final lobby = ref.watch(lobbyProvider);
    final data = lobby.valueOrNull;
    final global = data?.coinShop.globalDiscountPercent ?? 0;

    return DuelPage(
      title: t.picoCoin,
      sub: t.shopSub(global),
      expanded: true,
      sideBack: true,
      contentTop: 198,
      child: lobby.valueOrNull == null
          ? Center(
              child: lobby.hasError
                  ? Text(t.offlineServer, style: AppText.label(20, color: DuelColors.red))
                  : const CircularProgressIndicator(color: DuelColors.silver))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: DuelColors.rim.withValues(alpha: 0.85)),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0E1433).withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicator: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _ShopUi.tabGlow, width: 3),
                      ),
                      boxShadow: [
                        BoxShadow(color: _ShopUi.tabGlow.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: -2),
                      ],
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: DuelColors.dim,
                    labelStyle: AppText.label(17, weight: FontWeight.w900),
                    unselectedLabelStyle: AppText.label(16, color: DuelColors.dim, weight: FontWeight.w700),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    tabs: [
                      Tab(text: t.tabBuy),
                      Tab(text: t.tabTransfer),
                      Tab(text: t.tabRedeem),
                      Tab(text: t.tabHistory),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _ShopUi.cardBorderDim.withValues(alpha: 0.7)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF0A1024).withValues(alpha: 0.92),
                          const Color(0xFF141C40).withValues(alpha: 0.75),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: DuelColors.blue.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _BuyTab(data: data!, onBuy: _onPackTap),
                          CoinTransferTab(config: data.coinTransfer, tutorialUrl: data.coinTutorials.transfer),
                          _RedeemTab(config: data.redeem, tutorialUrl: data.coinTutorials.redeem),
                          const _ActivityTab(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Shop tab content fills the tab area; panel stretches to at least full height.
class _ShopPanel extends StatelessWidget {
  const _ShopPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
              decoration: duelPanel(radius: 22),
              child: child,
            ),
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
    final packs = data.coinShop.packs;
    final bestId = _ShopUi.bestValuePackId(packs);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 880 ? 3 : 2;
        final tutorials = data.coinTutorials;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CoinTutorialVideoFrame(
                  youtubeUrl: tutorials.deposit,
                  title: t.coinTutorialDepositTitle,
                  tapHint: t.coinTutorialTapPlay,
                ),
                if (packs.isEmpty)
                  Center(child: Text(t.noPacks, style: AppText.label(18, color: DuelColors.dim)))
                else
                  _CoinPackGrid(
                    packs: packs,
                    columns: cols,
                    bestId: bestId,
                    onBuy: onBuy,
                  ),
              ],
            ),
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
  ConsumerState<_ManualDepositSheet> createState() => _ManualDepositSheetState();
}

class _ManualDepositSheetState extends ConsumerState<_ManualDepositSheet> {
  final _trx = TextEditingController();
  final _payer = TextEditingController();
  late String _provider;
  bool _busy = false;
  String? _error;

  int get _bdt => widget.pack.coins;

  int get _coins => widget.pack.receiveCoins;

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
        SnackBar(content: Text(t.copiedNumber(number), style: AppText.label(14)), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _submit() async {
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
      await ref.read(sessionProvider.notifier).submitDeposit(
            bdt: bdt,
            provider: _provider,
            trxId: _trx.text.trim(),
            payerNumber: _payer.text.trim(),
          );
      await ref.read(lobbyProvider.notifier).refresh();
      if (mounted) {
        Navigator.of(context).pop();
        showDuelMessage(context,
            title: t.requestSent,
            body: t.depositPendingBody(formatPicoCoins(_coins)),
            icon: Icons.check_circle_rounded);
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
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.addCoinTitle, style: AppText.label(28, color: DuelColors.gold, weight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                '${widget.pack.coins} BDT · ${t.youGetCoins(formatPicoCoins(_coins))}',
                style: AppText.label(18, color: DuelColors.silver, weight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(t.addCoinSteps, style: AppText.label(16, color: DuelColors.dim)),
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
                            Text(a.label, style: AppText.label(16, color: DuelColors.silver, weight: FontWeight.w800)),
                            Text(a.number, style: AppText.label(24, color: Colors.white, weight: FontWeight.w900)),
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
                      label: Text(a.label, style: AppText.label(16, weight: FontWeight.w800)),
                      selected: _provider == a.id,
                      onSelected: _busy ? null : (_) => setState(() => _provider = a.id),
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
                decoration: InputDecoration(
                  labelText: t.payerNumber,
                  hintText: '01XXXXXXXXX',
                  counterText: '',
                  labelStyle: AppText.label(16, color: DuelColors.dim),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _trx,
                style: input,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t.trxId,
                  labelStyle: AppText.label(16, color: DuelColors.dim),
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
  const _RedeemBalanceCard({required this.title, required this.amount, required this.accent});

  final String title;
  final String amount;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1428),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppText.label(16, color: DuelColors.dim, weight: FontWeight.w800),
            ),
          ),
          Text(amount, style: AppText.label(30, color: accent, weight: FontWeight.w900)),
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
      await ref.read(sessionProvider.notifier).cancelRedeem(widget.row['id'] as int);
      await ref.read(lobbyProvider.notifier).refresh();
      if (mounted) {
        widget.onCancelled();
        showDuelMessage(context, title: t.redeemCancel, body: t.redeemCancelled, icon: Icons.undo_rounded);
      }
    } on ApiException catch (e) {
      if (mounted) {
        showDuelMessage(context, title: t.redeemOff, body: t.maybeApi(e.message), icon: Icons.error_outline);
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
            child: Text(_busy ? '…' : t.redeemCancel, style: AppText.label(18, color: DuelColors.red, weight: FontWeight.w900)),
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
    _pending = ref.read(sessionProvider.notifier).redeemRequests().then(
          (list) => list.where((r) => r['status'] == 'pending').toList(),
        );
  }

  @override
  void dispose() {
    _coins.dispose();
    _wallet.dispose();
    super.dispose();
  }

  int? get _coinAmount => int.tryParse(_coins.text.replaceAll(RegExp(r'\D'), ''));

  int get _bdt {
    final c = _coinAmount ?? 0;
    final rate = widget.config.coinPerBdt;
    return rate <= 0 ? c : c ~/ rate;
  }

  Future<void> _submit() async {
    final t = ref.read(stringsProvider);
    final cfg = widget.config;
    final redeemable = ref.read(sessionProvider).redeemableCoins;
    if (!cfg.enabled) {
      setState(() => _error = t.redeemOff);
      return;
    }
    final coins = _coinAmount;
    final cap = redeemable < cfg.maxCoins ? redeemable : cfg.maxCoins;
    if (coins == null || coins < cfg.minCoins || coins > cfg.maxCoins) {
      setState(() => _error = t.redeemRange(formatCoins(cfg.minCoins), formatCoins(cfg.maxCoins)));
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
      await ref.read(sessionProvider.notifier).submitRedeem(
            coins: coins,
            walletProvider: _provider,
            walletNumber: _wallet.text.trim(),
          );
      await ref.read(lobbyProvider.notifier).refresh();
      if (mounted) {
        setState(_reloadPending);
        showDuelMessage(context,
            title: t.redeemSent,
            body: t.redeemSentBody(_bdt),
            icon: Icons.check_circle_rounded);
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
    final mainBalance = session.walletCoins;
    final redeemAvailable = session.redeemableCoins;
    final redeemCap = redeemAvailable < cfg.maxCoins ? redeemAvailable : cfg.maxCoins;
    if (!cfg.enabled) {
      return Center(
        child: Text(t.redeemTurnedOff, style: AppText.label(22, color: DuelColors.dim, weight: FontWeight.w800)),
      );
    }
    final input = AppText.label(28, color: Colors.white);
    const fieldPad = EdgeInsets.symmetric(horizontal: 22, vertical: 22);
    final fieldLabel = AppText.label(20, color: DuelColors.dim);
    return _ShopPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoinTutorialVideoFrame(
            youtubeUrl: widget.tutorialUrl,
            title: t.coinTutorialRedeemTitle,
            tapHint: t.coinTutorialTapPlay,
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
              future: _pending,
              builder: (context, snap) {
                final rows = snap.data ?? const [];
                if (rows.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t.redeemPendingTitle, style: AppText.label(22, color: DuelColors.silver, weight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    for (final r in rows)
                      _PendingRedeemRow(
                        row: r,
                        onCancelled: () => setState(_reloadPending),
                      ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
            Text(t.cashOutTitle, style: AppText.label(36, color: DuelColors.gold, weight: FontWeight.w900)),
            const SizedBox(height: 16),
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
            const SizedBox(height: 14),
            Text(
              t.redeemWinOnlyHint,
              style: AppText.label(18, color: DuelColors.dim),
            ),
            const SizedBox(height: 10),
            Text(
              t.redeemRateHint(cfg.coinPerBdt),
              style: AppText.label(18, color: DuelColors.dim),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _coins,
              style: input,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: t.coinAmountLabel,
                hintText: redeemCap >= cfg.minCoins
                    ? '${cfg.minCoins} – ${formatCoins(redeemCap)}'
                    : t.notEnoughRedeemable,
                contentPadding: fieldPad,
                labelStyle: fieldLabel,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Text(t.youReceiveBdt(_bdt), style: AppText.label(26, color: DuelColors.silver, weight: FontWeight.w800)),
            const SizedBox(height: 18),
            Text(t.walletType, style: AppText.label(20, color: DuelColors.dim)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final p in cfg.providers)
                  ChoiceChip(
                    label: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Text(p.label, style: AppText.label(22, weight: FontWeight.w800)),
                    ),
                    selected: _provider == p.id,
                    onSelected: _busy ? null : (_) => setState(() => _provider = p.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _wallet,
              style: input,
              keyboardType: TextInputType.phone,
              maxLength: 14,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: t.walletNumber,
                hintText: '01XXXXXXXXX',
                counterText: '',
                contentPadding: fieldPad,
                labelStyle: fieldLabel,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppText.label(22, color: DuelColors.red)),
            ],
            const SizedBox(height: 24),
            GameButton(
              label: _busy ? t.sending : t.submitRedeem,
              height: 88,
              fontSize: 26,
              onPressed: _busy ? null : _submit,
            ),
          ],
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

  void _reload() => setState(() => _feed = ref.read(sessionProvider.notifier).activity());

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
              body = Center(child: Text(t.historyLoadFail, style: AppText.label(20, color: DuelColors.red)));
            } else if (!snap.hasData) {
              body = const Center(child: CircularProgressIndicator(color: DuelColors.silver));
            } else if (snap.data!.isEmpty) {
              body = Center(child: Text(t.historyEmpty, style: AppText.label(22, color: DuelColors.dim)));
            } else {
              final rows = snap.data!;
              body = RefreshIndicator(
                color: DuelColors.gold,
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF1E2546)),
                  itemBuilder: (context, i) => _ActivityRow(item: rows[i]),
                ),
              );
            }
            return Container(
              width: double.infinity,
              height: constraints.maxHeight,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: duelPanel(radius: 22),
              child: body,
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
    final time = '${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
    final kind = item['kind'] as String;

    if (kind == 'match') {
      final won = item['won'] as bool;
      final coins = item['coins'] as int;
      final practice = item['mode'] == 'bots';
      return _rowShell(
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
      final peer = sent ? (item['toName'] as String? ?? '') : (item['fromName'] as String? ?? '');
      final peerId = sent ? item['toGameId'] : item['fromGameId'];
      return _rowShell(
        badge: sent ? t.badgeTransferSuccess : t.badgeTransfer,
        badgeColor: sent ? DuelColors.green : DuelColors.green,
        title: sent ? '→ $peer' : '← $peer',
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
        badge: t.statusLabel(status),
        badgeColor: color,
        title: '${t.badgeRedeem} · ${item['walletProviderLabel']}',
        sub: '${formatCoins(item['coins'] as int)} → ${item['bdt']} BDT · ${item['walletNumber']}',
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

  Widget _rowShell({
    required String badge,
    required Color badgeColor,
    required String title,
    required String sub,
    required int coins,
    required String time,
  }) {
    return SizedBox(
      height: 68,
      child: Row(
        children: [
          Container(
            width: 92,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badgeColor),
            ),
            child: Text(badge, style: AppText.label(13, color: badgeColor, weight: FontWeight.w900)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(17, weight: FontWeight.w800)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(13, color: DuelColors.dim)),
              ],
            ),
          ),
          if (coins != 0) ...[
            const PikoCoinIcon(size: 22),
            const SizedBox(width: 6),
            Text('${coins > 0 ? '+' : ''}${formatCoins(coins)}',
                style: AppText.label(18,
                    color: coins > 0 ? DuelColors.gold : DuelColors.red, weight: FontWeight.w900)),
          ],
          const SizedBox(width: 12),
          Text(time, style: AppText.label(13, color: DuelColors.dim)),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final bonus = pack.discountPercent;
    final borderColor = isBestValue ? _ShopUi.bestBorder : _ShopUi.cardBorder;
    final buyBdt = pack.free ? t.claimNow : '৳${formatCoins(pack.coins, compact: true)}';
    final amountLabel = formatCoins(pack.coins, compact: true);
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_ShopUi.cardFillTop, _ShopUi.cardFillMid, _ShopUi.cardFillBot],
          ),
          border: Border.all(
            color: borderColor.withValues(alpha: isBestValue ? 1 : 0.9),
            width: isBestValue ? 1.8 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isBestValue ? _ShopUi.bestBorder : Colors.black).withValues(alpha: isBestValue ? 0.4 : 0.45),
              blurRadius: isBestValue ? 16 : 14,
              offset: const Offset(0, 4),
            ),
            if (isBestValue)
              BoxShadow(color: _ShopUi.bestBorder.withValues(alpha: 0.15), blurRadius: 8, spreadRadius: -2),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(width: 4),
                        _ShopUi.packCoinArt(pack.coins),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                amountLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.label(20, color: Colors.white, weight: FontWeight.w900),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                t.youGetCoins(formatPicoCoins(pack.receiveCoins)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.label(10, color: _ShopUi.skyLine, weight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 34,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: _ShopUi.buyGreen,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Color(0x6600C675), blurRadius: 10, offset: Offset(0, 2)),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: pack.free
                          ? Text(buyBdt, style: AppText.label(12, color: _ShopUi.buyGreenText, weight: FontWeight.w900))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(buyBdt, style: AppText.label(12, color: _ShopUi.buyGreenText, weight: FontWeight.w900)),
                                Text('  •  ', style: AppText.label(10, color: _ShopUi.buyGreenText.withValues(alpha: 0.75))),
                                Text('${t.tabBuy} →', style: AppText.label(12, color: _ShopUi.buyGreenText, weight: FontWeight.w900)),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (bonus > 0) _BonusRibbon(percent: bonus),
            if (isBestValue)
              Positioned(
                top: 6,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFEAB308)]),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [BoxShadow(color: Color(0xCCFBBF24), blurRadius: 8)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium_rounded, size: 12, color: Colors.brown.shade900),
                      const SizedBox(width: 3),
                      Text('BEST VALUE', style: AppText.label(9, color: Colors.brown.shade900, weight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BonusRibbon extends StatelessWidget {
  const _BonusRibbon({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      child: SizedBox(
        width: 50,
        height: 50,
        child: OverflowBox(
          maxWidth: 90,
          maxHeight: 90,
          alignment: Alignment.topLeft,
          child: Transform.rotate(
            angle: -0.785398,
            child: Container(
              width: 72,
              margin: const EdgeInsets.only(top: 10, left: -18),
              padding: const EdgeInsets.symmetric(vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_ShopUi.ribbonStart, _ShopUi.ribbonEnd],
                ),
                boxShadow: [BoxShadow(color: _ShopUi.ribbonStart.withValues(alpha: 0.6), blurRadius: 6)],
              ),
              child: Text('+$percent%', style: AppText.label(10, color: Colors.white, weight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    );
  }
}
