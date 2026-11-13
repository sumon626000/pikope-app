import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
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

/// Opens NOWPayments hosted invoice (crypto).
Future<void> openNowPaymentsDeposit(
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
      showDuelMessage(
        context,
        title: t.addCoinTitle,
        body: t.bdtRange(config.minBdt, config.maxBdt),
        icon: Icons.payments_outlined,
      );
    }
    return;
  }
  if (!Env.hasBackend || !config.cryptoEnabled) {
    if (context.mounted) {
      showDuelMessage(
        context,
        title: t.addCoinTitle,
        body: t.paymentUnavailable,
        icon: Icons.payment_rounded,
      );
    }
    return;
  }
  try {
    final r = await ref
        .read(sessionProvider.notifier)
        .startNowPaymentsDeposit(bdt, packId: packId, qty: qty);
    final url = r['checkoutUrl'] as String? ?? '';
    final depositId = (r['depositId'] as num?)?.toInt() ?? 0;
    if (url.isEmpty || depositId <= 0) {
      throw ApiException(0, 'nowpayments_error', t.paymentUnavailable);
    }
    if (!context.mounted) return;
    if (kIsWeb) {
      final ok = await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
      if (!ok && context.mounted) {
        showDuelMessage(
          context,
          title: t.addCoinTitle,
          body: t.paymentUnavailable,
          icon: Icons.open_in_browser_rounded,
        );
      }
      return;
    }
    pushScreen(
      context,
      NowPaymentsCheckoutScreen(paymentUrl: url, depositId: depositId),
    );
  } on ApiException catch (e) {
    if (context.mounted) {
      showDuelMessage(
        context,
        title: t.addCoinTitle,
        body: t.maybeApi(e.message),
        icon: Icons.error_outline_rounded,
      );
    }
  }
}

class NowPaymentsCheckoutScreen extends ConsumerStatefulWidget {
  const NowPaymentsCheckoutScreen({
    super.key,
    required this.paymentUrl,
    required this.depositId,
  });

  final String paymentUrl;
  final int depositId;

  @override
  ConsumerState<NowPaymentsCheckoutScreen> createState() =>
      _NowPaymentsCheckoutScreenState();
}

class _NowPaymentsCheckoutScreenState
    extends ConsumerState<NowPaymentsCheckoutScreen> {
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
            final u = req.url.toLowerCase();
            if (u.contains('/deposit/nowpayments/return')) {
              _tryFinish();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  Future<void> _tryFinish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final t = ref.read(stringsProvider);
    try {
      final r = await ref
          .read(sessionProvider.notifier)
          .finishNowPaymentsDeposit(widget.depositId);
      if (!mounted) return;
      final coins = (r['coins'] as num?)?.toInt() ?? 0;
      Navigator.of(context).pop();
      if (context.mounted) {
        showDuelMessage(
          context,
          title: t.addCoinTitle,
          body: coins > 0
              ? t.youGetCoins(formatPicoCoins(coins))
              : t.cryptoPendingConfirm,
          icon: Icons.check_circle_rounded,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      showDuelMessage(
        context,
        title: t.addCoinTitle,
        body: t.maybeApi(e.message),
        icon: Icons.hourglass_top_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return DuelPage(
      title: t.payCryptoUsd,
      child: Column(
        children: [
          if (_finishing)
            const LinearProgressIndicator(color: AppColors.gold)
          else
            const SizedBox(height: 2),
          Expanded(child: WebViewWidget(controller: _web)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: GameButton(
                    label: t.ivePaidCheck,
                    onPressed: _finishing ? null : _tryFinish,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
