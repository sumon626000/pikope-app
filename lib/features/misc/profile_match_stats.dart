import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../l10n/strings.dart';

/// Lifetime + today match stats for profile / settings.
class ProfileMatchStatsPanel extends ConsumerWidget {
  const ProfileMatchStatsPanel({
    super.key,
    required this.totalGames,
    required this.totalWins,
    required this.totalLosses,
    required this.winRate,
    required this.todayPlayed,
    required this.todayWins,
    required this.todayLosses,
    this.loading = false,
  });

  final int totalGames;
  final int totalWins;
  final int totalLosses;
  final int winRate;
  final int todayPlayed;
  final int todayWins;
  final int todayLosses;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    if (loading) {
      return Container(
        height: 132,
        alignment: Alignment.center,
        decoration: duelPanel(radius: 16, rim: DuelColors.rimLight),
        child: const CircularProgressIndicator(color: DuelColors.gold, strokeWidth: 2.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.query_stats_rounded, color: DuelColors.gold.withValues(alpha: 0.9), size: 20),
            const SizedBox(width: 8),
            Text(t.sectionMatchStats, style: AppText.label(14, weight: FontWeight.w900, color: DuelColors.silver)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatTile(label: t.statMatches, value: formatCoins(totalGames), accent: DuelColors.silver),
            _StatTile(label: t.statWins, value: formatCoins(totalWins), accent: DuelColors.green),
            _StatTile(label: t.statLosses, value: formatCoins(totalLosses), accent: DuelColors.red),
            _StatTile(label: t.statWinRate, value: '$winRate%', accent: DuelColors.gold, glow: true),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF121830),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DuelColors.rimLight.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _TodayChip(label: t.statTodayPlayed, value: '$todayPlayed', icon: Icons.today_rounded),
              ),
              Container(width: 1, height: 36, color: DuelColors.rimLight.withValues(alpha: 0.25)),
              Expanded(
                child: _TodayChip(label: t.statTodayWins, value: '$todayWins', icon: Icons.emoji_events_outlined, color: DuelColors.green),
              ),
              Container(width: 1, height: 36, color: DuelColors.rimLight.withValues(alpha: 0.25)),
              Expanded(
                child: _TodayChip(label: t.statTodayLosses, value: '$todayLosses', icon: Icons.close_rounded, color: DuelColors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.accent,
    this.glow = false,
  });

  final String label;
  final String value;
  final Color accent;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 72,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: duelPanel(
          radius: 12,
          rim: accent.withValues(alpha: glow ? 0.85 : 0.45),
          glow: glow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(10, color: DuelColors.dim, weight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppText.label(20, color: Colors.white, weight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayChip extends StatelessWidget {
  const _TodayChip({
    required this.label,
    required this.value,
    required this.icon,
    this.color = DuelColors.silver,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value, style: AppText.label(18, weight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.label(9, color: DuelColors.dim, weight: FontWeight.w700),
        ),
      ],
    );
  }
}
