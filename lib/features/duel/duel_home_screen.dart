import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../misc/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/env.dart';
import '../../core/orientation.dart';
import '../../core/push_service.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';
import '../../data/api_client.dart';
import '../../data/app_game.dart';
import '../game/widgets/ball_painter.dart' show paintBall;
import '../misc/leaderboard_screen.dart';
import '../online/online_screens.dart';
import '../online/notification_unread.dart';
import '../online/session.dart';
import '../carrom/carrom_lobby_screen.dart';
import '../ludo/ludo_board.dart';
import '../ludo/ludo_lobby_screen.dart';
import '../misc/how_to_play_screen.dart';
import 'bet_level_screen.dart';
import 'practice_launch.dart';
import 'challenge_inbox_host.dart';
import 'challenge_screen.dart';
import 'history_screen.dart';
import 'home_portrait_widgets.dart';
import 'notices_screen.dart';
import 'notifications_screen.dart';
import 'refer_screen.dart';
import 'lobby_data.dart';
import 'pool_hub_screen.dart';
import '../../l10n/strings.dart';
import 'items_screen.dart';
import 'shop_screen.dart';
import '../start/auth_prompt.dart';

/// Home lobby in the Pool City look (portrait): wallet and shortcuts across
/// the top, the player's rank in the middle, Pool / Ludo hero tiles, the
/// Carrom / Friends / Practice row, a wide banner and the five-tab bar.
/// Every game gets the same billing.
class DuelHomeScreen extends ConsumerStatefulWidget {
  const DuelHomeScreen({super.key});

  @override
  ConsumerState<DuelHomeScreen> createState() => _DuelHomeScreenState();
}

class _DuelHomeScreenState extends ConsumerState<DuelHomeScreen> with WidgetsBindingObserver {
  Timer? _refresh;
  Timer? _pushPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Wallet and "players online" stay current while the lobby is open.
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (ModalRoute.of(context)?.isCurrent ?? false) ref.read(lobbyProvider.notifier).refresh();
    });
    _pushPoll = Timer.periodic(const Duration(seconds: 25), (_) => _pollPush());
    _pollPush();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(audioProvider).playMenuMusic();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    _pushPoll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
      ref.read(audioProvider).playMenuMusic();
    }
  }

  void _reload() {
    ref.read(lobbyProvider.notifier).refresh();
    ref.invalidate(activeMatchProvider);
    _pollPush();
  }

  Future<void> _pollPush() async {
    if (!Env.hasBackend) return;
    final api = ref.read(apiProvider);
    if (api == null || !ref.read(sessionProvider).signedIn) return;
    try {
      final poll = await PushService.pollInbox(api);
      if (mounted) ref.read(notificationUnreadProvider.notifier).set(poll.unread);
      if (poll.walletChanged) {
        await ref.read(sessionProvider.notifier).refresh();
        if (mounted) ref.read(lobbyProvider.notifier).refresh();
      }
    } on Object {
      // offline
    }
  }

  /// Anything opened from here may change coins or leave a match running.
  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _reload();
  }

  /// Screens that need an account (shop, items, challenge, history, mail).
  Future<void> _openRegistered(Widget screen) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (mounted) await _open(screen);
  }

  Future<void> _rejoin(Map<String, dynamic> match) async {
    await openOnlineMatchFromActivePayload(Navigator.of(context), ref, match);
    if (mounted) _reload();
  }

  /// A dialog with one big button per choice.
  Future<void> _chooser({required String title, required String body, required List<(String, Color, VoidCallback)> choices}) =>
      showDuelDialog<void>(
        context,
        barrierColor: DesignAuth.overlayScrim,
        builder: (dialog) => PcDialog(
          title: title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(body, textAlign: TextAlign.center, style: pcText(32, color: DesignColors.pcTextDim, weight: FontWeight.w500).copyWith(height: 1.35)),
              const SizedBox(height: 28),
              for (final (label, color, go) in choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: PcButton(
                    label: label,
                    width: 760,
                    style: pcStyleFor(color),
                    onPressed: () {
                      Navigator.of(dialog).pop();
                      go();
                    },
                  ),
                ),
            ],
          ),
        ),
      );

  static const _poolColor = DuelColors.green;
  static const _ludoColor = DesignColors.ludoAccent;
  static const _carromColor = DesignColors.carromAccent;

  static DuelMode _friendsDuelMode(AppGame game) => switch (game) {
        AppGame.poker => DuelMode.poker,
        AppGame.eightBall => DuelMode.eight,
        AppGame.nineBall => DuelMode.nine,
        AppGame.tenBall => DuelMode.ten,
      };

  void _practiceLudoPick() {
    final t = ref.read(stringsProvider);
    _chooser(
      title: t.ludoTitle,
      body: t.practiceSubLudo,
      choices: [
        (t.twoPlayers, _ludoColor, () => launchLudoPractice(context, ref, players: 2)),
        (t.fourPlayers, _ludoColor, () => launchLudoPractice(context, ref, players: 4)),
      ],
    );
  }

  void _practice() {
    final t = ref.read(stringsProvider);
    _chooser(
      title: t.practiceTitle,
      body: t.practiceChooserBody,
      choices: [
        (t.poolTitle, _poolColor, () => showPoolPracticeDialog(context, open: _open)),
        (t.ludoTitle, _ludoColor, _practiceLudoPick),
        (t.carromTitle, _carromColor, () => launchCarromPractice(context, ref)),
      ],
    );
  }

  Future<void> _friends() async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (!mounted) return;
    final t = ref.read(stringsProvider);
    _chooser(
      title: t.friendsTitle,
      body: t.friendsBody,
      choices: [
        (t.poolTitle, _poolColor, _friendsPool),
        (t.ludoPlayers(2), _ludoColor, () => _open(const BetLevelScreen(mode: DuelMode.ludo2, friendsRoom: true))),
        (t.ludoPlayers(4), _ludoColor, () => _open(const BetLevelScreen(mode: DuelMode.ludo4, friendsRoom: true))),
        (t.carromTitle, _carromColor, () => _open(const BetLevelScreen(mode: DuelMode.carrom, friendsRoom: true))),
      ],
    );
  }

  void _friendsPool() {
    final t = ref.read(stringsProvider);
    _chooser(
      title: t.poolFriendsTitle,
      body: t.poolFriendsBody,
      choices: [
        for (final game in AppGame.values)
          (
            t.appGameTitle(game),
            game == AppGame.poker ? DuelColors.purple : DuelColors.blue,
            () => _open(BetLevelScreen(mode: _friendsDuelMode(game), friendsRoom: true)),
          ),
      ],
    );
  }

  Future<void> _daily(DailyBonus daily) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (!mounted) return;
    await showDuelDialog<void>(
      context,
      barrierColor: const Color(0xB3000000),
      builder: (_) => _DailyBonusDialog(daily: daily),
    );
  }

  void _missions() {
    final t = ref.read(stringsProvider);
    showDuelMessage(context, title: t.missions, body: t.missionsBody, icon: Icons.flag_rounded);
  }

  Future<void> _profile() async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (mounted) await _open(const SettingsScreen());
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final lobby = ref.watch(lobbyProvider);
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(settingsProvider);
    final registered = hasRegisteredAccount(ref);
    final active = ref.watch(activeMatchProvider).valueOrNull;
    final challengePending = ref.watch(challengePendingCountProvider);
    final unread = ref.watch(notificationUnreadProvider);
    final data = lobby.valueOrNull;
    final coins = lobbyDisplayCoins(ref);
    final dailyReady = data?.daily.available ?? false;
    final lobbyError = lobby.hasError && data == null;

    return OrientationLock(
      orientation: AppOrientation.portrait,
      child: PortraitCanvas(
        builder: (context, height) {
          // Reference layout is 2340 tall; shorter screens tighten the gaps.
          final roomy = height >= 2200;
          const edge = 20.0;
          // The two hero tiles share one slanted edge: 528 + 512 = full width.
          const heroLeftW = 528.0;
          const heroRightW = PortraitCanvas.width - edge * 2 - heroLeftW;
          const smallW = (PortraitCanvas.width - edge * 2 - 2 * 18) / 3; // ~335
          final daily = data?.daily;
          return Column(
            children: [
              SizedBox(height: roomy ? 24 : 12),
              HomeTopBar(
                avatar: settings.avatar,
                registered: registered,
                level: session.level,
                coins: coins,
                gems: registered ? session.gems : null,
                placeholder: t.signUpOrLogin,
                unread: unread,
                onProfile: () {
                  AudioService.tap();
                  _profile();
                },
                onWallet: () {
                  AudioService.tap();
                  _openRegistered(const ShopScreen());
                },
                onMail: () async {
                  if (!await requireRegisteredAccount(context, ref)) return;
                  if (mounted) await showNoticesDialog(context, ref);
                },
                onBell: () async {
                  if (!await requireRegisteredAccount(context, ref)) return;
                  if (mounted) await showNotificationsDialog(context, ref);
                  if (mounted) _reload();
                },
                onSettings: _profile,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: edge),
                  child: Column(
                    children: [
                      SizedBox(height: roomy ? 16 : 6),
                      // --- shortcuts down both sides, the rank block between them
                      SizedBox(
                        height: 470,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 4,
                              top: 0,
                              child: Column(
                                children: [
                                  HomeSquareButton(
                                    icon: Icons.assignment_turned_in_rounded,
                                    iconColor: const Color(0xFFFFB13D),
                                    tag: 'NEW',
                                    onTap: _missions,
                                  ),
                                  const SizedBox(height: 14),
                                  HomeSquareButton(
                                    icon: Icons.menu_book_rounded,
                                    iconColor: const Color(0xFFC9B8FF),
                                    size: 84,
                                    onTap: () => _open(const HowToPlayScreen()),
                                  ),
                                  const SizedBox(height: 14),
                                  HomeSquareButton(
                                    icon: Icons.query_stats_rounded,
                                    iconColor: const Color(0xFF9CC2FF),
                                    size: 84,
                                    onTap: () => _openRegistered(const HistoryScreen()),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Column(
                                children: [
                                  HomeRoundButton(
                                    icon: Icons.sports_kabaddi_rounded,
                                    iconColor: const Color(0xFF8FD3FF),
                                    label: t.navChallenge,
                                    count: challengePending,
                                    onTap: () => _openRegistered(const ChallengeScreen()),
                                  ),
                                  const SizedBox(height: 4),
                                  HomeRoundButton(
                                    icon: Icons.card_giftcard_rounded,
                                    iconColor: const Color(0xFFFF9A2E),
                                    label: t.refer,
                                    onTap: () => _openRegistered(const ReferScreen()),
                                  ),
                                ],
                              ),
                            ),
                            Align(
                              alignment: const Alignment(0, 1),
                              child: RankBlock(
                                registered: registered,
                                tier: session.rankTier,
                                rankName: registered ? session.rankName : t.browseProfileTitle,
                                position: registered ? '${session.level}' : '—',
                                avatar: settings.avatar,
                                name: registered ? settings.name : titleCase(t.browseProfileSub),
                                coins: coins == null ? '—' : formatCoins(coins, compact: coins >= 10000000),
                                onTap: () => _open(const LeaderboardScreen()),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // --- the two hero games (one slanted gap between them)
                      Row(
                        children: [
                          HeroTile(
                            width: heroLeftW,
                            height: 350,
                            slantRight: true,
                            colors: const [DesignColors.pcTileOrange, DesignColors.pcTileOrangeDeep],
                            label: t.playPool,
                            artInsets: const EdgeInsets.fromLTRB(26, 4, 70, 96),
                            art: const Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(child: RackArt()),
                                Positioned(right: -50, bottom: -56, child: TapHandHint(size: 170)),
                              ],
                            ),
                            onTap: () => _open(const PoolHubScreen()),
                          ),
                          HeroTile(
                            width: heroRightW,
                            height: 350,
                            slantRight: false,
                            colors: const [DesignColors.pcTilePink, DesignColors.pcTilePinkDeep],
                            label: t.playLudo,
                            artInsets: const EdgeInsets.fromLTRB(40, 10, 40, 92),
                            art: const FloatBob(child: LudoHeroArt()),
                            crown: true,
                            onTap: () => _open(const LudoLobbyScreen()),
                          ),
                        ],
                      ),
                      SizedBox(height: roomy ? 48 : 30),
                      // --- carrom, friends, practice
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SmallTile(
                              width: smallW - 4,
                              height: 250,
                              colors: const [DesignColors.pcTileTeal, DesignColors.pcTileTealDeep],
                              label: t.carromTitle,
                              onTap: () => _open(const CarromLobbyScreen()),
                              child: const FloatBob(amplitude: 5, period: Duration(milliseconds: 3100), child: CarromArt(transparent: true)),
                            ),
                            SmallTile(
                              width: smallW - 4,
                              height: 250,
                              colors: const [DesignColors.pcTileBlue, DesignColors.pcTileBlueDeep],
                              label: t.navFriends,
                              onTap: _friends,
                              child: const Icon(Icons.groups_rounded, color: Colors.white, size: 136, shadows: [Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 4))]),
                            ),
                            SmallTile(
                              width: smallW - 4,
                              height: 250,
                              colors: const [DesignColors.pcTileGreen, DesignColors.pcTileGreenDeep],
                              label: t.practice,
                              onTap: _practice,
                              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 136, shadows: [Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 4))]),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(flex: 2),
                      // --- ladder panel (the reference's season pass): daily bonus,
                      //     or the running match to rejoin
                      Align(
                        alignment: Alignment.centerLeft,
                        child: active != null
                            ? HighlightPulse(
                                highlightColor: DuelColors.gold,
                                onTap: () {
                                  AudioService.tap();
                                  _rejoin(active);
                                },
                                child: HomeWideBanner(
                                  width: 748,
                                  height: 200,
                                  title: t.matchInProgress,
                                  icon: PulseBadge(
                                    minScale: 0.94,
                                    maxScale: 1.12,
                                    child: const Icon(Icons.play_circle_fill_rounded, color: DuelColors.gold, size: 48),
                                  ),
                                  rim: DuelColors.gold,
                                  glow: true,
                                  onTap: () => _rejoin(active),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(titleCase(t.rejoinMatch), style: pcText(44, color: DuelColors.gold)),
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_rounded, color: DuelColors.gold, size: 56),
                                    ],
                                  ),
                                ),
                              )
                            : LadderPanel(
                                width: 748,
                                title: t.dailyBonus,
                                timer: daily == null
                                    ? Text(lobbyError ? titleCase(t.offline) : '...', style: pcText(28, color: lobbyError ? DuelColors.red : DesignColors.pcGold))
                                    : dailyReady
                                        ? Text(titleCase(t.claimNow), style: pcText(28, color: const Color(0xFF4DF08A)))
                                        : _Countdown(from: data!.fetchedAt, seconds: daily.secondsToNext, size: 28, color: DesignColors.pcGold),
                                boxes: [
                                  if (daily == null || daily.rewards.isEmpty)
                                    // Offline / loading: the ladder's shape with empty boxes.
                                    for (var i = 0; i < 3; i++)
                                      LadderBox(
                                        art: const Opacity(opacity: 0.45, child: PikoCoinIcon(size: 62)),
                                        count: '—',
                                        caption: titleCase(t.dayLabel(i + 1)),
                                      )
                                  else
                                    for (var i = max(0, min(daily.day, daily.rewards.length - 3)); i < min(daily.rewards.length, max(0, min(daily.day, daily.rewards.length - 3)) + 3); i++)
                                      LadderBox(
                                        art: daily.rewards[i].gems > 0 ? const GemIcon(size: 62) : const PikoCoinIcon(size: 62),
                                        count: formatCoins(daily.rewards[i].gems > 0 ? daily.rewards[i].gems : daily.rewards[i].coins, compact: true),
                                        caption: titleCase(t.dayLabel(i + 1)),
                                        highlight: daily.rewards[i].gems > 0,
                                        done: i < daily.day || (i == daily.day && !dailyReady),
                                      ),
                                ],
                                progress: daily == null || daily.rewards.isEmpty ? 0 : (daily.day + (dailyReady ? 0 : 1)) / daily.rewards.length,
                                footnote: data == null ? null : '${titleCase(t.online)} ${formatCoins(data.online)}',
                                onTap: data == null ? _reload : () => _daily(data.daily),
                              ),
                      ),
                      if (lobbyError)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            lobby.error is ApiException ? t.maybeApi((lobby.error as ApiException).message) : t.offlineServer,
                            style: pcText(22, color: DuelColors.red, weight: FontWeight.w500),
                          ),
                        ),
                      SizedBox(height: roomy ? 60 : 30),
                    ],
                  ),
                ),
              ),
              HomeBottomNav(
                items: [
                  HomeNavItem(icon: Icons.smart_toy_rounded, label: t.practice, onTap: _practice),
                  HomeNavItem(icon: Icons.leaderboard_rounded, label: t.navRankings, onTap: () => _open(const LeaderboardScreen())),
                  HomeNavItem(icon: Icons.home_rounded, label: t.navHome, active: true, onTap: _reload),
                  HomeNavItem(icon: Icons.backpack_rounded, label: t.navItems, onTap: () => _openRegistered(const ItemsScreen())),
                  HomeNavItem(icon: Icons.shopping_cart_rounded, label: t.navShop, onTap: () => _openRegistered(const ShopScreen())),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Ticks down to the next daily bonus.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.from, required this.seconds, this.size = 14, this.color = DesignColors.pcTextDim});

  final DateTime from;
  final int seconds;
  final double size;
  final Color color;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late final Timer _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _timer.isActive;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = max(0, widget.seconds - DateTime.now().difference(widget.from).inSeconds);
    String two(int v) => v.toString().padLeft(2, '0');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, color: widget.color, size: widget.size * 1.1),
        const SizedBox(width: 4),
        Text('${two(left ~/ 3600)}:${two(left % 3600 ~/ 60)}:${two(left % 60)}', style: pcText(widget.size, color: widget.color)),
      ],
    );
  }
}

/// Tall game card of the landscape hubs (pool hub). Not used on the home any
/// more, kept for [PoolHubScreen].
class GameCard extends ConsumerWidget {
  const GameCard({super.key, required this.width, required this.color, required this.title, required this.sub, required this.art, required this.onPlay});

  final double width;
  final Color color;
  final String title;
  final String? sub;
  final Widget art;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return PressScale(
        onTap: onPlay,
        scale: 0.97,
        child: Container(
          width: width,
          height: 448,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color, width: 2.5),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(color, Colors.black, 0.55)!, Color.lerp(color, Colors.black, 0.9)!, const Color(0xFF05060C)],
              stops: const [0, 0.55, 1],
            ),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 34, spreadRadius: 1),
              const BoxShadow(color: Color(0xBB000000), blurRadius: 18, offset: Offset(0, 12)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                Positioned(left: 0, right: 0, top: 0, height: 258, child: art),
                // Fade the artwork into the caption.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 170,
                  height: 100,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [const Color(0x00000000), Color.lerp(color, Colors.black, 0.88)!],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          textAlign: TextAlign.center,
                          style: AppText.label(40, color: Colors.white, weight: FontWeight.w900).copyWith(height: 1.0, letterSpacing: 1, shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 16), const Shadow(color: Color(0xAA000000), blurRadius: 4, offset: Offset(0, 2))])),
                      if (sub != null) ...[
                        const SizedBox(height: 6),
                        Text(sub!, textAlign: TextAlign.center, style: AppText.label(15, color: Colors.white, weight: FontWeight.w700)),
                      ],
                      const SizedBox(height: 14),
                      DuelButton(label: t.playNow, color: color, width: width - 28, height: 54, fontSize: 22, onPressed: onPlay),
                    ],
                  ),
                ),
                // Polished glass over the whole card and a light inner trim.
                const DuelGloss(radius: 15, strength: 0.18, diagonal: true),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1.2)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }
}

/// Green felt, a cue and a handful of balls with the 9 up front.
class BilliardArt extends StatelessWidget {
  const BilliardArt({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _BilliardArtPainter());
}

class _BilliardArtPainter extends CustomPainter {
  const _BilliardArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.2),
          radius: 0.9,
          colors: [Color(0xFF2FA45C), Color(0xFF166B38), Color(0xFF062A14)],
        ).createShader(rect),
    );
    final w = size.width, h = size.height;
    // Cue across the cloth.
    canvas.save();
    canvas.translate(w * 0.5, h * 0.62);
    canvas.rotate(-0.12);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-w * 0.7, -5, w * 1.4, 10), const Radius.circular(5)),
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFF6B3519), Color(0xFFE9C98F), Color(0xFFF7E3BD)])
              .createShader(Rect.fromLTWH(-w * 0.7, -5, w * 1.4, 10)));
    canvas.restore();
    paintBall(canvas, Offset(w * 0.13, h * 0.45), 24, 4);
    paintBall(canvas, Offset(w * 0.45, h * 0.18), 15, 1);
    paintBall(canvas, Offset(w * 0.66, h * 0.26), 20, 3);
    paintBall(canvas, Offset(w * 0.9, h * 0.34), 24, 8);
    paintBall(canvas, Offset(w * 0.2, h * 0.14), 13, 11);
    paintBall(canvas, Offset(w * 0.5, h * 0.56), 62, 9);
  }

  @override
  bool shouldRepaint(_BilliardArtPainter old) => false;
}

/// Purple felt: a fan of cards, stacks of chips and the 9 ball.
class PokerArt extends StatelessWidget {
  const PokerArt({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _PokerArtPainter());
}

class _PokerArtPainter extends CustomPainter {
  const _PokerArtPainter();

  void _card(Canvas canvas, Offset c, double angle, String rank, String suit, bool red) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    const size = Size(92, 128);
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height), const Radius.circular(9));
    canvas.drawRRect(r.shift(const Offset(3, 5)), Paint()..color = const Color(0x80000000));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFF6F3EA));
    final color = red ? const Color(0xFFD12B3C) : const Color(0xFF15171C);
    void text(String s, double fontSize, Offset at, {String? family}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontFamily: family ?? AppText.card, fontSize: fontSize, color: color, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    text(rank, 30, const Offset(-27, -42));
    text(suit, 20, const Offset(-27, -16), family: 'sans-serif');
    text(suit, 50, const Offset(8, 22), family: 'sans-serif');
    canvas.restore();
  }

  void _chips(Canvas canvas, Offset base, int count, Color color) {
    for (var i = 0; i < count; i++) {
      final c = base - Offset(0, i * 9.0);
      final oval = Rect.fromCenter(center: c, width: 74, height: 30);
      canvas.drawOval(oval.shift(const Offset(0, 8)), Paint()..color = Color.lerp(color, Colors.black, 0.6)!);
      canvas.drawOval(oval, Paint()..color = color);
      canvas.drawOval(
          oval.deflate(7),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: 0.75));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.1),
          radius: 0.95,
          colors: [Color(0xFF5A2FB0), Color(0xFF2C1466), Color(0xFF0D0624)],
        ).createShader(rect),
    );
    final w = size.width, h = size.height;
    _chips(canvas, Offset(w * 0.12, h * 0.56), 3, const Color(0xFF2A2F6B));
    _card(canvas, Offset(w * 0.3, h * 0.42), -0.28, 'A', '♠', false);
    _card(canvas, Offset(w * 0.47, h * 0.36), -0.04, 'K', '♥', true);
    _card(canvas, Offset(w * 0.64, h * 0.4), 0.22, 'Q', '♣', false);
    paintBall(canvas, Offset(w * 0.8, h * 0.56), 50, 9);
    _chips(canvas, Offset(w * 0.3, h * 0.84), 4, const Color(0xFF3B3F8C));
    _chips(canvas, Offset(w * 0.52, h * 0.9), 3, const Color(0xFF23265A));
    paintBall(canvas, Offset(w * 0.92, h * 0.2), 13, 3);
  }

  @override
  bool shouldRepaint(_PokerArtPainter old) => false;
}

/// A mini carrom board for the game card. [transparent] skips the dark
/// background so the board can sit on a coloured tile.
class CarromArt extends StatelessWidget {
  const CarromArt({super.key, this.transparent = false, this.themeIndex = 0});

  final bool transparent;
  final int themeIndex;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CarromArtPainter(transparent, themeIndex));
}

class _CarromArtPainter extends CustomPainter {
  const _CarromArtPainter(this.transparent, this.themeIndex);

  final bool transparent;
  final int themeIndex;

  // Per-tier wood frame colors
  static const _frames = [
    Color(0xFF7A6040), // Rookie: light maple
    Color(0xFF5B3A2E), // Bronze: classic teak
    Color(0xFF3A4848), // Silver: cool slate
    Color(0xFF6A4A00), // Gold: mahogany
    Color(0xFF3A1848), // Platinum: dark ebony
    Color(0xFF103050), // Diamond: exotic ocean wood
  ];
  // Per-tier cloth (playing field) colors
  static const _cloths = [
    Color(0xFFEACC98), // Rookie: light maple felt
    Color(0xFFE8BF8E), // Bronze: classic warm felt
    Color(0xFFB0C4A8), // Silver: slate-green felt
    Color(0xFFD4A060), // Gold: rich teak felt
    Color(0xFFB8A0C4), // Platinum: dark purple felt
    Color(0xFF90B8D4), // Diamond: ocean blue felt
  ];
  static const _lines = [
    Color(0xFF9A7850), Color(0xFFA2613B), Color(0xFF6A8080),
    Color(0xFF8A6010), Color(0xFF7A5890), Color(0xFF3A6888),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final idx = themeIndex.clamp(0, _frames.length - 1);
    final frameColor = _frames[idx];
    final clothColor = _cloths[idx];
    final lineColor = _lines[idx];

    final rect = Offset.zero & size;
    if (!transparent) {
      canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF4A1414), Color(0xFF1A0808)]).createShader(rect));
    }
    final b = size.shortestSide * (transparent ? 0.96 : 0.82);
    final left = (size.width - b) / 2, top = (size.height - b) / 2 + (transparent ? 0 : size.height * 0.04);
    final board = Rect.fromLTWH(left, top, b, b);
    if (transparent) {
      canvas.drawRRect(RRect.fromRectAndRadius(board.shift(Offset(0, b * 0.04)), Radius.circular(b * 0.05)), Paint()
        ..color = const Color(0x88000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, b * 0.03));
    }
    canvas.drawRRect(RRect.fromRectAndRadius(board, Radius.circular(b * 0.05)), Paint()..color = frameColor);
    final f = b * 0.06;
    final field = board.deflate(f);
    canvas.drawRect(field, Paint()..color = clothColor);
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = lineColor;
    final u = field.width;
    for (final s in const [0.16, 0.84]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(field.left + u * 0.19, field.top + u * (s - 0.03), field.left + u * 0.81, field.top + u * (s + 0.03)), Radius.circular(u * 0.03)), line);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(field.left + u * (s - 0.03), field.top + u * 0.19, field.left + u * (s + 0.03), field.top + u * 0.81), Radius.circular(u * 0.03)), line);
    }
    canvas.drawCircle(field.center, u * 0.17, line);
    for (final c in [field.topLeft, field.topRight, field.bottomLeft, field.bottomRight]) {
      canvas.drawCircle(c + Offset(c.dx < field.center.dx ? u * 0.04 : -u * 0.04, c.dy < field.center.dy ? u * 0.04 : -u * 0.04), u * 0.05, Paint()..color = const Color(0xFF111111));
    }
    final r = u * 0.03;
    canvas.drawCircle(field.center, r, Paint()..color = const Color(0xFFE53935));
    for (var k = 0; k < 6; k++) {
      final a = -3.14159 / 2 + k * 3.14159 / 3;
      final p = field.center + Offset(2.1 * r * cos(a), 2.1 * r * sin(a));
      canvas.drawCircle(p, r, Paint()..color = k.isEven ? const Color(0xFF2C2F33) : const Color(0xFFEFE3D2));
    }
    canvas.drawCircle(Offset(field.center.dx, field.top + u * 0.84), r * 1.35, Paint()..color = const Color(0xFFE53935));
  }

  @override
  bool shouldRepaint(_CarromArtPainter old) => old.transparent != transparent || old.themeIndex != themeIndex;
}

/// A mini Ludo board for the game card. [transparent] skips the wooden
/// background so the board can sit on a coloured tile.
class LudoArt extends StatelessWidget {
  const LudoArt({super.key, this.transparent = false, this.themeIndex = 0});

  final bool transparent;
  final int themeIndex;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _LudoArtPainter(transparent, themeIndex));
}

class _LudoArtPainter extends CustomPainter {
  const _LudoArtPainter(this.transparent, this.themeIndex);

  final bool transparent;
  final int themeIndex;

  // Per-tier board field (background) colors
  static const _fields = [
    Color(0xFFEDF5E8), // Rookie: green-tinted ivory
    Color(0xFFF5EDD8), // Bronze: warm cream
    Color(0xFFEAEDF2), // Silver: cool gray
    Color(0xFFF5F0E8), // Gold: classic ivory
    Color(0xFFE8E0F5), // Platinum: lavender
    Color(0xFFDFEBFF), // Diamond: ice blue
  ];
  // Per-tier track cell colors
  static const _tracks = [
    Color(0xFFCBE0C3), // Rookie: light green
    Color(0xFFD4B882), // Bronze: warm tan
    Color(0xFFBDC9D8), // Silver: steel gray
    Color(0xFFE0DACE), // Gold: classic tan
    Color(0xFFC4B0E8), // Platinum: purple
    Color(0xFFABC4EE), // Diamond: periwinkle
  ];
  static const _gridColors = [
    Color(0xFF99BB88), Color(0xFFBBAA88), Color(0xFF9AAABB),
    Color(0xFFCCCCCC), Color(0xFF9A80CC), Color(0xFF8AAAD8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final idx = themeIndex.clamp(0, _fields.length - 1);
    final fieldColor = _fields[idx];
    final trackColor = _tracks[idx];
    final gridColor = _gridColors[idx];

    final b = size.shortestSide * (transparent ? 0.96 : 0.82);
    final left = (size.width - b) / 2;
    final top = (size.height - b) / 2 + (transparent ? 0 : size.height * 0.04);
    final s = b / LudoBoard.n;

    Rect cellRect(int col, int row) => Rect.fromLTWH(left + col * s, top + row * s, s, s);
    Offset at(double gx, double gy) => Offset(left + gx * s, top + gy * s);

    if (!transparent) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A2606), Color(0xFF1A1206)],
          ).createShader(Offset.zero & size),
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left, top + s * 0.6, b, b), Radius.circular(s * 0.1)),
        Paint()
          ..color = const Color(0x88000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.6),
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top, b, b), Radius.circular(s * 0.1)),
      Paint()..color = fieldColor,
    );

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = gridColor;

    for (final c in LudoBoard.path) {
      canvas.drawRect(cellRect(c[0], c[1]), Paint()..color = trackColor);
      canvas.drawRect(cellRect(c[0], c[1]), grid);
    }

    for (var colour = 0; colour < 4; colour++) {
      for (final c in LudoBoard.homeColumn[colour]) {
        canvas.drawRect(cellRect(c[0], c[1]), Paint()..color = LudoBoard.colours[colour].withValues(alpha: 0.80));
        canvas.drawRect(cellRect(c[0], c[1]), grid);
      }
    }

    final mid = at(7.5, 7.5);
    final corners = [at(6, 6), at(9, 6), at(9, 9), at(6, 9)];
    void tri(Offset a, Offset b2, Color col) => canvas.drawPath(
      Path()..moveTo(mid.dx, mid.dy)..lineTo(a.dx, a.dy)..lineTo(b2.dx, b2.dy)..close(),
      Paint()..color = col,
    );
    tri(corners[0], corners[1], LudoBoard.colours[2]);
    tri(corners[1], corners[2], LudoBoard.colours[3]);
    tri(corners[2], corners[3], LudoBoard.colours[0]);
    tri(corners[3], corners[0], LudoBoard.colours[1]);

    for (var colour = 0; colour < 4; colour++) {
      final y = LudoBoard.yardRect[colour];
      final rect = Rect.fromLTWH(left + y[0] * s, top + y[1] * s, y[2] * s, y[2] * s);
      final col = LudoBoard.colours[colour];
      canvas.drawRect(rect, Paint()..color = col);
      final inner = Rect.fromLTWH(rect.left + s, rect.top + s, s * 4, s * 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(s * 0.18)),
        Paint()..color = fieldColor,
      );
      for (final spot in LudoBoard.yard[colour]) {
        canvas.drawCircle(at(spot[0], spot[1]), s * 0.44, Paint()..color = col);
        canvas.drawCircle(
          at(spot[0], spot[1]),
          s * 0.44,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white.withValues(alpha: 0.7),
        );
      }
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top, b, b), Radius.circular(s * 0.1)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = gridColor,
    );
  }

  @override
  bool shouldRepaint(_LudoArtPainter old) => old.transparent != transparent || old.themeIndex != themeIndex;
}

/// Wide banner of the landscape hubs (pool hub). Kept for [PoolHubScreen].
class HomeBanner extends StatelessWidget {
  const HomeBanner({super.key, required this.title, required this.sub, required this.colors, required this.rim, required this.titleColor, required this.icon, required this.onTap});

  final String title;
  final String sub;
  final List<Color> colors;
  final Color rim;
  final Color titleColor;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        onTap: onTap,
        scale: 0.97,
        child: Container(
          width: 366,
          height: 160,
          padding: const EdgeInsets.fromLTRB(22, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: rim, width: 2),
            gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: colors),
            boxShadow: [
              const BoxShadow(color: Color(0xAA000000), blurRadius: 16, offset: Offset(0, 8)),
              BoxShadow(color: rim.withValues(alpha: 0.35), blurRadius: 22),
            ],
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppText.label(26, color: titleColor, weight: FontWeight.w900).copyWith(height: 1.05, shadows: [Shadow(color: titleColor.withValues(alpha: 0.6), blurRadius: 14)])),
                        const SizedBox(height: 8),
                        Text(sub, style: AppText.label(12, color: Colors.white, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  icon,
                ],
              ),
              const Positioned(left: -22, right: -14, top: -14, bottom: -14, child: Stack(children: [DuelGloss(radius: 18, strength: 0.16)])),
            ],
          ),
        ),
      );
}

/// The bonus ladder: one reward a day, bigger each day in a row.
class _DailyBonusDialog extends ConsumerStatefulWidget {
  const _DailyBonusDialog({required this.daily});

  final DailyBonus daily;

  @override
  ConsumerState<_DailyBonusDialog> createState() => _DailyBonusDialogState();
}

class _DailyBonusDialogState extends ConsumerState<_DailyBonusDialog> {
  late bool _available = widget.daily.available;
  bool _busy = false;
  String? _note;
  int _celebrate = 0;

  Future<void> _claim() async {
    setState(() => _busy = true);
    try {
      final reward = await ref.read(lobbyProvider.notifier).claimDaily();
      ref.read(audioProvider).play(Sfx.success);
      if (!mounted) return;
      setState(() {
        _available = false;
        _celebrate++;
        _note = '+${formatPicoCoins(reward.coins)}${reward.gems > 0 ? '  +${reward.gems} GEMS' : ''}';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _note = e.message.toUpperCase());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 0 later, 1 today, 2 collected.
  int _stateOf(int i) {
    final d = widget.daily;
    return i < d.day || (i == d.day && !_available) ? 2 : (i == d.day ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final d = widget.daily;
    final n = d.rewards.length;
    // The reference's calendar: small cells three to a row, the last day a
    // tall card on the right.
    const cell = 194.0, cellH = 230.0, gap = 14.0, bigW = 240.0;
    final small = n - 1;
    final rows = small <= 0 ? 1 : ((small + 2) ~/ 3);
    final bigH = rows * cellH + (rows - 1) * gap;
    // Reference: a pale-blue calendar sheet with the big title, the close
    // cross above its corner and a violet strip for the action.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 1000,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: PressScale(
                onTap: () => Navigator.of(context).pop(),
                scale: 0.9,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close_rounded, color: Colors.white, size: 76, shadows: [Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 3))]),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(30, 26, 30, 34),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFD6E6FF), Color(0xFFA9C6FA), Color(0xFF8FB0F2)]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 30, offset: Offset(0, 14))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(t.dailyBonus.toUpperCase(), style: pcText(104, color: const Color(0xFF2D46B8), shadow: false).copyWith(letterSpacing: 2)),
                  ),
                  Text(t.dailyBonusGrow, textAlign: TextAlign.center, style: pcText(28, color: const Color(0xFF34407A), weight: FontWeight.w500, shadow: false)),
                  const SizedBox(height: 22),
                  if (n > 0)
                    PopCelebration(
                      trigger: _celebrate,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (small > 0)
                            Expanded(
                              child: Wrap(
                                spacing: gap,
                                runSpacing: gap,
                                children: [
                                  for (var i = 0; i < small; i++)
                                    _DayCell(day: i + 1, coins: d.rewards[i].coins, gems: d.rewards[i].gems, state: _stateOf(i), width: cell, height: cellH, label: t.dayLabel(i + 1)),
                                ],
                              ),
                            ),
                          if (small > 0) const SizedBox(width: 20),
                          _DayCell(day: n, coins: d.rewards[n - 1].coins, gems: d.rewards[n - 1].gems, state: _stateOf(n - 1), width: bigW, height: bigH, label: t.dayLabel(n), big: true),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(30, 26, 30, 30),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF5B4BD6), Color(0xFF3A2FA6)]),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border.all(color: const Color(0xFF8C7CE8), width: 3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_note != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(_note!, textAlign: TextAlign.center, style: pcText(36, color: const Color(0xFF4DF08A))),
                    ),
                  if (_available)
                    PcButton(label: _busy ? '...' : t.claim, style: PcButtonStyle.gold, width: 460, height: 110, fontSize: 46, onPressed: _busy ? null : _claim)
                  else
                    PcButton(label: t.close, style: PcButtonStyle.blue, width: 360, onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One day of the bonus calendar: number in the corner, the reward art,
/// the amount along the bottom; a tick once collected, a gold rim today.
class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.coins, required this.gems, required this.state, required this.width, required this.height, required this.label, this.big = false});

  final int day;
  final int coins;
  final int gems;
  final int state;
  final double width;
  final double height;
  final String label;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final today = state == 1, done = state == 2;
    final premium = gems > 0 || big;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: premium
              ? const [Color(0xFF8E4CF0), Color(0xFF4B1FA8)]
              : (day <= 2 ? const [Color(0xFFF7C24A), Color(0xFFD98A12)] : const [Color(0xFF3D7BE8), Color(0xFF1E3FA8)]),
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: today ? DesignColors.pcGold : Colors.white.withValues(alpha: 0.55), width: today ? 4 : 2.5),
        boxShadow: [
          const BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 4)),
          if (today) BoxShadow(color: DesignColors.pcGold.withValues(alpha: 0.5), blurRadius: 18),
        ],
      ),
      child: Stack(
        children: [
          Positioned(left: 12, top: 6, child: Text(day.toString().padLeft(2, '0'), style: pcText(big ? 44 : 34, color: Colors.white.withValues(alpha: 0.7)))),
          Center(
            child: Opacity(
              opacity: done ? 0.4 : 1,
              child: gems > 0 ? GemIcon(size: big ? 150 : 96) : PikoCoinIcon(size: big ? 150 : 96),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 10,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                gems > 0 ? '${formatCoins(coins, compact: true)}  +$gems' : formatCoins(coins, compact: true),
                style: pcText(big ? 34 : 28),
              ),
            ),
          ),
          if (done)
            const Center(child: Icon(Icons.check_circle_rounded, color: Color(0xFF4DF08A), size: 80, shadows: [Shadow(color: Color(0xCC000000), blurRadius: 8)])),
        ],
      ),
    );
  }
}
