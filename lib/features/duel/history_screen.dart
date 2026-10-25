import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import 'shop_screen.dart';
import '../../l10n/strings.dart';

/// Win/loss stats plus full coin activity (matches, shop, redeem).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late Future<List<Map<String, dynamic>>> _feed;

  @override
  void initState() {
    super.initState();
    _feed = ref.read(sessionProvider.notifier).activity(limit: 80);
  }

  void _reload() => setState(() => _feed = ref.read(sessionProvider.notifier).activity(limit: 80));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final session = ref.watch(sessionProvider);
    final rate = s.games == 0 ? 0 : (100 * s.wins / s.games).round();
    return DuelPage(
      title: t.matchDataTitle,
      sub: t.matchDataSub,
      child: Column(
        children: [
          Row(
            children: [
              _Stat(t.statLevel, '${session.level}'),
              _Stat(t.statRank, session.rankName),
              _Stat(t.statMatches, formatCoins(s.games)),
              _Stat(t.statWins, formatCoins(s.wins)),
              _Stat(t.statWinRate, '$rate%'),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => pushScreen(context, const ShopScreen(initialTab: 2)),
              child: Text(t.openCoinWallet, style: AppText.label(14, color: DuelColors.gold, weight: FontWeight.w800)),
            ),
          ),
          Expanded(
            child: Container(
              decoration: duelPanel(radius: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FutureBuilder<List<Map<String, dynamic>>>(
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
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _ActivityLine(item: rows[i]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityLine extends ConsumerWidget {
  const _ActivityLine({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final at = DateTime.fromMillisecondsSinceEpoch(item['at'] as int);
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
    final kind = item['kind'] as String;
    String title;
    String sub;
    Color badgeColor;
    String badge;
    int coins = 0;

    switch (kind) {
      case 'match':
        final won = item['won'] as bool;
        badge = won ? t.badgeWin : t.badgeLoss;
        badgeColor = won ? DuelColors.green : DuelColors.red;
        title = t.gameTitleKey(item['game'] as String);
        sub = item['mode'] == 'bots' ? t.badgePractice : t.onlineMatch;
        coins = item['coins'] as int;
      case 'wallet':
        badge = t.badgeCoin;
        badgeColor = DuelColors.gold;
        title = item['label'] as String? ?? (t.isBn ? 'ওয়ালেট' : 'Wallet');
        sub = item['reason'] as String? ?? '';
        coins = item['amount'] as int;
      case 'redeem':
        final status = item['status'] as String;
        badge = t.statusLabel(status);
        badgeColor = status == 'approved'
            ? DuelColors.green
            : status == 'rejected'
                ? DuelColors.red
                : DuelColors.gold;
        title = '${t.badgeRedeem} ${item['walletProviderLabel']}';
        sub = '${item['bdt']} BDT · ${item['walletNumber']}';
        coins = -(item['coins'] as int);
      case 'deposit':
        final dStatus = item['status'] as String;
        badge = t.statusLabel(dStatus);
        badgeColor = dStatus == 'approved'
            ? DuelColors.green
            : dStatus == 'rejected'
                ? DuelColors.red
                : DuelColors.gold;
        title = '${t.badgeAdd} ${item['providerLabel']}';
        sub = '${item['bdt']} BDT · Trx ${item['trxId']}';
        coins = dStatus == 'approved' ? (item['coins'] as int) : 0;
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badgeColor),
              color: badgeColor.withValues(alpha: 0.12),
            ),
            child: Text(badge, style: AppText.label(12, color: badgeColor, weight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: AppText.label(15, weight: FontWeight.w800)),
                Text(sub, style: AppText.label(12, color: DuelColors.dim)),
              ],
            ),
          ),
          if (coins != 0)
            Text('${coins > 0 ? '+' : ''}${formatCoins(coins)}',
                style: AppText.label(16, color: coins > 0 ? DuelColors.gold : DuelColors.red, weight: FontWeight.w900)),
          const SizedBox(width: 10),
          Text(time, style: AppText.label(12, color: DuelColors.dim)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 96,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: duelPanel(radius: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: AppText.label(13, color: DuelColors.dim)),
              const SizedBox(height: 6),
              Text(value, style: AppText.label(26, color: Colors.white, weight: FontWeight.w900)),
            ],
          ),
        ),
      );
}
