import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../data/app_game.dart';
import '../../data/demo_data.dart';
import '../game/widgets/table_art.dart';
import '../lobby/lobby_screen.dart';
import 'duel_home_screen.dart' show CarromArt, LudoArt;
import 'practice_launch.dart';
import '../misc/leaderboard_screen.dart';
import '../misc/settings_screen.dart';
import 'lobby_data.dart';
import '../online/online_screens.dart';
import 'matchmaking_screen.dart';
import 'shop_screen.dart';
import 'challenge_flow.dart';
import 'challenge_inbox_pulse.dart';
import '../../l10n/strings.dart';
import '../online/session.dart';
import '../../data/api_client.dart';
import 'not_enough_balance.dart';
import '../start/auth_prompt.dart';

/// Pick what to play for: the reference's stake cards — a row of venues,
/// cheapest to richest, that scrolls sideways with the chosen one large in
/// the middle; each card names its prize and entry fee.
class BetLevelScreen extends ConsumerStatefulWidget {
  const BetLevelScreen({
    super.key,
    required this.mode,
    this.practiceFirst = false,
    this.friendsRoom = false,
    this.challengeTarget,
  });

  final DuelMode mode;

  /// Open straight on the free practice choice.
  final bool practiceFirst;

  /// Pick a stake, then open a private room (play with friends).
  final bool friendsRoom;

  /// Same stake UI as play, but tap sends a 1v1 challenge.
  final ChallengeTarget? challengeTarget;

  @override
  ConsumerState<BetLevelScreen> createState() => _BetLevelScreenState();
}

class _BetLevelScreenState extends ConsumerState<BetLevelScreen> {
  static const _cardWidth = 760.0;
  PageController? _pages;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    ref.read(lobbyProvider.notifier).refresh();
    if (widget.practiceFirst)
      WidgetsBinding.instance.addPostFrameCallback((_) => _practice());
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
    return _pages = PageController(
      initialPage: _selected,
      viewportFraction: _cardWidth * 0.78 / PortraitCanvas.width,
    );
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) ref.read(lobbyProvider.notifier).refresh();
  }

  Future<void> _play(BetLevel level) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (!mounted) return;
    final coins = ref.read(settingsProvider).coins;
    if (coins < level.buyIn) {
      promptNotEnoughBalance(context, need: level.buyIn, have: coins);
      return;
    }
    final target = widget.challengeTarget;
    if (target != null) {
      await _sendChallenge(target, level);
      return;
    }
    if (widget.friendsRoom) {
      await _open(
        OnlineLobbyScreen.stakedPrivate(
          gameKey: widget.mode.apiName,
          level: level,
        ),
      );
      return;
    }
    await _open(MatchmakingScreen(mode: widget.mode, level: level));
  }

  Future<void> _sendChallenge(ChallengeTarget target, BetLevel level) async {
    if (!mounted) return;
    try {
      final ch = await ref
          .read(sessionProvider.notifier)
          .sendChallenge(target.userId, widget.mode.apiName, level.level);
      requestChallengeInboxPoll();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChallengeWaitScreen(
            challengeId: ch['id'] as int,
            opponentName: target.name,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isNotEnoughCoins(e)) {
        await promptNotEnoughBalance(
          context,
          need: level.buyIn,
          have: ref.read(settingsProvider).coins,
        );
        return;
      }
      final t = ref.read(stringsProvider);
      showDuelMessage(
        context,
        title: t.challengePageTitle,
        body: t.maybeApi(e.message),
        icon: Icons.error_outline_rounded,
      );
    }
  }

  AppGame? _poolGameForMode(DuelMode mode) => switch (mode) {
    DuelMode.eight => AppGame.eightBall,
    DuelMode.nine => AppGame.nineBall,
    DuelMode.ten => AppGame.tenBall,
    DuelMode.poker => AppGame.poker,
    _ => null,
  };

  void _practiceLudo(int players) {
    final t = ref.read(stringsProvider);
    showOfflinePracticeModeDialog(
      context,
      ref,
      modeLabel: t.ludoPlayers(players),
      onVsBots: () => _open(
        buildLudoPracticeScreen(ref, players: players, passAndPlay: false),
      ),
      onPassAndPlay: () => _open(
        buildLudoPracticeScreen(ref, players: players, passAndPlay: true),
      ),
    );
  }

  void _practiceCarrom() {
    final t = ref.read(stringsProvider);
    showOfflinePracticeModeDialog(
      context,
      ref,
      modeLabel: t.carromTitle,
      onVsBots: () => _open(buildCarromPracticeScreen(ref, passAndPlay: false)),
      onPassAndPlay: () =>
          _open(buildCarromPracticeScreen(ref, passAndPlay: true)),
    );
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

  Future<void> _gated(Widget screen) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (mounted) await _open(screen);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final lobby = ref.watch(lobbyProvider);
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final registered = hasRegisteredAccount(ref);
    final coins = settings.coins;
    final levels = lobby.valueOrNull?.levelsFor(widget.mode);
    return PcPage(
      header: PcHeader(
        avatar: settings.avatar,
        name: settings.name,
        registered: registered,
        level: session.level,
        coins: lobbyDisplayCoins(ref),
        gems: registered ? session.gems : null,
        placeholder: t.signUpOrLogin,
        onProfile: () => _gated(const SettingsScreen()),
        onWallet: () => _gated(const ShopScreen()),
      ),
      title: widget.challengeTarget != null
          ? t.challengePlayer(widget.challengeTarget!.name)
          : widget.mode.title,
      panel: false,
      scroll: false,
      bodyPadding: EdgeInsets.zero,
      minHeight: 1900,
      bottomTrailing: Row(
        children: [
          _SmallIconButton(
            Icons.local_police_rounded,
            () => showDuelMessage(
              context,
              title: t.clubsTitle,
              body: t.clubsBody,
              icon: Icons.local_police_rounded,
            ),
          ),
          const SizedBox(width: 14),
          _SmallIconButton(
            Icons.groups_rounded,
            () => showDuelMessage(
              context,
              title: t.friendsTitle,
              body: t.friendsNavBody,
              icon: Icons.groups_rounded,
            ),
          ),
          const SizedBox(width: 14),
          _SmallIconButton(
            Icons.leaderboard_rounded,
            () => _open(const LeaderboardScreen()),
          ),
          const SizedBox(width: 14),
          _SmallIconButton(
            Icons.shopping_cart_rounded,
            () => _gated(const ShopScreen()),
          ),
        ],
      ),
      body: levels == null
          ? Center(
              child: lobby.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titleCase(t.offlineServer),
                          style: pcText(36, color: DuelColors.red),
                        ),
                        const SizedBox(height: 30),
                        PcButton(
                          label: t.tryAgain,
                          width: 400,
                          onPressed: () => ref.invalidate(lobbyProvider),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            )
          : Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  widget.challengeTarget != null
                      ? t.challengePlayer(widget.challengeTarget!.name)
                      : t.modeSubtitle(widget.mode),
                  textAlign: TextAlign.center,
                  style: pcText(
                    28,
                    color: DesignColors.pcTextDim,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                // Level chips, cheapest to richest.
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    itemCount: levels.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, i) {
                      final on = i == _selected;
                      return GestureDetector(
                        onTap: () {
                          AudioService.tap();
                          _pages?.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOut,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 30),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: on
                                ? const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFFF9C64A),
                                      Color(0xFFD08A10),
                                    ],
                                  )
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFF3E3456),
                                      Color(0xFF342B4C),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: on ? 0.75 : 0.2,
                              ),
                              width: on ? 2.5 : 1.5,
                            ),
                            boxShadow: on
                                ? [
                                    const BoxShadow(
                                      color: Color(0x88F7C04A),
                                      blurRadius: 14,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            levels[i].displayName,
                            style: pcText(
                              30,
                              color: on
                                  ? Colors.white
                                  : const Color(0xFFB3B4D9),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _Carousel(
                    controller: _controller(levels, coins),
                    levels: levels,
                    mode: widget.mode,
                    coins: coins,
                    cardWidth: _cardWidth,
                    selected: _selected,
                    onSelect: (i) => setState(() => _selected = i),
                    onPlay: _play,
                    challengeMode: widget.challengeTarget != null,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton(this.icon, this.onTap);

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PcButton(
    label: '',
    icon: icon,
    width: 110,
    height: 96,
    fontSize: 44,
    onPressed: onTap,
  );
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
    this.challengeMode = false,
  });

  final PageController controller;
  final List<BetLevel> levels;
  final DuelMode mode;
  final int coins;
  final double cardWidth;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<BetLevel> onPlay;
  final bool challengeMode;

  @override
  Widget build(BuildContext context) {
    final step = cardWidth * 0.78;
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          // The cards are drawn here, farthest first, so the chosen one sits on
          // top of its neighbours; the page view below only supplies scrolling.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final page = controller.position.haveDimensions
                      ? (controller.page ?? selected.toDouble())
                      : selected.toDouble();
                  final order = [for (var i = 0; i < levels.length; i++) i]
                    ..sort(
                      (a, b) => (page - b).abs().compareTo((page - a).abs()),
                    );
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final i in order)
                        Positioned(
                          left:
                              c.maxWidth / 2 -
                              cardWidth / 2 +
                              (i - page) * step,
                          top: 8,
                          bottom: 8,
                          child: Builder(
                            builder: (context) {
                              final away = (page - i).abs().clamp(0.0, 2.0);
                              // The middle card is full size and bright; neighbours shrink and dim.
                              return Transform.scale(
                                scale:
                                    1 -
                                    0.14 * away.clamp(0.0, 1.0) -
                                    0.05 * (away - 1).clamp(0.0, 1.0),
                                child: Opacity(
                                  opacity: 1 - 0.45 * away.clamp(0.0, 1.0),
                                  child: _LevelCard(
                                    level: levels[i],
                                    index: i,
                                    mode: mode,
                                    width: cardWidth,
                                    affordable: coins >= levels[i].buyIn,
                                    active: (page - i).abs() < 0.5,
                                    challengeMode: challengeMode,
                                  ),
                                ),
                              );
                            },
                          ),
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
                  controller.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                  );
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

/// One stake card: mode in the corner, the venue (a table skin), its name,
/// the prize band, the entry fee, players and the tap hint.
class _LevelCard extends ConsumerWidget {
  const _LevelCard({
    required this.level,
    required this.index,
    required this.mode,
    required this.width,
    required this.affordable,
    required this.active,
    this.challengeMode = false,
  });

  final BetLevel level;
  final int index;
  final DuelMode mode;
  final double width;
  final bool affordable;
  final bool active;
  final bool challengeMode;

  static const _cardTopActive = [
    Color(0xFF5DBD50),
    Color(0xFFD49050),
    Color(0xFF90A8C0),
    Color(0xFFF5B942),
    Color(0xFFA070D8),
    Color(0xFF6090E8),
  ];
  static const _cardBotActive = [
    Color(0xFF2E7828),
    Color(0xFF8B5820),
    Color(0xFF5A7090),
    Color(0xFFB87214),
    Color(0xFF5A28A0),
    Color(0xFF2040A0),
  ];
  static const _cardTopDim = [
    Color(0xFF264E20),
    Color(0xFF4A3010),
    Color(0xFF303848),
    Color(0xFF4A3808),
    Color(0xFF3A1860),
    Color(0xFF1A2850),
  ];
  static const _cardBotDim = [
    Color(0xFF143010),
    Color(0xFF2E1808),
    Color(0xFF1C2430),
    Color(0xFF2E2004),
    Color(0xFF200A40),
    Color(0xFF0C1428),
  ];
  static const _boardTopActive = [
    Color(0xFF4AAE42),
    Color(0xFFC08040),
    Color(0xFF80A0B8),
    Color(0xFFF7DC6A),
    Color(0xFF9060C8),
    Color(0xFF5080D8),
  ];
  static const _boardBotActive = [
    Color(0xFF246820),
    Color(0xFF7A5018),
    Color(0xFF4A6878),
    Color(0xFFD09020),
    Color(0xFF481890),
    Color(0xFF183088),
  ];
  static const _glows = [
    Color(0xAA3A9A30),
    Color(0xAAC47030),
    Color(0xAA6A90B0),
    Color(0xAAF7C04A),
    Color(0xAA8A50C8),
    Color(0xAA4A80E8),
  ];
  static const _borders = [
    Color(0xFF5DBD50),
    Color(0xFFD49050),
    Color(0xFF90A8C0),
    Color(0xFFF7C04A),
    Color(0xFFA070D8),
    Color(0xFF6090E8),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final poker = mode == DuelMode.poker;
    final carrom = mode == DuelMode.carrom;
    final ludo = mode == DuelMode.ludo2 || mode == DuelMode.ludo4;
    final board = carrom || ludo;
    String plain(int v) =>
        v >= 10000 ? formatCoins(v, compact: true) : formatCoins(v);
    final winLine = poker
        ? plain(level.maxPrize!)
        : plain(level.prize ?? level.stake * mode.seats);
    final skin = DemoData.tableSkins[(index + 2) % DemoData.tableSkins.length];
    final gold = active;
    final tierIdx = index.clamp(0, _cardTopActive.length - 1);
    final cardTop = gold ? _cardTopActive[tierIdx] : _cardTopDim[tierIdx];
    final cardBottom = gold ? _cardBotActive[tierIdx] : _cardBotDim[tierIdx];
    final boardTop = gold ? _boardTopActive[tierIdx] : _cardTopDim[tierIdx];
    final boardBottom = gold ? _boardBotActive[tierIdx] : _cardBotDim[tierIdx];
    final venueLabel = poker
        ? titleCase(t.billiardPokerCardTitle)
        : titleCase(
            board
                ? '${level.displayName} ${mode.title}'
                : '${level.displayName} ${skin.name}',
          );

    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cardTop, cardBottom],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: gold
              ? _borders[tierIdx].withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.18),
          width: gold ? 2.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.72),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
          if (gold)
            BoxShadow(color: _glows[tierIdx], blurRadius: 56, spreadRadius: 4),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Art area: full-bleed with overlaid labels and venue name ──
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Gradient background for board games; pool uses card gradient
                if (board)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [boardTop, boardBottom],
                      ),
                    ),
                  ),
                // Art: contained + padded (bottom padding reserves space for name)
                Center(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      board ? 50 : 28,
                      board ? 48 : 28,
                      board ? 50 : 28,
                      90,
                    ),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: board
                          ? (carrom
                                ? SizedBox(
                                    width: 560,
                                    height: 560,
                                    child: CarromArt(
                                      transparent: true,
                                      themeIndex: tierIdx,
                                    ),
                                  )
                                : SizedBox(
                                    width: 560,
                                    height: 560,
                                    child: LudoArt(
                                      transparent: true,
                                      themeIndex: tierIdx,
                                    ),
                                  ))
                          : Container(
                              decoration: const BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x88000000),
                                    blurRadius: 22,
                                    offset: Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: TableArt(skin: skin, width: 620),
                            ),
                    ),
                  ),
                ),
                // Bottom gradient — makes name readable
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.44, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.76),
                        ],
                      ),
                    ),
                  ),
                ),
                // Top-left: mode chip
                Positioned(
                  top: 20,
                  left: 22,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.52),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(titleCase(mode.title), style: pcText(26)),
                  ),
                ),
                // Top-right: info button
                Positioned(
                  top: 16,
                  right: 20,
                  child: Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.42),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Text('i', style: pcText(30, shadow: false)),
                  ),
                ),
                // Bottom: venue / level name overlaid on art
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Text(
                    venueLabel,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: pcText(46),
                  ),
                ),
              ],
            ),
          ),
          // ── Prize band ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            color: Colors.black.withValues(alpha: 0.52),
            child: Row(
              children: [
                Text(
                  '${titleCase(poker ? t.winUpTo : t.prize)}:',
                  style: pcText(38, weight: FontWeight.w700),
                ),
                const SizedBox(width: 14),
                Text(winLine, style: pcText(54, weight: FontWeight.w800)),
                const SizedBox(width: 10),
                const PikoCoinIcon(size: 60),
              ],
            ),
          ),
          Container(height: 1.5, color: Colors.white.withValues(alpha: 0.12)),
          // ── Entry fee ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            child: Row(
              children: [
                Text(
                  '${titleCase(t.entryFee(level.buyIn).split(':').first)}:',
                  style: pcText(34),
                ),
                const SizedBox(width: 10),
                Text(
                  plain(level.buyIn),
                  style: pcText(40, weight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                const PikoCoinIcon(size: 50),
              ],
            ),
          ),
          if (poker)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
              child: Text(
                t.minPrizePlayers(level.minPrize!),
                style: pcText(24, weight: FontWeight.w500),
              ),
            ),
          Container(height: 1.5, color: Colors.white.withValues(alpha: 0.1)),
          // ── Players + hint ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            color: Colors.black.withValues(alpha: 0.28),
            child: Row(
              children: [
                Icon(
                  Icons.person_rounded,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 40,
                ),
                const SizedBox(width: 6),
                Text(
                  formatCoins(level.players),
                  style: pcText(36, weight: FontWeight.w600),
                ),
                const Spacer(),
                if (active)
                  affordable
                      ? Row(
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              color: Colors.white.withValues(alpha: 0.8),
                              size: 36,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              titleCase(
                                challengeMode ? t.tapToChallenge : t.tapToPlay,
                              ),
                              style: pcText(28),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            const Icon(
                              Icons.lock_rounded,
                              color: Color(0xFFFF8AA0),
                              size: 34,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              titleCase(t.notEnoughBalance),
                              style: pcText(26, color: const Color(0xFFFF8AA0)),
                            ),
                          ],
                        ),
              ],
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
  return showDuelDialog<void>(
    context,
    barrierColor: DesignAuth.overlayScrim,
    builder: (dialog) => Consumer(
      builder: (context, ref, _) {
        final t = ref.watch(stringsProvider);
        return PcDialog(
          title: t.practice,
          width: 820,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.practiceLong,
                textAlign: TextAlign.center,
                style: pcText(
                  28,
                  color: DesignColors.pcTextDim,
                  weight: FontWeight.w500,
                ).copyWith(height: 1.3),
              ),
              const SizedBox(height: 16),
              for (final pick in games) ...[
                if (games.length > 1) ...[
                  const SizedBox(height: 8),
                  Text(titleCase(t.appGameTitle(pick)), style: pcText(30)),
                  const SizedBox(height: 10),
                ],
                PcButton(
                  label: t.vsBots,
                  width: 640,
                  height: 84,
                  fontSize: 34,
                  onPressed: () {
                    Navigator.of(dialog).pop();
                    open(LobbyScreen(game: pick));
                  },
                ),
                const SizedBox(height: 12),
                PcButton(
                  label: t.passAndPlay,
                  width: 640,
                  height: 84,
                  fontSize: 34,
                  style: PcButtonStyle.gold,
                  onPressed: () {
                    Navigator.of(dialog).pop();
                    open(LobbyScreen(game: pick, passAndPlay: true));
                  },
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
