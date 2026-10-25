import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../l10n/strings.dart';
import '../online/session.dart';
import 'challenge_screen.dart';

/// Compact top banner (not a full-screen dialog) for an incoming 1v1 invite.
Future<void> showIncomingChallengeBanner(BuildContext context, WidgetRef ref, Map<String, dynamic> ch) async {
  await showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'challenge',
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 320),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1.08), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
    pageBuilder: (context, _, __) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 56),
          child: Align(
            alignment: Alignment.topCenter,
            child: _IncomingTopBanner(ch: ch),
          ),
        ),
      );
    },
  );
}

class _IncomingTopBanner extends ConsumerStatefulWidget {
  const _IncomingTopBanner({required this.ch});

  final Map<String, dynamic> ch;

  @override
  ConsumerState<_IncomingTopBanner> createState() => _IncomingTopBannerState();
}

class _IncomingTopBannerState extends ConsumerState<_IncomingTopBanner> {
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get _from => widget.ch['from'] as Map<String, dynamic>;

  String get _gameKey => widget.ch['game'] as String;

  int get _buyIn {
    final raw = widget.ch['buyIn'];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return (widget.ch['stake'] as int?) ?? 0;
  }

  int get _prize => (widget.ch['prize'] as int?) ?? 0;

  int? get _level {
    final raw = widget.ch['level'];
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw.toString());
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final room = await ref.read(sessionProvider.notifier).acceptChallenge(widget.ch['id'] as int);
      if (!mounted) return;
      Navigator.of(context).pop();
      await openChallengeRoom(context, ref, room);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    try {
      await ref.read(sessionProvider.notifier).declineChallenge(widget.ch['id'] as int);
    } on ApiException {
      // ignore
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final title = challengeGameTitle(_gameKey);
    final name = (_from['name'] as String).toUpperCase();
    final level = _level;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 560, minHeight: 132),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12182E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DuelColors.gold, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFF5C8BFF), Color(0xFFFF3B4E)]),
                  ),
                  child: ClipOval(child: AvatarImage(_from['avatar'] as String, size: 48)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.challengeTitle, style: AppText.label(13, color: DuelColors.gold, weight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(17, weight: FontWeight.w900)),
                      Text(t.challengesYou(title), style: AppText.label(12, color: DuelColors.silver)),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : _decline,
                  icon: const Icon(Icons.close_rounded, color: DuelColors.silver, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _detailChip(Icons.sports_esports_rounded, title),
                if (level != null) _detailChip(Icons.table_bar_rounded, t.challengeTableLevel(level)),
                if (_buyIn > 0) ...[
                  const PikoCoinIcon(size: 20),
                  Text(t.buyInWin(_buyIn, formatCoins(_prize)), style: AppText.label(13, color: DuelColors.gold, weight: FontWeight.w800)),
                ] else
                  Text(t.friendlyNoStake, style: AppText.label(12, color: DuelColors.dim)),
                if ((widget.ch['expiresIn'] as int?) != null && (widget.ch['expiresIn'] as int) > 0)
                  _detailChip(Icons.timer_outlined, t.challengeExpiresSec(widget.ch['expiresIn'] as int)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!.toUpperCase(), style: AppText.label(11, color: DuelColors.red)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DuelButton(
                    label: _busy ? '...' : t.decline,
                    height: 44,
                    fontSize: 14,
                    color: DuelColors.rimLight,
                    onPressed: _busy ? null : _decline,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DuelButton(
                    label: _busy ? '...' : t.accept,
                    height: 44,
                    fontSize: 14,
                    color: DuelColors.gold,
                    onPressed: _busy ? null : _accept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFF1E2640), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: DuelColors.silver),
          const SizedBox(width: 4),
          Text(label, style: AppText.label(11, color: DuelColors.silver, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

String challengeGameTitle(String game) {
  if (game.startsWith('ludo')) return 'LUDO';
  if (game == 'carrom') return 'CARROM';
  if (game == 'poker') return 'BILLIARD POKER';
  if (game == 'eight') return '8-BALL';
  if (game == 'nine') return '9-BALL';
  if (game == 'ten') return '10-BALL';
  return 'BILLIARD';
}
