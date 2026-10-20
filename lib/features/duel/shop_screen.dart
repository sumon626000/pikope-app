import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../online/session.dart';
import 'board_shop.dart';
import 'duel_chrome.dart';
import 'lobby_data.dart';
import '../../l10n/strings.dart';
import 'coin_transfer_tab.dart';
import 'zini_pay_checkout.dart';

/// Pico coin: buy packs, redeem to mobile wallet, full activity history.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this, initialIndex: widget.initialTab.clamp(0, 4));
  CoinShopPack? _selectedPack;
  int _packQty = 1;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openPack(CoinShopPack pack) {
    setState(() {
      _selectedPack = pack;
      _packQty = 1;
    });
    _tabs.animateTo(1);
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
      child: lobby.valueOrNull == null
          ? Center(
              child: lobby.hasError
                  ? Text(t.offlineServer, style: AppText.label(20, color: DuelColors.red))
                  : const CircularProgressIndicator(color: DuelColors.silver))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: DuelColors.gold,
                  indicatorWeight: 4,
                  labelStyle: AppText.label(24, weight: FontWeight.w900),
                  unselectedLabelStyle: AppText.label(22, color: DuelColors.dim, weight: FontWeight.w700),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  tabs: [
                    Tab(text: t.tabBuy),
                    Tab(text: t.tabAdd),
                    Tab(text: t.tabTransfer),
                    Tab(text: t.tabRedeem),
                    Tab(text: t.tabHistory),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _BuyTab(data: data!, onBuy: _openPack),
                      _DepositTab(
                        config: data.coinDeposit,
                        pack: _selectedPack,
                        packs: data.coinShop.packs,
                        qty: _packQty,
                        onPickPack: (p) => setState(() {
                          _selectedPack = p;
                          _packQty = 1;
                        }),
                        onQty: (q) => setState(() => _packQty = q),
                      ),
                      CoinTransferTab(config: data.coinTransfer),
                      _RedeemTab(config: data.redeem),
                      const _ActivityTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _BuyTab extends ConsumerWidget {
  const _BuyTab({required this.data, required this.onBuy});

  final LobbyData data;
  final void Function(CoinShopPack) onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final packs = data.coinShop.packs;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.packsTitle, style: AppText.label(26, color: DuelColors.gold, weight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (packs.isEmpty)
            Text(t.noPacks, style: AppText.label(18, color: DuelColors.dim))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final pack in packs)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: _CoinPackCard(
                        pack: pack,
                        onTap: () => onBuy(pack),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),
          Row(
            children: [
              _ShopDoor(label: t.poolTableBtn, color: DuelColors.green, icon: Icons.crop_16_9_rounded, onTap: () => pushScreen(context, const BoardShopScreen(kind: BoardKind.pool))),
              const SizedBox(width: 16),
              _ShopDoor(label: t.carromTableBtn, color: const Color(0xFFD9A34A), icon: Icons.grid_on_rounded, onTap: () => pushScreen(context, const BoardShopScreen(kind: BoardKind.carrom))),
              const SizedBox(width: 16),
              _ShopDoor(label: t.ludoBoardBtn, color: const Color(0xFFE8721C), icon: Icons.casino_rounded, onTap: () => pushScreen(context, const BoardShopScreen(kind: BoardKind.ludo))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShopDoor extends StatelessWidget {
  const _ShopDoor({required this.label, required this.color, required this.icon, required this.onTap});

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          AudioService.tap();
          onTap();
        },
        child: Container(
          height: 104,
          decoration: duelPanel(radius: 16, rim: color, glow: true),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(width: 12),
              Text(label, style: AppText.label(24, color: Colors.white, weight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepositTab extends ConsumerStatefulWidget {
  const _DepositTab({
    required this.config,
    this.pack,
    this.packs = const [],
    this.qty = 1,
    this.onPickPack,
    this.onQty,
  });

  final CoinDepositConfig config;
  final CoinShopPack? pack;
  final List<CoinShopPack> packs;
  final int qty;
  final ValueChanged<CoinShopPack>? onPickPack;
  final ValueChanged<int>? onQty;

  @override
  ConsumerState<_DepositTab> createState() => _DepositTabState();
}

class _DepositTabState extends ConsumerState<_DepositTab> {
  final _bdt = TextEditingController();
  final _trx = TextEditingController();
  final _payer = TextEditingController();
  String _provider = 'bkash';
  bool _busy = false;
  String? _error;
  late bool _autoMode;

  @override
  void initState() {
    super.initState();
    final agents = widget.config.agents;
    if (agents.isNotEmpty) _provider = agents.first.id;
    final cfg = widget.config;
    _autoMode = cfg.autoEnabled && (!cfg.manualEnabled || cfg.agents.isEmpty);
    _syncPackAmount();
  }

  @override
  void didUpdateWidget(_DepositTab old) {
    super.didUpdateWidget(old);
    if (old.pack?.id != widget.pack?.id || old.qty != widget.qty) _syncPackAmount();
  }

  void _syncPackAmount() {
    final pack = widget.pack;
    if (pack == null) return;
    final total = pack.coins * widget.qty;
    final text = '$total';
    if (_bdt.text != text) _bdt.text = text;
  }

  @override
  void dispose() {
    _bdt.dispose();
    _trx.dispose();
    _payer.dispose();
    super.dispose();
  }

  int? get _amount => int.tryParse(_bdt.text.replaceAll(RegExp(r'\D'), ''));

  int get _coins {
    final pack = widget.pack;
    if (pack != null) return pack.receiveCoins * widget.qty;
    final a = _amount ?? 0;
    final r = widget.config.coinPerBdt;
    return r <= 0 ? a : a * r;
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
    if (!cfg.manualEnabled || cfg.agents.isEmpty) {
      setState(() => _error = t.manualAddOff);
      return;
    }
    final bdt = _amount;
    if (bdt == null || bdt < cfg.minBdt || bdt > cfg.maxBdt) {
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
        showDuelMessage(context,
            title: t.requestSent,
            body: t.depositPendingBody(formatPicoCoins(_coins)),
            icon: Icons.check_circle_rounded);
        _bdt.clear();
        _trx.clear();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = t.maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _packStepper() {
    final unit = widget.pack?.coins ?? 0;
    final canAdd = unit * (widget.qty + 1) <= widget.config.maxBdt;
    final canSub = widget.qty > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          _stepButton(Icons.remove_rounded, canSub, () => widget.onQty?.call(widget.qty - 1)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '${widget.qty} × $unit',
              textAlign: TextAlign.center,
              style: AppText.label(28, color: Colors.white, weight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 14),
          _stepButton(Icons.add_rounded, canAdd, () => widget.onQty?.call(widget.qty + 1)),
        ],
      ),
    );
  }

  Widget _addModePicker(AppStrings t, bool manualOk, bool autoOk) {
    if (!manualOk || !autoOk) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          ChoiceChip(
            label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(t.addCoinManual, style: AppText.label(22, weight: FontWeight.w900)),
            ),
            selected: !_autoMode,
            onSelected: _busy ? null : (_) => setState(() => _autoMode = false),
          ),
          ChoiceChip(
            label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(t.addCoinAuto, style: AppText.label(22, weight: FontWeight.w900)),
            ),
            selected: _autoMode,
            onSelected: _busy ? null : (_) => setState(() => _autoMode = true),
          ),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled
          ? () {
              AudioService.tap();
              onTap();
            }
          : null,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: duelPanel(radius: 16, rim: enabled ? DuelColors.gold : DuelColors.rim),
        child: Icon(icon, color: enabled ? DuelColors.gold : DuelColors.dim, size: 36),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final cfg = widget.config;
    final manualOk = cfg.manualEnabled && cfg.agents.isNotEmpty;
    final autoOk = cfg.autoEnabled;
    if (!manualOk && !autoOk) {
      return Center(child: Text(t.manualAddOffTitle, style: AppText.label(22, color: DuelColors.dim, weight: FontWeight.w800)));
    }
    if (_autoMode && autoOk) {
      return SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(36, 28, 36, 32),
          decoration: duelPanel(radius: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (manualOk && autoOk) _addModePicker(t, manualOk, autoOk),
              ZiniPayAutoPanel(
                config: cfg,
                pack: widget.pack,
                packs: widget.packs,
                qty: widget.qty,
                onPickPack: widget.onPickPack,
                onQty: widget.onQty,
              ),
            ],
          ),
        ),
      );
    }
    if (!manualOk) {
      return Center(child: Text(t.paymentNumbersNotSet, style: AppText.label(18, color: DuelColors.dim)));
    }
    final input = AppText.label(28, color: Colors.white);
    final field = InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      labelStyle: AppText.label(20, color: DuelColors.dim),
    );
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 32),
        decoration: duelPanel(radius: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (manualOk && autoOk) _addModePicker(t, manualOk, autoOk),
            Text(t.addCoinTitle, style: AppText.label(36, color: DuelColors.gold, weight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(t.addCoinSteps, style: AppText.label(20, color: DuelColors.dim)),
            const SizedBox(height: 22),
            for (final a in cfg.agents)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.label, style: AppText.label(20, color: DuelColors.silver, weight: FontWeight.w800)),
                          Text(a.number, style: AppText.label(32, color: Colors.white, weight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    GameButton(
                      label: t.copy,
                      height: 64,
                      width: 180,
                      fontSize: 20,
                      onPressed: () => _copy(a.number),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                for (final a in cfg.agents)
                  ChoiceChip(
                    label: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Text(a.label, style: AppText.label(22, weight: FontWeight.w800)),
                    ),
                    selected: _provider == a.id,
                    onSelected: _busy ? null : (_) => setState(() => _provider = a.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.packs.isNotEmpty) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final p in widget.packs)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          label: Text(
                            p.receiveCoins > p.coins ? '${p.coins} → ${p.receiveCoins}' : '${p.coins}',
                            style: AppText.label(18, weight: FontWeight.w800),
                          ),
                          selected: widget.pack?.id == p.id,
                          onSelected: _busy ? null : (_) => widget.onPickPack?.call(p),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (widget.pack != null) _packStepper(),
            TextField(
              controller: _bdt,
              readOnly: widget.pack != null,
              style: input,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: t.amountBdt,
                hintText: '${cfg.minBdt} – ${cfg.maxBdt}',
                contentPadding: field.contentPadding,
                labelStyle: field.labelStyle,
              ),
              onChanged: (_) => setState(() {}),
            ),
            Text(t.youGetCoins(formatPicoCoins(_coins)), style: AppText.label(26, color: DuelColors.gold, weight: FontWeight.w800)),
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
                contentPadding: field.contentPadding,
                labelStyle: field.labelStyle,
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
                contentPadding: field.contentPadding,
                labelStyle: field.labelStyle,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppText.label(22, color: DuelColors.red)),
            ],
            const SizedBox(height: 24),
            GameButton(
              label: _busy ? t.sending : t.submitForApproval,
              height: 88,
              fontSize: 26,
              onPressed: _busy ? null : _submit,
            ),
          ],
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
  const _RedeemTab({required this.config});

  final RedeemConfig config;

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
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 32),
        decoration: duelPanel(radius: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _feed,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(t.historyLoadFail, style: AppText.label(18, color: DuelColors.red)));
        }
        final rows = snap.data;
        if (rows == null) return const Center(child: CircularProgressIndicator(color: DuelColors.silver));
        if (rows.isEmpty) {
          return Center(child: Text(t.historyEmpty, style: AppText.label(20, color: DuelColors.dim)));
        }
        return RefreshIndicator(
          color: DuelColors.gold,
          onRefresh: () async => _reload(),
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF1E2546)),
            itemBuilder: (context, i) => _ActivityRow(item: rows[i]),
          ),
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
        badge: t.badgeTransfer,
        badgeColor: sent ? DuelColors.silver : DuelColors.green,
        title: sent ? '→ $peer' : '← $peer',
        sub: 'ID $peerId · ${sent ? '-${formatCoins(amount + fee)}' : '+${formatCoins(amount)}'}',
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
  const _CoinPackCard({required this.pack, required this.onTap});

  final CoinShopPack pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: Container(
          width: 252,
          height: 248,
          decoration: duelPanel(radius: 18, rim: Color.lerp(DuelColors.gold, Colors.black, 0.35)!),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PikoCoinIcon(size: 88),
              const SizedBox(height: 8),
              Text(formatCoins(pack.coins, compact: true),
                  style: AppText.label(38, color: Colors.white, weight: FontWeight.w900)),
              Text(t.youGetCoins(formatPicoCoins(pack.receiveCoins)),
                  style: AppText.label(18, color: DuelColors.gold, weight: FontWeight.w800)),
              if (pack.name != '${pack.coins}')
                Text(pack.name, style: AppText.label(15, color: DuelColors.dim, weight: FontWeight.w700)),
              if (pack.discountPercent > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    t.bonusPercent(pack.discountPercent),
                    style: AppText.label(16, color: DuelColors.green, weight: FontWeight.w800),
                  ),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: DuelColors.gold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DuelColors.gold),
                ),
                child: Text(t.tabAdd, style: AppText.label(16, color: DuelColors.gold, weight: FontWeight.w900)),
              ),
            ],
          ),
        ),
    );
  }
}
