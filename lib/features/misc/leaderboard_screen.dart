import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../../core/widgets.dart';
import '../../data/demo_data.dart';
import '../duel/home_portrait_widgets.dart' show RankEmblemPainter;
import '../online/session.dart';
import '../../l10n/strings.dart';

typedef _Row = ({String name, String avatar, int wins, int extra, bool showLevel, bool me});

/// Ranking by wins, in the reference's layout: tab strip, the player's rank
/// tier, column headers, medal rows, the player's own row pinned at the
/// bottom. With a backend it is the live table; without one it is bundled
/// demo data plus the local player.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  List<_Row>? _live;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    if (Env.hasBackend) _load();
  }

  Future<void> _load() async {
    try {
      if (!await ref.read(sessionProvider.notifier).tryRestoreExistingSession()) {
        if (mounted) setState(() => _live = const []);
        return;
      }
      final myId = ref.read(sessionProvider).userId;
      final r = await ref.read(apiProvider)!.get('/leaderboard');
      final rows = [
        for (final e in (r['entries'] as List).cast<Map<String, dynamic>>())
          (
            name: e['name'] as String,
            avatar: e['avatar'] as String,
            wins: e['wins'] as int,
            extra: e['level'] as int? ?? 1,
            showLevel: true,
            me: e['id'] == myId,
          ),
      ];
      if (mounted) setState(() => _live = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final me = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final List<_Row> rows;
    String? note;
    if (Env.hasBackend) {
      rows = _live ?? const [];
      note = _error ?? (_live == null ? t.loading : (rows.isEmpty ? t.leaderboardEmpty : null));
    } else {
      rows = [
        for (final e in DemoData.leaderboard)
          (name: e.name, avatar: e.avatar, wins: e.wins, extra: e.coins, showLevel: false, me: false),
        (name: me.name, avatar: me.avatar, wins: me.wins, extra: me.coins, showLevel: false, me: true),
      ]..sort((a, b) => b.wins != a.wins ? b.wins - a.wins : b.extra - a.extra);
      note = t.leaderboardDemo;
    }
    final myIndex = rows.indexWhere((r) => r.me);
    final mine = myIndex >= 0 ? rows[myIndex] : (name: me.name, avatar: me.avatar, wins: me.wins, extra: me.coins, showLevel: false, me: true);

    return PcPage(
      tabs: PcTabs(labels: [t.leaderboard], index: _tab, onChanged: (i) => setState(() => _tab = i)),
      panel: false,
      scroll: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          // Tier header: gem, rank name, info.
          Container(
            height: 150,
            padding: const EdgeInsets.symmetric(horizontal: 30),
            decoration: BoxDecoration(color: const Color(0xFF1E1545).withValues(alpha: 0.6)),
            child: Row(
              children: [
                SizedBox(width: 120, height: 130, child: CustomPaint(painter: RankEmblemPainter(session.signedIn ? session.rankTier : -1))),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titleCase(session.signedIn ? session.rankName : t.browseProfileTitle), style: pcText(44)),
                      const SizedBox(height: 6),
                      Text(
                        note ?? '${titleCase(t.leaderboard)}  •  ${rows.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: pcText(26, color: note == null ? DesignColors.pcTextDim : DesignColors.pcGold, weight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                PcButton(label: '', icon: Icons.info_outline_rounded, width: 90, height: 84, fontSize: 44, onPressed: () => showPcMessage(context, title: t.leaderboard, body: note ?? t.leaderboardDemo)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PcSubTabs(labels: [t.rank, t.navData], index: 0, onChanged: (_) {}),
          const SizedBox(height: 16),
          // Column headers.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 70),
            child: Row(
              children: [
                SizedBox(width: 140, child: Text(titleCase(t.rank), style: pcText(28, color: const Color(0xFF9F96D8), weight: FontWeight.w500))),
                Expanded(child: Text(titleCase(t.playerCol), textAlign: TextAlign.center, style: pcText(28, color: const Color(0xFF9F96D8), weight: FontWeight.w500))),
                SizedBox(width: 220, child: Text(titleCase(t.winsLabel), textAlign: TextAlign.right, style: pcText(28, color: const Color(0xFF9F96D8), weight: FontWeight.w500))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              decoration: pcPanelDecoration(),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                itemBuilder: (context, i) => _RankRow(rank: i + 1, row: rows[i], t: t),
              ),
            ),
          ),
          // The player's own row, pinned.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: _RankRow(rank: myIndex >= 0 ? myIndex + 1 : rows.length + 1, row: mine, t: t, pinned: true),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.row, required this.t, this.pinned = false});

  final int rank;
  final _Row row;
  final AppStrings t;
  final bool pinned;

  @override
  Widget build(BuildContext context) => PcListRow(
        rank: rank,
        me: row.me,
        height: pinned ? 136 : 128,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(
          children: [
            PcRankBadge(rank, size: 84),
            const SizedBox(width: 30),
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF7FE0FF), width: 3)),
              child: ClipRRect(borderRadius: BorderRadius.circular(4), child: AvatarImage(row.avatar, size: 96)),
            ),
            const SizedBox(width: 20),
            if (row.showLevel) ...[
              SizedBox(
                width: 70,
                height: 70,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFF8A4A1E), size: 72),
                    const Icon(Icons.star_rounded, color: DesignColors.pcGold, size: 62),
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('${row.extra}', style: pcText(row.extra >= 100 ? 20 : 26, color: const Color(0xFF5A2E00), shadow: false))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pcText(36))),
            Text(formatCoins(row.wins), style: pcText(38)),
            const SizedBox(width: 10),
            const Icon(Icons.emoji_events_rounded, color: DesignColors.pcGold, size: 56, shadows: [Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 3))]),
          ],
        ),
      );
}
