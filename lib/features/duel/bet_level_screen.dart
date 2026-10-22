import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../data/app_game.dart';
import '../../data/demo_data.dart';
import '../carrom/carrom_controller.dart';
import '../carrom/carrom_screen.dart';
import '../game/game_controller.dart' show SeatConfig;
import '../lobby/lobby_screen.dart';
import '../ludo/ludo_controller.dart';
import '../ludo/ludo_screen.dart';
import '../misc/leaderboard_screen.dart';
import 'duel_chrome.dart';
import 'lobby_data.dart';
import '../online/online_screens.dart';
import 'matchmaking_screen.dart';
import 'shop_screen.dart';
import '../../l10n/strings.dart';

/// Pick what to play for: a row of tables, cheapest to richest, that scrolls
/// sideways with the chosen one large in the middle.
class BetLevelScreen extends ConsumerStatefulWidget {
  const BetLevelScreen({super.key, required this.mode, this.practiceFirst = false, this.friendsRoom = false});

  final DuelMode mode;

  /// Open straight on the free practice choice.
  final bool practiceFirst;

  /// Pick a stake, then open a private room (play with friends).
  final bool friendsRoom;

  @override
  ConsumerState<BetLevelScreen> createState() => _BetLevelScreenState();
}

class _BetLevelScreenState extends ConsumerState<BetLevelScreen> {
  static const _cardWidth = 372.0;
  PageController? _pages;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    ref.read(lobbyProvider.notifier).refresh();
    if (widget.practiceFirst) WidgetsBinding.instance.addPostFrameCallback((_) => _practice());
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  /// Starts on the richest table the player can afford.
  PageController _controller(List<BetLevel> levels, int coins) {
    if (_pages != null) return _pages!;
    _selected = 0;
    for (var i = 0; i < levels.length; i++) {
      if (levels[i].buyIn <= coins) _selected = i;
    }
    return _pages = PageController(initialPage: _selected, viewportFraction: _cardWidth * 0.78 / DuelCanvas.size.width);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) ref.read(lobbyProvider.notifier).refresh();
  }

  void _play(BetLevel level) {
    final coins = ref.read(settingsProvider).coins;
    if (coins < level.buyIn) {
      _open(const ShopScreen(initialTab: 1));
      return;
    }
    if (widget.friendsRoom) {
      _open(OnlineLobbyScreen.stakedPrivate(gameKey: widget.mode.apiName, level: level));
      return;
    }
    _open(MatchmakingScreen(mode: widget.mode, level: level));
  }

  AppGame? _poolGameForMode(DuelMode mode) => switch (mode) {
        DuelMode.eight => AppGame.eightBall,
        DuelMode.nine => AppGame.nineBall,
        DuelMode.ten => AppGame.tenBall,
        DuelMode.poker => AppGame.poker,
        _ => null,
      };

  void _practiceLudo(int players) {
    final s = ref.read(settingsProvider);
    const colour = 0;
    final colours = players == 2 ? [colour, (colour + 2) % 4] : [colour, 1, 2, 3];
    final seats = [
      SeatConfig(name: s.name, avatar: s.avatar),
      for (var i = 1; i < players; i++)
        SeatConfig(
          name: DemoData.botNames[(i - 1) % DemoData.botNames.length],
          avatar: DemoData.botAvatars[(i - 1) % DemoData.botAvatars.length],
          isBot: true,
        ),
    ];
    _open(LudoScreen(
      config: LudoMatchConfig(seats: players, players: seats, shotSeconds: s.shotSeconds, humanSeats: 1),
      colours: colours,
    ));
  }

  void _practiceCarrom() {
    final s = ref.read(settingsProvider);
    _open(CarromScreen(
      config: CarromMatchConfig(
        seats: [
          SeatConfig(name: s.name, avatar: s.avatar),
          SeatConfig(
            name: DemoData.botNames[0],
            avatar: DemoData.botAvatars[0],
            isBot: true,
            botSkill: s.botSkill,
          ),
        ],
        shotSeconds: s.shotSeconds,
        strikerSkin: s.carromStriker,
        pieceSkin: s.carromPieces,
        boardSkin: s.carromBoard,
      ),
    ));
  }

  void _practice() {
    final mode = widget.mode;
    if (mode == DuelMode.ludo2) {
      _practiceLudo(2);
      return;
    }
    if (mode == DuelMode.ludo4) {
      _practiceLudo(4);
      return;
    }
    if (mode == DuelMode.carrom) {
      _practiceCarrom();
      return;
    }
    final game = _poolGameForMode(mode);
    showPoolPracticeDialog(context, open: _open, game: game);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final lobby = ref.watch(lobbyProvider);
    final coins = ref.watch(settingsProvider).coins;
    final levels = lobby.valueOrNull?.levelsFor(widget.mode);
    return DuelCanvas(
      child: Stack(
        children: [
          const Positioned(left: 0, right: 0, top: 6, child: DuelTopBar()),
          if (levels == null)
            Positioned.fill(
              child: Center(
                child: lobby.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.offlineServer, style: AppText.label(22, color: DuelColors.red)),
                          const SizedBox(height: 16),
                          DuelButton(label: t.tryAgain, onPressed: () => ref.invalidate(lobbyProvider)),
                        ],
                      )
                    : const CircularProgressIndicator(color: DuelColors.silver),
              ),
            )
          else ...[
            Positioned(
              left: 36,
              right: 36,
              top: 152,
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: levels.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final on = i == _selected;
                  return GestureDetector(
                    onTap: () {
                      AudioService.tap();
                      _pages?.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      alignment: Alignment.center,
                      decoration: duelPanel(radius: 14, rim: on ? DuelColors.gold : DuelColors.rim, glow: on),
                      child: Text(levels[i].displayName,
                          style: AppText.label(18, color: on ? DuelColors.gold : Colors.white, weight: FontWeight.w900)),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 220,
              height: 490,
              child: _Carousel(
                controller: _controller(levels, coins),
                levels: levels,
                mode: widget.mode,
                coins: coins,
                cardWidth: _cardWidth,
                selected: _selected,
                onSelect: (i) => setState(() => _selected = i),
                onPlay: _play,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 126,
              child: Center(
                child: Text(
                  t.modeSubtitle(widget.mode),
                  style: AppText.label(15, color: DuelColors.dim, weight: FontWeight.w700),
                ),
              ),
            ),
          ],
          Positioned(
            left: 42,
            top: 722,
            child: Row(
              children: [
                NavTile(
                  icon: Icons.local_police_rounded,
                  label: t.navClub,
                  onTap: () => showDuelMessage(context,
                      title: t.clubsTitle, body: t.clubsBody, icon: Icons.local_police_rounded),
                ),
                const SizedBox(width: 19),
                NavTile(
                  icon: Icons.groups_rounded,
                  label: t.navFriends,
                  onTap: () => showDuelMessage(context,
                      title: t.friendsTitle,
                      body: t.friendsNavBody,
                      icon: Icons.groups_rounded),
                ),
                const SizedBox(width: 19),
                NavTile(icon: Icons.leaderboard_rounded, label: t.navRankings, onTap: () => _open(const LeaderboardScreen())),
                const SizedBox(width: 19),
                NavTile(icon: Icons.storefront_rounded, label: t.navShop, onTap: () => _open(const ShopScreen())),
                const SizedBox(width: 19),
                NavTile(icon: Icons.reply_rounded, label: t.navBack, onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Carousel extends StatelessWidget {
  const _Carousel({
    required this.controller,
    required this.levels,
    required this.mode,
    required this.coins,
    required this.cardWidth,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
  });

  final PageController controller;
  final List<BetLevel> levels;
  final DuelMode mode;
  final int coins;
  final double cardWidth;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<BetLevel> onPlay;

  @override
  Widget build(BuildContext context) {
    final step = cardWidth * 0.78;
    return Stack(
      children: [
        // The cards are drawn here, farthest first, so the chosen one sits on
        // top of its neighbours; the page view below only supplies scrolling.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final page = controller.position.haveDimensions ? (controller.page ?? selected.toDouble()) : selected.toDouble();
                final order = [for (var i = 0; i < levels.length; i++) i]..sort((a, b) => (page - b).abs().compareTo((page - a).abs()));
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final i in order)
                      Positioned(
                        left: DuelCanvas.size.width / 2 - cardWidth / 2 + (i - page) * step,
                        top: 8,
                        child: Builder(builder: (context) {
                          final away = (page - i).abs().clamp(0.0, 2.0);
                          // The middle card is full size and bright; neighbours shrink and dim.
                          return Transform.scale(
                            scale: 1 - 0.2 * away.clamp(0.0, 1.0) - 0.06 * (away - 1).clamp(0.0, 1.0),
                            child: Opacity(
                              opacity: 1 - 0.4 * away.clamp(0.0, 1.0),
                              child: _LevelCard(
                                level: levels[i],
                                mode: mode,
                                color: DuelColors.level(i),
                                affordable: coins >= levels[i].buyIn,
                                active: (page - i).abs() < 0.5,
                              ),
                            ),
                          );
                        }),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        PageView.builder(
          controller: controller,
          itemCount: levels.length,
          onPageChanged: (i) {
            AudioService.instance?.play(Sfx.tick, volume: 0.5);
            onSelect(i);
          },
          itemBuilder: (context, i) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AudioService.tap();
              if (i == selected) {
                onPlay(levels[i]);
              } else {
                controller.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
              }
            },
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _LevelCard extends ConsumerWidget {
  const _LevelCard({required this.level, required this.mode, required this.color, required this.affordable, required this.active});

  final BetLevel level;
  final DuelMode mode;
  final Color color;
  final bool affordable;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final poker = mode == DuelMode.poker;
    String plain(int v) => v >= 10000 ? formatCoins(v, compact: true) : '$v';
    final headline = level.displayName;
    final winLine = poker ? plain(level.maxPrize!) : plain(level.prize ?? level.stake * mode.seats);
    return Container(
      width: 372,
      height: 470,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: active ? 3 : 2),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, const Color(0xFF05060C), 0.72)!, const Color(0xFF080A14), const Color(0xFF05060C)],
          stops: const [0, 0.5, 1],
        ),
        boxShadow: [
          if (active) BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 36, spreadRadius: 1),
          const BoxShadow(color: Color(0xB3000000), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 36),
              Text(t.stakeAmount(level.stake), style: AppText.label(26, color: DuelColors.gold, weight: FontWeight.w800)),
              const SizedBox(height: 14),
              // The glowing rule under the prize.
              Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 36),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)]),
                  boxShadow: [BoxShadow(color: color, blurRadius: 12)],
                ),
              ),
              const SizedBox(height: 16),
              Text(poker ? t.winUpTo : t.prize, style: AppText.label(18, color: DuelColors.silver, weight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(winLine, style: AppText.label(34, color: Colors.white, weight: FontWeight.w900)),
              const SizedBox(height: 16),
              Text(headline,
                  style: AppText.label(30, color: poker ? DuelColors.gold : Colors.white, weight: FontWeight.w900).copyWith(
                    shadows: [Shadow(color: color.withValues(alpha: 0.65), blurRadius: 16)],
                  )),
              const SizedBox(height: 14),
              if (poker)
                Text(t.minPrizePlayers(level.minPrize!),
                    style: AppText.label(14, color: Color.lerp(color, Colors.white, 0.35)!, weight: FontWeight.w700))
              else
                Text(t.playersOnline, style: AppText.label(18, color: Color.lerp(color, Colors.white, 0.2)!, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.groups_rounded, color: Color.lerp(color, Colors.white, 0.2), size: 30),
                  const SizedBox(width: 10),
                  Text(poker ? '${formatCoins(level.players)} PLAYING' : formatCoins(level.players),
                      style: AppText.label(20, color: Color.lerp(color, Colors.white, 0.2)!, weight: FontWeight.w800)),
                ],
              ),
            ],
          ),
          if (active)
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Center(
                child: affordable
                    ? Text(t.tapToPlay, style: AppText.label(15, color: Colors.white.withValues(alpha: 0.75), weight: FontWeight.w800))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_rounded, color: DuelColors.red, size: 20),
                          const SizedBox(width: 6),
                          Text(t.notEnoughCoin, style: AppText.label(15, color: DuelColors.red, weight: FontWeight.w800)),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Free pool matches on this device: every pool game against bots or passing
/// the phone around. [open] pushes the chosen screen.
Future<void> showPoolPracticeDialog(
  BuildContext context, {
  required Future<void> Function(Widget screen) open,
  AppGame? game,
}) {
  final games = game != null ? [game] : AppGame.values;
  return     showDuelDialog<void>(
    context,
    barrierColor: const Color(0xB3000000),
    builder: (dialog) => Consumer(
      builder: (context, ref, _) {
        final t = ref.watch(stringsProvider);
        return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(22),
        decoration: duelPanel(rim: DuelColors.rimLight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.practice, style: AppText.label(18, weight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(t.practiceLong,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.4, color: DuelColors.dim)),
            const SizedBox(height: 12),
            for (final pick in games)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 150, child: Text(t.appGameTitle(pick), style: AppText.label(13, color: DuelColors.silver))),
                    DuelButton(
                      label: t.vsBots,
                      width: 140,
                      height: 40,
                      fontSize: 14,
                      onPressed: () {
                        Navigator.of(dialog).pop();
                        open(LobbyScreen(game: pick));
                      },
                    ),
                    const SizedBox(width: 8),
                    DuelButton(
                      label: t.passAndPlay,
                      width: 150,
                      height: 40,
                      fontSize: 14,
                      color: DuelColors.blue,
                      onPressed: () {
                        Navigator.of(dialog).pop();
                        open(LobbyScreen(game: pick, passAndPlay: true));
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
      },
    ),
  );
}
