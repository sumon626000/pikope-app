import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/duel_ui.dart';
import '../../l10n/strings.dart';
import 'bet_level_screen.dart';
import 'cues_screen.dart';
import 'duel_chrome.dart';
import 'duel_home_screen.dart' show GameCard, HomeBanner, PokerArt;
import 'lobby_data.dart';

/// Everything pool lives here: 8-, 9- and 10-ball tables, Billiard Poker
/// with its jackpot, the random quick duel, free practice and the cue shop.
class PoolHubScreen extends ConsumerWidget {
  const PoolHubScreen({super.key});

  static const _cardW = 240.0, _cardGap = 16.0, _left = 120.0;

  Future<void> _open(BuildContext context, WidgetRef ref, Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    ref.read(lobbyProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final data = ref.watch(lobbyProvider).valueOrNull;
    final tables = [
      (DuelMode.eight, 8, t.eightBallTitle, t.eightBallSubShort, const Color(0xFF2E8B57)),
      (DuelMode.nine, 9, t.nineBallTitle, t.nineBallSubShort, DuelColors.gold),
      (DuelMode.ten, 10, t.tenBallTitle, t.tenBallSubShort, const Color(0xFF2F6BFF)),
    ];
    return DuelCanvas(
      child: Stack(
        children: [
          const Positioned(left: 0, right: 0, top: 6, child: DuelTopBar()),
          Positioned(
            left: _left,
            width: 4 * _cardW + 3 * _cardGap,
            top: 124,
            child: DuelTitle(t.poolHubTitle, size: 50, sub: t.poolHubSub),
          ),
          for (var i = 0; i < tables.length; i++)
            Positioned(
              left: _left + i * (_cardW + _cardGap),
              top: 234,
              child: GameCard(
                width: _cardW,
                color: tables[i].$5,
                title: tables[i].$3,
                sub: tables[i].$4,
                art: _BallArt(tables[i].$2),
                onPlay: () => _open(context, ref, BetLevelScreen(mode: tables[i].$1)),
              ),
            ),
          Positioned(
            left: _left + 3 * (_cardW + _cardGap),
            top: 234,
            child: GameCard(
              width: _cardW,
              color: DuelColors.purple,
              title: t.billiardPokerCardTitle,
              sub: null,
              art: const PokerArt(),
              onPlay: () => _open(context, ref, const BetLevelScreen(mode: DuelMode.poker)),
            ),
          ),
          Positioned(
            left: 1178,
            top: 132,
            child: HomeBanner(
              title: t.jackpotUpTo(data == null ? '10,000' : formatCoins(data.jackpot.reduce(max))),
              sub: t.jackpotSubLine,
              colors: const [Color(0xFF3A2606), Color(0xFF15100A)],
              rim: const Color(0xFF8A6A22),
              titleColor: DuelColors.gold,
              icon: const PikoCoinIcon(size: 96),
              onTap: () => _open(context, ref, const BetLevelScreen(mode: DuelMode.poker)),
            ),
          ),
          Positioned(
            left: 1178,
            top: 318,
            child: HomeBanner(
              title: t.quickDuel,
              sub: t.quickDuelSubRandom,
              colors: const [Color(0xFF0B2A66), Color(0xFF070E24)],
              rim: const Color(0xFF2F6BFF),
              titleColor: const Color(0xFF9CC2FF),
              icon: const Icon(Icons.shuffle_rounded, color: Color(0xFF9CC2FF), size: 84),
              onTap: () => _open(context, ref, const BetLevelScreen(mode: DuelMode.billiard)),
            ),
          ),
          Positioned(
            left: 1178,
            top: 518,
            child: HomeBanner(
              title: t.practiceFreeTitle,
              sub: t.practiceBannerSubPass,
              colors: const [Color(0xFF0E3A22), Color(0xFF07140D)],
              rim: const Color(0xFF2E8B57),
              titleColor: const Color(0xFF9BF2B5),
              icon: const Icon(Icons.smart_toy_rounded, color: Color(0xFF9BF2B5), size: 84),
              onTap: () => showPoolPracticeDialog(context, open: (screen) => _open(context, ref, screen)),
            ),
          ),
          Positioned(
            left: 42,
            bottom: 34,
            child: Row(
              children: [
                NavTile(icon: Icons.reply_rounded, label: t.back, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 19),
                NavTile(icon: NavTile.cuesIcon, label: t.navCues, onTap: () => _open(context, ref, const CuesScreen())),
                const SizedBox(width: 19),
                NavTile(icon: Icons.backpack_rounded, label: t.myCues, onTap: () => _open(context, ref, const CuesScreen(ownedOnly: true))),
              ],
            ),
          ),
        ],
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
          gradient: RadialGradient(center: Alignment(0, -0.2), radius: 1.1, colors: [Color(0xFF1F8A4C), Color(0xFF0B3A1F)]),
        ),
        child: Center(child: BallIcon(number, size: 118)),
      );
}
