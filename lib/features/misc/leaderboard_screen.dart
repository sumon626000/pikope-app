import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/env.dart';
import '../../core/widgets.dart';
import '../../data/demo_data.dart';
import '../online/session.dart';
import 'page_frame.dart';
import '../../l10n/strings.dart';

typedef _Row = ({String name, String avatar, int wins, int extra, bool showLevel, bool me});

/// Ranking by wins. With a backend it is the live table; without one it is
/// bundled demo data plus the local player.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  List<_Row>? _live;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Env.hasBackend) _load();
  }

  Future<void> _load() async {
    try {
      await ref.read(sessionProvider.notifier).ensureSignedIn();
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
    return PageFrame(
      title: t.leaderboard,
      maxWidth: 760,
      child: Column(
        children: [
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(note, textAlign: TextAlign.center, style: AppText.label(11, color: AppColors.textDim)),
            ),
          for (var i = 0; i < rows.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: panelDecoration(
                radius: 14,
                border: rows[i].me ? AppColors.active : AppColors.frame,
                glow: rows[i].me ? AppColors.active : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text('${i + 1}',
                        style: AppText.label(18, color: i < 3 ? AppColors.gold : AppColors.textDim)),
                  ),
                  FramedTile(size: 44, child: AvatarImage(rows[i].avatar, size: 44)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(rows[i].name.toUpperCase(),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(15)),
                  ),
                  Text('${rows[i].wins} WINS', style: AppText.label(13, color: AppColors.active)),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 90,
                    child: Text(
                      rows[i].showLevel ? 'LV ${rows[i].extra}' : '${rows[i].extra}',
                      textAlign: TextAlign.right,
                      style: AppText.label(13, color: AppColors.gold),
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
