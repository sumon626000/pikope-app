import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';
import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/env.dart';
import '../../core/widgets.dart';
import '../../data/app_game.dart';
import '../../data/demo_data.dart';
import '../../game/models/playing_card.dart';
import '../game/widgets/card_view.dart';
import '../game/widgets/table_art.dart';
import '../lobby/lobby_screen.dart';
import '../misc/how_to_play_screen.dart';
import '../misc/leaderboard_screen.dart';
import '../misc/settings_screen.dart';
import '../online/online_screens.dart';
import '../online/session.dart';
import '../../l10n/strings.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// Online screens can leave a match running behind them: look again on return.
  Future<void> _openOnline(BuildContext context, WidgetRef ref, Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    ref.invalidate(activeMatchProvider);
  }

  void _onlineInfo(BuildContext context, AppStrings t) {
    showDuelDialog<void>(
      context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(22),
          decoration: panelDecoration(radius: 22, opacity: 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.public_rounded, color: AppColors.gold, size: 36),
              const SizedBox(height: 8),
              Text(t.onlineMatch, style: AppText.label(18, weight: FontWeight.w900)),
              const SizedBox(height: 10),
              const Text(
                'This build was made without a game server address (API_BASE_URL), so online '
                'rooms are off. Play against bots or pass the device between friends.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'sans-serif', fontSize: 14, height: 1.4, color: AppColors.text),
              ),
              const SizedBox(height: 16),
              GameButton(
                label: t.gotIt,
                width: 180,
                height: 42,
                fontSize: 14,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final s = ref.watch(settingsProvider);
    final game = ref.watch(selectedGameProvider);
    return Scaffold(
      body: DesignCanvas(
        child: Stack(
          children: [
            Positioned(left: 47, top: 42, child: CoinsTile(coins: s.coins)),
            Positioned(
              left: 190,
              top: 42,
              child: GestureDetector(
                onTap: () => _open(context, const SettingsScreen()),
                child: Row(
                  children: [
                    FramedTile(
                      size: 120,
                      frameColor: AppColors.active,
                      child: AvatarImage(s.avatar, size: 120),
                    ),
                    const SizedBox(width: 18),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name.toUpperCase(), style: AppText.label(30, weight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text(t.winsGames(s.wins, s.games),
                            style: AppText.label(17, color: AppColors.textDim)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Closed the app mid-match? The seat is still there.
            if (ref.watch(activeMatchProvider).valueOrNull case final match?)
              Positioned(
                right: 50,
                top: 46,
                child: HighlightPulse(
                  highlightColor: AppColors.gold,
                  borderRadius: 14,
                  child: GameButton(
                    label: t.rejoinMatch,
                    icon: Icons.login_rounded,
                    color: AppColors.gold,
                    width: 420,
                    height: 70,
                    fontSize: 21,
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final api = ref.read(apiProvider)!;
                      final wsUrl = await ref.read(sessionProvider.notifier).realtimeUrl();
                      await openOnlineMatch(
                        navigator,
                        api,
                        gameId: match['gameId'] as int,
                        roomId: match['roomId'] as int?,
                        gameKey: match['game'] as String,
                        seat: match['seat'] as int,
                        shotSeconds: match['shotSeconds'] as int,
                        players: (match['players'] as List).cast<Map<String, dynamic>>(),
                        wsUrl: wsUrl,
                        replace: false,
                      );
                      ref.invalidate(activeMatchProvider);
                    },
                  ),
                ),
              ),
            if (Env.isDemo)
              Positioned(
                right: 50,
                top: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gold, width: 2),
                  ),
                  child: Text(t.demoBuild, style: AppText.label(16, color: AppColors.gold)),
                ),
              ),
            Positioned(left: 110, top: 232, child: _Logo(s.tableSkin)),
            Positioned(
              left: 930,
              top: 176,
              width: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.chooseGame, style: AppText.label(17, color: AppColors.textDim)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    children: [
                      for (final g in AppGame.values)
                        _GameTile(
                          game: g,
                          selected: g == game,
                          onTap: () => ref.read(selectedGameProvider.notifier).state = g,
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  GameButton(
                    label: game.players == 4 ? 'PLAY VS BOTS' : 'PLAY VS BOT',
                    icon: Icons.smart_toy_rounded,
                    width: 560,
                    height: 84,
                    fontSize: 28,
                    onPressed: () => _open(context, LobbyScreen(game: game)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      GameButton(
                        label: 'PASS & PLAY',
                        icon: Icons.groups_rounded,
                        width: 272,
                        height: 70,
                        fontSize: 19,
                        color: AppColors.gold,
                        onPressed: () => _open(context, LobbyScreen(game: game, passAndPlay: true)),
                      ),
                      const SizedBox(width: 16),
                      GameButton(
                        label: 'ONLINE',
                        icon: Icons.public_rounded,
                        width: 272,
                        height: 70,
                        fontSize: 19,
                        color: AppColors.frame,
                        onPressed: () => Env.hasBackend
                            ? _openOnline(context, ref, OnlineLobbyScreen(game: game))
                            : _onlineInfo(context, t),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 110,
              right: 110,
              bottom: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GameButton(
                    label: 'LEADERBOARD',
                    icon: Icons.leaderboard_rounded,
                    width: 430,
                    height: 84,
                    fontSize: 22,
                    color: const Color(0xFF2B2B38),
                    onPressed: () => _open(context, const LeaderboardScreen()),
                  ),
                  GameButton(
                    label: 'HOW TO PLAY',
                    icon: Icons.menu_book_rounded,
                    width: 430,
                    height: 84,
                    fontSize: 22,
                    color: const Color(0xFF2B2B38),
                    onPressed: () => _open(context, const HowToPlayScreen()),
                  ),
                  GameButton(
                    label: 'PROFILE & TABLES',
                    icon: Icons.settings_rounded,
                    width: 430,
                    height: 84,
                    fontSize: 22,
                    color: const Color(0xFF2B2B38),
                    onPressed: () => _open(context, const SettingsScreen()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game, required this.selected, required this.onTap});

  final AppGame game;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ball = game.iconBall;
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 272,
        height: 92,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: panelDecoration(
          radius: 20,
          border: selected ? AppColors.active : AppColors.frame,
          borderWidth: selected ? 4 : 2,
          glow: selected ? AppColors.active : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              child: Center(
                child: ball != null
                    ? BallIcon(ball, size: 52)
                    : const CardFace(card: PlayingCard(1, Suit.spades), width: 38),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(game.title,
                        style: AppText.label(20,
                            color: selected ? AppColors.active : AppColors.text, weight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 4),
                  Text(game.tagline,
                      maxLines: 2, style: AppText.label(10.5, color: AppColors.textDim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo(this.skinId);

  final String skinId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 780,
      height: 470,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The table itself, tilted and fading into the room.
          Positioned(
            left: 150,
            top: -40,
            child: Transform.rotate(
              angle: -0.1,
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, 0.5, 0.95],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: Opacity(
                  opacity: 0.75,
                  child: TableArt(skin: DemoData.skin(skinId), width: 620),
                ),
              ),
            ),
          ),
          for (final (i, card) in const [
            PlayingCard(1, Suit.spades),
            PlayingCard(13, Suit.hearts),
            PlayingCard(7, Suit.diamonds),
          ].indexed)
            Positioned(
              left: 20.0 + i * 105,
              top: 10.0 + (i - 1).abs() * 22,
              child: Transform.rotate(angle: (i - 1) * 0.22, child: CardFace(card: card, width: 135)),
            ),
          for (final (i, n) in const [1, 13, 7, 14, 15].indexed)
            Positioned(left: 420.0 + i * 62, top: 120.0 - (i.isOdd ? 38 : 0), child: BallIcon(n, size: 68)),
          Positioned(
            left: 0,
            top: 250,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BILLIARD',
                    style: AppText.label(88, weight: FontWeight.w900).copyWith(
                      height: 1,
                      shadows: const [Shadow(color: Colors.black, blurRadius: 18, offset: Offset(0, 6))],
                    )),
                Text('POKER',
                    style: AppText.label(88, color: AppColors.active, weight: FontWeight.w900).copyWith(
                      height: 1,
                      shadows: const [
                        Shadow(color: Color(0xAA2EE84F), blurRadius: 34),
                        Shadow(color: Colors.black, blurRadius: 14, offset: Offset(0, 6)),
                      ],
                    )),
                const SizedBox(height: 14),
                Text('4 GAMES  |  BOTS  |  PASS & PLAY',
                    style: AppText.label(19, color: AppColors.gold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
