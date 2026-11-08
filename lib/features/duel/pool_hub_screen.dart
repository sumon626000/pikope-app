import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/design/design.dart';
import '../../core/duel_ui.dart';
import '../../l10n/strings.dart';
import 'duel_chrome.dart';
import 'bet_level_screen.dart';
import 'duel_home_screen.dart' show GameCard, HomeBanner, PokerArt;
import 'portrait_widgets.dart';
import 'lobby_data.dart';
import '../start/auth_prompt.dart';

/// Everything pool lives here: 8-, 9- and 10-ball tables, Billiard Poker
/// with its jackpot, the random quick duel, free practice and the cue shop.
class PoolHubScreen extends ConsumerWidget {
  const PoolHubScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    ref.read(lobbyProvider.notifier).refresh();
  }

  Future<void> _openStaked(
    BuildContext context,
    WidgetRef ref,
    Widget screen,
  ) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (!context.mounted) return;
    await _open(context, ref, screen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final data = ref.watch(lobbyProvider).valueOrNull;
    final tables = [
      (
        DuelMode.eight,
        8,
        t.eightBallTitle,
        t.eightBallSubShort,
        DesignColors.poolEightAccent,
      ),
      (DuelMode.nine, 9, t.nineBallTitle, t.nineBallSubShort, DuelColors.gold),
      (DuelMode.ten, 10, t.tenBallTitle, t.tenBallSubShort, DuelColors.blue),
    ];
    if (DesignBreakpoints.portraitLayout(context)) {
      return DuelCanvas(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DuelTopBar(showProfile: false, showShortcuts: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Column(
                children: [
                  Text(
                    t.poolHubTitle,
                    textAlign: TextAlign.center,
                    style: AppText.label(20, weight: FontWeight.w900),
                  ),
                  Text(
                    t.poolHubSub,
                    textAlign: TextAlign.center,
                    style: AppText.label(
                      11,
                      color: DuelColors.dim,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                children: [
                  for (final table in tables)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SizedBox(
                        height: 84,
                        child: PortraitGameRow(
                          color: table.$5,
                          title: table.$3,
                          subtitle: table.$4,
                          art: _BallArt(table.$2),
                          playLabel: t.playNow,
                          onPlay: () => _openStaked(
                            context,
                            ref,
                            BetLevelScreen(mode: table.$1),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      height: 84,
                      child: PortraitGameRow(
                        color: DuelColors.purple,
                        title: t.billiardPokerCardTitle,
                        art: const PokerArt(),
                        playLabel: t.playNow,
                        onPlay: () => _openStaked(
                          context,
                          ref,
                          const BetLevelScreen(mode: DuelMode.poker),
                        ),
                      ),
                    ),
                  ),
                  PortraitFeatureTile(
                    icon: Icons.emoji_events_rounded,
                    title: t.jackpotUpTo(
                      data == null
                          ? '10,000'
                          : formatCoins(data.jackpot.reduce(max)),
                    ),
                    subtitle: t.jackpotSubLine,
                    accent: DuelColors.gold,
                    onTap: () => _openStaked(
                      context,
                      ref,
                      const BetLevelScreen(mode: DuelMode.poker),
                    ),
                  ),
                  const SizedBox(height: 6),
                  PortraitFeatureTile(
                    icon: Icons.shuffle_rounded,
                    title: t.quickDuel,
                    subtitle: t.quickDuelSubRandom,
                    accent: const Color(0xFF9CC2FF),
                    onTap: () => _openStaked(
                      context,
                      ref,
                      const BetLevelScreen(mode: DuelMode.billiard),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: NavTile(
                  icon: Icons.reply_rounded,
                  label: t.back,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return DuelCanvas(
      child: LobbyScaffold(
        title: DuelTitle(t.poolHubTitle, size: 50, sub: t.poolHubSub),
        centerPadding: EdgeInsets.zero,
        center: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: DesignSpacing.x6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < tables.length; i++) ...[
                  if (i > 0) const SizedBox(width: DesignLayout.poolHubCardGap),
                  GameCard(
                    width: DesignLayout.poolHubCardWidth,
                    color: tables[i].$5,
                    title: tables[i].$3,
                    sub: tables[i].$4,
                    art: _BallArt(tables[i].$2),
                    onPlay: () => _openStaked(
                      context,
                      ref,
                      BetLevelScreen(mode: tables[i].$1),
                    ),
                  ),
                ],
                const SizedBox(width: DesignLayout.poolHubCardGap),
                GameCard(
                  width: DesignLayout.poolHubCardWidth,
                  color: DuelColors.purple,
                  title: t.billiardPokerCardTitle,
                  sub: null,
                  art: const PokerArt(),
                  onPlay: () => _openStaked(
                    context,
                    ref,
                    const BetLevelScreen(mode: DuelMode.poker),
                  ),
                ),
              ],
            ),
          ),
        ),
        rightRail: Column(
          children: [
            HomeBanner(
              title: t.jackpotUpTo(
                data == null ? '10,000' : formatCoins(data.jackpot.reduce(max)),
              ),
              sub: t.jackpotSubLine,
              colors: const [Color(0xFF3A2606), Color(0xFF15100A)],
              rim: const Color(0xFF8A6A22),
              titleColor: DuelColors.gold,
              icon: const PikoCoinIcon(size: 96),
              onTap: () => _openStaked(
                context,
                ref,
                const BetLevelScreen(mode: DuelMode.poker),
              ),
            ),
            const SizedBox(height: DesignSpacing.x3),
            HomeBanner(
              title: t.quickDuel,
              sub: t.quickDuelSubRandom,
              colors: const [Color(0xFF0B2A66), Color(0xFF070E24)],
              rim: DuelColors.blue,
              titleColor: const Color(0xFF9CC2FF),
              icon: const Icon(
                Icons.shuffle_rounded,
                color: Color(0xFF9CC2FF),
                size: 84,
              ),
              onTap: () => _openStaked(
                context,
                ref,
                const BetLevelScreen(mode: DuelMode.billiard),
              ),
            ),
          ],
        ),
        bottomLeading: LobbyBackNav(
          label: t.back,
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// One big numbered ball on green cloth.
class _BallArt extends StatelessWidget {
  const _BallArt(this.number);

  final int number;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(0, -0.2),
        radius: 1.1,
        colors: [Color(0xFF1F8A4C), Color(0xFF0B3A1F)],
      ),
    ),
    child: Center(child: BallIcon(number, size: 118)),
  );
}
