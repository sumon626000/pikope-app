import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../l10n/strings.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import 'lobby_data.dart';

/// Opens hosted checkout after server creates a ZiniPay invoice.
Future<void> openZiniPayDeposit(
  BuildContext context,
  WidgetRef ref, {
  required CoinDepositConfig config,
  required int bdt,
  String? packId,
  int qty = 1,
}) async {
  final t = ref.read(stringsProvider);
  if (bdt < config.minBdt || bdt > config.maxBdt) {
    if (context.mounted) {
      showDuelMessage(context,
          title: t.addCoinTitle, body: t.bdtRange(config.minBdt, config.maxBdt), icon: Icons.payments_outlined);
    }
    return;
  }
  if (!Env.hasBackend) {
    if (context.mounted) {
      showDuelMessage(context, title: t.addCoinTitle, body: t.offlineServer, icon: Icons.cloud_off_rounded);
    }
    return;
  }
  if (!config.autoEnabled) {
    if (context.mounted) {
      showDuelMessage(context, title: t.addCoinTitle, body: t.paymentUnavailable, icon: Icons.payment_rounded);
    }
    return;
  }
  try {
    final r = await ref.read(sessionProvider.notifier).startZiniPayDeposit(bdt, packId: packId, qty: qty);
    final url = r['paymentUrl'] as String;
    final deposit = r['deposit'] as Map<String, dynamic>;
    final returnPath = r['returnPath'] as String? ?? '/deposit/zinipay/return';
    if (!context.mounted) return;
    pushScreen(
      context,
      ZiniPayCheckoutScreen(
        paymentUrl: url,
        depositId: deposit['id'] as int,
        returnPath: returnPath,
      ),
    );
  } on ApiException catch (e) {
    if (context.mounted) {
      showDuelMessage(context,
          title: t.addCoinTitle, body: t.maybeApi(e.message), icon: Icons.error_outline_rounded);
    }
  }
}

/// ZiniPay hosted checkout inside the app (auto coin add).
class ZiniPayCheckoutScreen extends ConsumerStatefulWidget {
  const ZiniPayCheckoutScreen({
    super.key,
    required this.paymentUrl,
    required this.depositId,
    required this.returnPath,
  });

  final String paymentUrl;
  final int depositId;
  final String returnPath;

  @override
  ConsumerState<ZiniPayCheckoutScreen> createState() => _ZiniPayCheckoutScreenState();
}

class _ZiniPayCheckoutScreenState extends ConsumerState<ZiniPayCheckoutScreen> {
  late final WebViewController _web;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            if (_handleReturnUrl(req.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onUrlChange: (c) {
            final url = c.url;
            if (url != null) _handleReturnUrl(url);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  bool _handleReturnUrl(String url) {
    if (!url.contains(widget.returnPath)) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final id = int.tryParse(uri.queryParameters['deposit'] ?? '') ?? widget.depositId;
    final cancelled = uri.queryParameters['status'] == 'cancel';
    if (cancelled) {
      if (mounted) Navigator.of(context).pop(false);
      return true;
    }
    _complete(id);
    return true;
  }

  Future<void> _complete(int depositId) async {
    if (_finishing) return;
    _finishing = true;
    final t = ref.read(stringsProvider);
    try {
      await ref.read(sessionProvider.notifier).finishZiniPayDeposit(depositId);
      await ref.read(lobbyProvider.notifier).refresh();
      if (mounted) {
        Navigator.of(context).pop(true);
        showDuelMessage(context,
            title: t.autoAddSuccess,
            body: t.autoAddSuccessBody,
            icon: Icons.check_circle_rounded);
      }
    } on ApiException catch (e) {
      if (mounted) {
        showDuelMessage(context,
            title: t.autoAddPending,
            body: t.maybeApi(e.message),
            icon: Icons.hourglass_top_rounded);
        Navigator.of(context).pop(false);
      }
    } finally {
      _finishing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return DuelPage(
      title: t.autoAddTitle,
      sub: t.autoAddSub,
      sideBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: WebViewWidget(controller: _web),
            ),
          ),
          const SizedBox(height: 12),
          Text(t.autoAddWebHint, style: AppText.label(18, color: DuelColors.dim), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class ZiniPayAutoPanel extends ConsumerStatefulWidget {
  const ZiniPayAutoPanel({
    super.key,
    required this.config,
    this.pack,
    this.qty = 1,
    this.packs = const [],
    this.onPickPack,
    this.onQty,
  });

  final CoinDepositConfig config;
  final CoinShopPack? pack;
  final int qty;
  final List<CoinShopPack> packs;
  final ValueChanged<CoinShopPack>? onPickPack;
  final ValueChanged<int>? onQty;

  @override
  ConsumerState<ZiniPayAutoPanel> createState() => _ZiniPayAutoPanelState();
}

class _ZiniPayAutoPanelState extends ConsumerState<ZiniPayAutoPanel> {
  final _bdt = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _syncPackAmount();
  }

  @override
  void didUpdateWidget(ZiniPayAutoPanel old) {
    super.didUpdateWidget(old);
    if (old.pack?.id != widget.pack?.id || old.qty != widget.qty) _syncPackAmount();
  }

  void _syncPackAmount() {
    final pack = widget.pack;
    if (pack == null) return;
    final total = pack.coins * widget.qty;
    _bdt.text = '$total';
  }

  @override
  void dispose() {
    _bdt.dispose();
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

  Future<void> _pay() async {
    final t = ref.read(stringsProvider);
    final bdt = _amount;
    if (bdt == null) {
      setState(() => _error = t.bdtRange(widget.config.minBdt, widget.config.maxBdt));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await openZiniPayDeposit(
        context,
        ref,
        config: widget.config,
        bdt: bdt,
        packId: widget.pack?.id,
        qty: widget.qty,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final cfg = widget.config;
    final input = AppText.label(28, color: Colors.white);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.addCoinTitle, style: AppText.label(36, color: DuelColors.gold, weight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text(t.addCoinSteps, style: AppText.label(20, color: DuelColors.dim)),
        const SizedBox(height: 20),
        if (widget.packs.isNotEmpty) ...[
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
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _bdt,
          readOnly: widget.pack != null,
          style: input,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: t.amountBdt,
            hintText: '${cfg.minBdt} – ${cfg.maxBdt}',
            contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            labelStyle: AppText.label(20, color: DuelColors.dim),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Text(t.youGetCoins(formatPicoCoins(_coins)), style: AppText.label(26, color: DuelColors.gold, weight: FontWeight.w800)),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: AppText.label(22, color: DuelColors.red)),
        ],
        const SizedBox(height: 24),
        GameButton(
          label: _busy ? t.pleaseWait : t.payNow,
          height: 88,
          fontSize: 24,
          onPressed: _busy ? null : _pay,
        ),
      ],
    );
  }
}
