import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/root_nav.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../l10n/strings.dart';
import '../start/auth_prompt.dart';
import '../online/session.dart';
import 'coin_tutorial_video.dart';
import 'lobby_data.dart';
import '../../core/push_service.dart';
import '../online/notification_unread.dart';
import 'shop_phone_layout.dart';
import 'shop_tab_insets.dart';

/// Send Pico coin to another player by 6-digit game ID (registered only).
class CoinTransferTab extends ConsumerStatefulWidget {
  const CoinTransferTab({super.key, required this.config, this.tutorialUrl = ''});

  final CoinTransferConfig config;
  final String tutorialUrl;

  @override
  ConsumerState<CoinTransferTab> createState() => _CoinTransferTabState();
}

class _CoinTransferTabState extends ConsumerState<CoinTransferTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _gameId = TextEditingController();
  final _amount = TextEditingController();
  Timer? _lookupDebounce;
  Map<String, dynamic>? _profile;
  bool _lookupBusy = false;
  bool _busy = false;
  String? _error;
  String? _success;
  Timer? _walletPoll;

  @override
  void initState() {
    super.initState();
    _walletPoll = Timer.periodic(const Duration(seconds: 12), (_) => _pollWalletInbox());
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollWalletInbox());
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _walletPoll?.cancel();
    _gameId.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pollWalletInbox() async {
    if (!mounted || _busy) return;
    final api = ref.read(apiProvider);
    if (api == null || !ref.read(sessionProvider).signedIn) return;
    try {
      final poll = await PushService.pollInbox(api);
      if (!mounted) return;
      ref.read(notificationUnreadProvider.notifier).set(poll.unread);
      if (poll.walletChanged) {
        await ref.read(sessionProvider.notifier).refresh();
        if (mounted) ref.read(lobbyProvider.notifier).refresh();
      }
    } on Object {
      // offline
    }
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
        if (!mounted || _busy) return;
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
      if (!await requireRegisteredAccount(context, ref)) return;
      if (!mounted) return;
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
      builder: (ctx) => PcDialog(
        title: t.transferConfirmTitle,
        actions: [
          PcButton(label: t.cancel, style: PcButtonStyle.gray, width: 300, onPressed: () => Navigator.of(ctx).pop(false)),
          PcButton(label: t.transferSendBtn, style: PcButtonStyle.gold, width: 400, onPressed: () => Navigator.of(ctx).pop(true)),
        ],
        child: Text(t.transferConfirmBody(name, amount, fee, total), textAlign: TextAlign.center, style: pcText(36, weight: FontWeight.w500).copyWith(height: 1.35)),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final transfer = await ref.read(sessionProvider.notifier).sendCoinTransfer(gameId: digits, amount: amount);
      final recipient = transfer['toName'] as String? ?? name;
      if (mounted) {
        _amount.clear();
        setState(() {
          _profile = null;
          _error = null;
          _success = t.transferSentBody(recipient, amount);
        });
      }
      try {
        await ref.read(lobbyProvider.notifier).refresh();
      } catch (_) {}
      final dialogCtx = rootNavigatorKey.currentContext ?? (mounted ? context : null);
      if (dialogCtx != null && dialogCtx.mounted) {
        try {
          await showDuelMessage(
            dialogCtx,
            title: t.transferSent,
            body: t.transferSentBody(recipient, amount),
            icon: Icons.check_circle_rounded,
          );
        } catch (_) {}
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = t.maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = ref.watch(stringsProvider);
    final cfg = widget.config;
    if (!cfg.enabled) {
      return Center(child: Text(t.transferOff, style: AppText.label(22, color: DuelColors.dim, weight: FontWeight.w800)));
    }
    final amount = _amountInt ?? 0;
    final fee = amount > 0 ? _feeFor(amount) : 0;
    final total = amount + fee;
    final phone = ShopPhoneLayout.phone(context);
    final input = AppText.label(phone ? 16 : 28, color: Colors.white);
    return LayoutBuilder(
      builder: (context, constraints) {
        final form = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            CoinTutorialVideoFrame(
              youtubeUrl: widget.tutorialUrl,
              title: t.coinTutorialTransferTitle,
              tapHint: t.coinTutorialTapPlay,
              compact: phone,
            ),
            if (!phone) ...[
              Text(
                t.tabTransfer,
                style: AppText.label(40, color: DuelColors.gold, weight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              t.transferFeeHint(cfg.feePercent, formatCoins(fee), formatCoins(total)),
              maxLines: phone ? 2 : null,
              overflow: phone ? TextOverflow.ellipsis : null,
              style: AppText.label(phone ? 10 : 18, color: DuelColors.dim),
            ),
            SizedBox(height: phone ? 8 : 20),
            TextField(
              controller: _gameId,
              style: input,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: pcFieldDecoration(
                label: t.transferGameIdLabel,
                phone: phone,
                accent: DuelColors.silver,
              ),
              onChanged: (_) {
                setState(() {
                  _error = null;
                  _success = null;
                });
                _scheduleLookup();
              },
            ),
            if (_lookupBusy)
              Padding(
                padding: EdgeInsets.only(top: phone ? 6 : 12),
                child: Center(
                  child: SizedBox(
                    width: phone ? 22 : 36,
                    height: phone ? 22 : 36,
                    child: const CircularProgressIndicator(
                      color: DuelColors.silver,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              )
            else if (_profile != null) ...[
              SizedBox(height: phone ? 6 : 14),
              _ProfilePreview(profile: _profile!, compact: phone),
            ],
            SizedBox(height: phone ? 8 : 18),
            TextField(
              controller: _amount,
              style: input,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: pcFieldDecoration(
                label: t.transferAmountLabel,
                hint: '${cfg.minCoins} – ${formatCoins(cfg.maxCoins)}',
                phone: phone,
                accent: DuelColors.gold,
              ),
              onChanged: (_) => setState(() {
                _error = null;
                _success = null;
              }),
            ),
            if (_success != null) ...[
              SizedBox(height: phone ? 4 : 10),
              Text(
                _success!,
                style: AppText.label(
                  phone ? 11 : 22,
                  color: DuelColors.green,
                  weight: FontWeight.w800,
                ),
              ),
            ] else if (_error != null) ...[
              SizedBox(height: phone ? 4 : 10),
              Text(
                _error!,
                style: AppText.label(phone ? 11 : 22, color: DuelColors.red),
              ),
            ],
            SizedBox(height: phone ? 10 : 24),
            GameButton(
              label: _busy ? t.sending : t.transferSendBtn,
              height: phone ? 40 : 88,
              fontSize: phone ? 14 : 26,
              color: DuelColors.gold,
              onPressed: _busy ? null : _send,
            ),
          ],
        );
        if (phone) {
          return Padding(
            padding: ShopTabInsets.scrollPhoneFit,
            child: SizedBox(
              height: constraints.maxHeight,
              width: double.infinity,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: form,
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: ShopTabInsets.forViewport(context),
          child: SizedBox(
            width: double.infinity,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: form,
            ),
          ),
        );
      },
    );
  }
}

class _ProfilePreview extends ConsumerWidget {
  const _ProfilePreview({required this.profile, this.compact = false});

  final Map<String, dynamic> profile;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final eligible = profile['eligible'] as bool? ?? false;
    final name = profile['name'] as String? ?? '—';
    final avatar = profile['avatar'] as String? ?? 'classic';
    final gameId = profile['gameId'] as String? ?? '';
    final avatarSize = compact ? 36.0 : 64.0;
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2140),
        borderRadius: BorderRadius.circular(compact ? 10 : 16),
        border: Border.all(color: eligible ? DuelColors.green.withValues(alpha: 0.5) : DuelColors.red.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          ClipOval(child: AvatarImage(avatar, size: avatarSize)),
          SizedBox(width: compact ? 8 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(compact ? 13 : 24, weight: FontWeight.w900),
                ),
                Text(
                  'ID $gameId',
                  style: AppText.label(compact ? 10 : 18, color: DuelColors.dim),
                ),
                if (!eligible)
                  Text(
                    t.transferNotEligible,
                    style: AppText.label(compact ? 9 : 16, color: DuelColors.red),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
