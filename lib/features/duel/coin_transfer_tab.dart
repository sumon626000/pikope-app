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
import 'lobby_data.dart';

/// Send Pico coin to another player by 6-digit game ID (registered only).
class CoinTransferTab extends ConsumerStatefulWidget {
  const CoinTransferTab({super.key, required this.config});

  final CoinTransferConfig config;

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
  DateTime? _confirmUntil;
  int _confirmAmount = 0;
  String _confirmGameId = '';

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
    final total = amount + _feeFor(amount);
    if (total > session.walletCoins) {
      setState(() => _error = t.notEnoughCoin);
      return;
    }
    final now = DateTime.now();
    if (_confirmUntil == null ||
        _confirmAmount != amount ||
        _confirmGameId != digits ||
        now.isAfter(_confirmUntil!)) {
      setState(() {
        _confirmUntil = now.add(const Duration(seconds: 4));
        _confirmAmount = amount;
        _confirmGameId = digits;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _confirmUntil = null;
    });
    try {
      await ref.read(sessionProvider.notifier).sendCoinTransfer(gameId: digits, amount: amount);
      await ref.read(lobbyProvider.notifier).refresh();
      if (mounted) {
        final name = _profile?['name'] as String? ?? digits;
        showDuelMessage(context,
            title: t.transferSent, body: t.transferSentBody(name, amount), icon: Icons.check_circle_rounded);
        _amount.clear();
        setState(() => _profile = null);
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
    if (!cfg.enabled) {
      return Center(child: Text(t.transferOff, style: AppText.label(22, color: DuelColors.dim, weight: FontWeight.w800)));
    }
    if (session.isGuest) {
      return Center(child: Text(t.transferGuestOnly, style: AppText.label(20, color: DuelColors.dim)));
    }
    final amount = _amountInt ?? 0;
    final fee = amount > 0 ? _feeFor(amount) : 0;
    final total = amount + fee;
    final confirmReady = _confirmUntil != null &&
        !_busy &&
        _confirmAmount == amount &&
        _confirmGameId == _gameId.text.replaceAll(RegExp(r'\D'), '') &&
        DateTime.now().isBefore(_confirmUntil!);
    final btnLabel = confirmReady ? t.transferConfirmTap : t.transferSendBtn;

    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 32),
        decoration: duelPanel(radius: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                setState(() {
                  _error = null;
                  _confirmUntil = null;
                });
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
              onChanged: (_) => setState(() {
                _error = null;
                _confirmUntil = null;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppText.label(22, color: DuelColors.red)),
            ],
            const SizedBox(height: 24),
            GameButton(
              label: _busy ? t.sending : btnLabel,
              height: 88,
              fontSize: confirmReady ? 22 : 26,
              color: confirmReady ? DuelColors.green : DuelColors.gold,
              onPressed: _busy ? null : _send,
            ),
          ],
        ),
      ),
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
