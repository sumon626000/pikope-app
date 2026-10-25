import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../l10n/strings.dart';
import '../online/session.dart';
import 'coin_tutorial_video.dart';
import 'lobby_data.dart';

/// Send Pico coin to another player by 6-digit game ID (registered only).
class CoinTransferTab extends ConsumerStatefulWidget {
  const CoinTransferTab({super.key, required this.config, this.tutorialUrl = ''});

  final CoinTransferConfig config;
  final String tutorialUrl;

  @override
  ConsumerState<CoinTransferTab> createState() => _CoinTransferTabState();
}

class _CoinTransferTabState extends ConsumerState<CoinTransferTab> {
  final _gameId = TextEditingController();
  final _amount = TextEditingController();
  Timer? _lookupDebounce;
  Map<String, dynamic>? _profile;
  bool _lookupBusy = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _gameId.dispose();
    _amount.dispose();
    super.dispose();
  }

  int? get _amountInt => int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));

  int _feeFor(int amount) => (amount * widget.config.feePercent) ~/ 100;

  void _scheduleLookup() {
    _lookupDebounce?.cancel();
    final digits = _gameId.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 6) {
      setState(() {
        _profile = null;
        _lookupBusy = false;
      });
      return;
    }
    setState(() => _lookupBusy = true);
    _lookupDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final p = await ref.read(sessionProvider.notifier).lookupTransferTarget(digits);
        if (!mounted) return;
        setState(() {
          _profile = p;
          _lookupBusy = false;
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _profile = null;
          _lookupBusy = false;
          _error = ref.read(stringsProvider).maybeApi(e.message);
        });
      }
    });
  }

  Future<void> _send() async {
    final t = ref.read(stringsProvider);
    final session = ref.read(sessionProvider);
    if (session.isGuest) {
      setState(() => _error = t.transferGuestOnly);
      return;
    }
    if (!widget.config.enabled) {
      setState(() => _error = t.transferOff);
      return;
    }
    final digits = _gameId.text.replaceAll(RegExp(r'\D'), '');
    final amount = _amountInt;
    if (digits.length != 6 || amount == null) {
      setState(() => _error = t.transferInvalidId);
      return;
    }
    if (amount < widget.config.minCoins || amount > widget.config.maxCoins) {
      setState(() => _error = t.redeemRange(formatCoins(widget.config.minCoins), formatCoins(widget.config.maxCoins)));
      return;
    }
    final eligible = _profile?['eligible'] as bool? ?? false;
    if (!eligible) {
      setState(() => _error = t.transferNotEligible);
      return;
    }
    final fee = _feeFor(amount);
    final total = amount + fee;
    if (total > session.walletCoins) {
      setState(() => _error = t.notEnoughCoin);
      return;
    }
    final name = _profile?['name'] as String? ?? digits;
    final ok = await showDuelDialog<bool>(
      context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(24),
          decoration: duelPanel(rim: DuelColors.gold),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.transferConfirmTitle, textAlign: TextAlign.center, style: AppText.label(22, color: DuelColors.gold, weight: FontWeight.w900)),
              const SizedBox(height: 14),
              Text(t.transferConfirmBody(name, amount, fee, total), textAlign: TextAlign.center, style: AppText.label(16, color: Colors.white, weight: FontWeight.w700)),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DuelButton(label: t.cancel, width: 150, height: 48, color: DuelColors.rimLight, onPressed: () => Navigator.of(ctx).pop(false)),
                  const SizedBox(width: 12),
                  DuelButton(label: t.transferSendBtn, width: 170, height: 48, color: DuelColors.gold, onPressed: () => Navigator.of(ctx).pop(true)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).sendCoinTransfer(gameId: digits, amount: amount);
      if (!mounted) return;
      _amount.clear();
      setState(() => _profile = null);
      await showDuelDialog<void>(
        context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(26),
            decoration: duelPanel(rim: DuelColors.green, glow: true),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: DuelColors.green, size: 56),
                const SizedBox(height: 12),
                Text(t.transferSent, style: AppText.label(24, color: DuelColors.green, weight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text(t.transferSentBody(name, amount), textAlign: TextAlign.center, style: AppText.label(16, color: DuelColors.silver)),
                const SizedBox(height: 18),
                DuelButton(label: t.ok, width: 160, height: 46, color: DuelColors.gold, onPressed: () => Navigator.of(ctx).pop()),
              ],
            ),
          ),
        ),
      );
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
    if (!cfg.enabled) {
      return Center(child: Text(t.transferOff, style: AppText.label(22, color: DuelColors.dim, weight: FontWeight.w800)));
    }
    if (session.isGuest) {
      return Center(child: Text(t.transferGuestOnly, style: AppText.label(20, color: DuelColors.dim)));
    }
    final amount = _amountInt ?? 0;
    final fee = amount > 0 ? _feeFor(amount) : 0;
    final total = amount + fee;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
              decoration: duelPanel(radius: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            CoinTutorialVideoFrame(
              youtubeUrl: widget.tutorialUrl,
              title: t.coinTutorialTransferTitle,
              tapHint: t.coinTutorialTapPlay,
            ),
            Text(t.tabTransfer, style: AppText.label(40, color: DuelColors.gold, weight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              t.transferFeeHint(cfg.feePercent, formatCoins(fee), formatCoins(total)),
              style: AppText.label(18, color: DuelColors.dim),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _gameId,
              style: AppText.label(28, color: Colors.white),
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: t.transferGameIdLabel,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                labelStyle: AppText.label(20, color: DuelColors.dim),
              ),
              onChanged: (_) {
                setState(() => _error = null);
                _scheduleLookup();
              },
            ),
            if (_lookupBusy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: CircularProgressIndicator(color: DuelColors.silver)),
              )
            else if (_profile != null) ...[
              const SizedBox(height: 14),
              _ProfilePreview(profile: _profile!),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _amount,
              style: AppText.label(28, color: Colors.white),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: t.transferAmountLabel,
                hintText: '${cfg.minCoins} – ${formatCoins(cfg.maxCoins)}',
                contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                labelStyle: AppText.label(20, color: DuelColors.dim),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppText.label(22, color: DuelColors.red)),
            ],
            const SizedBox(height: 24),
                  GameButton(
                    label: _busy ? t.sending : t.transferSendBtn,
                    height: 88,
                    fontSize: 26,
                    color: DuelColors.gold,
                    onPressed: _busy ? null : _send,
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

class _ProfilePreview extends ConsumerWidget {
  const _ProfilePreview({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final eligible = profile['eligible'] as bool? ?? false;
    final name = profile['name'] as String? ?? '—';
    final avatar = profile['avatar'] as String? ?? 'classic';
    final gameId = profile['gameId'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2140),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: eligible ? DuelColors.green.withValues(alpha: 0.5) : DuelColors.red.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          ClipOval(child: AvatarImage(avatar, size: 64)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.label(24, weight: FontWeight.w900)),
                Text('ID $gameId', style: AppText.label(18, color: DuelColors.dim)),
                if (!eligible)
                  Text(t.transferNotEligible, style: AppText.label(16, color: DuelColors.red)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
