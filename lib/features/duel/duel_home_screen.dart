import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/env.dart';
import '../../core/push_service.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
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
import '../ludo/ludo_lobby_screen.dart';
import '../misc/how_to_play_screen.dart';
import 'bet_level_screen.dart';
import 'practice_launch.dart';
import 'challenge_inbox_host.dart';
import 'challenge_screen.dart';
import 'duel_chrome.dart';
import 'history_screen.dart';
import 'refer_screen.dart';
import 'lobby_data.dart';
import 'pool_hub_screen.dart';
import '../../l10n/strings.dart';
import 'items_screen.dart';
import 'shop_screen.dart';

/// Home lobby: pick Pool, Ludo or Carrom (every game gets the same billing),
/// with the wallet, daily bonus, rank and the shortcuts around it.
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
      final unread = await PushService.pollInbox(api);
      if (mounted) ref.read(notificationUnreadProvider.notifier).set(unread);
    } on Object {
      // offline
    }
  }

  /// Anything opened from here may change coins or leave a match running.
  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _reload();
  }

  Future<void> _rejoin(Map<String, dynamic> match) async {
    final navigator = Navigator.of(context);
    final wsUrl = await ref.read(sessionProvider.notifier).realtimeUrl();
    await openOnlineMatch(
      navigator,
      ref.read(apiProvider)!,
      gameId: match['gameId'] as int,
      roomId: match['roomId'] as int,
      gameKey: match['game'] as String,
      seat: match['seat'] as int,
      shotSeconds: match['shotSeconds'] as int,
      players: (match['players'] as List).cast<Map<String, dynamic>>(),
      wsUrl: wsUrl,
      bet: match['bet'] as Map<String, dynamic>?,
      replace: false,
    );
    if (mounted) _reload();
  }

  /// A dialog with one big button per choice.
  Future<void> _chooser({required String title, required String body, required List<(String, Color, VoidCallback)> choices}) =>
      showDuelDialog<void>(
        context,
        barrierColor: const Color(0xB3000000),
        builder: (dialog) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(22),
            decoration: duelPanel(rim: DuelColors.rimLight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppText.label(18, weight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(body, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.4, color: DuelColors.dim)),
                const SizedBox(height: 14),
                for (final (label, color, go) in choices)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DuelButton(
                      label: label,
                      width: 320,
                      height: 44,
                      fontSize: 16,
                      color: color,
                      onPressed: () {
                        Navigator.of(dialog).pop();
                        go();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  static const _poolColor = DuelColors.green;
  static const _ludoColor = Color(0xFFE8721C);
  static const _carromColor = Color(0xFFD9A34A);

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

  void _friends() {
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
    await showDuelDialog<void>(
      context,
      barrierColor: const Color(0xB3000000),
      builder: (_) => _DailyBonusDialog(daily: daily),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final lobby = ref.watch(lobbyProvider);
    final session = ref.watch(sessionProvider);
    final active = ref.watch(activeMatchProvider).valueOrNull;
    final challengePending = ref.watch(challengePendingCountProvider) > 0;
    final data = lobby.valueOrNull;
    return DuelCanvas(
      child: Stack(
        children: [
          const Positioned(left: 0, right: 0, top: 6, child: DuelTopBar()),
          Positioned(
            left: 200,
            width: 978,
            top: 124,
            child: DuelTitle(t.chooseTable, size: 50, sub: t.pickGameDuel),
          ),
          // Left: daily bonus, rank, missions.
          Positioned(
            left: 42,
            top: 132,
            child: _SideTile(
              height: 158,
              title: t.dailyBonus,
              titleColor: DuelColors.gold,
              onTap: data == null ? null : () => _daily(data.daily),
              badge: data?.daily.available ?? false,
              attention: data?.daily.available ?? false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.redeem_rounded, color: Color(0xFFFF9A2E), size: 70),
                  const SizedBox(height: 4),
                  data == null
                      ? const SizedBox(height: 18)
                      : data.daily.available
                          ? Text(t.claimNow, style: AppText.label(14, color: DuelColors.green, weight: FontWeight.w900))
                          : _Countdown(from: data.fetchedAt, seconds: data.daily.secondsToNext),
                ],
              ),
            ),
          ),
          Positioned(
            left: 42,
            top: 302,
            child: _SideTile(
              height: 206,
              title: t.rank,
              onTap: () => _open(const LeaderboardScreen()),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 96, height: 104, child: CustomPaint(painter: _RankBadgePainter(session.rankTier, session.rankName))),
                  const SizedBox(height: 8),
                  Text(session.rankName, style: AppText.label(15, color: DuelColors.gold, weight: FontWeight.w900)),
                ],
              ),
            ),
          ),
          Positioned(
            left: 42,
            top: 520,
            child: _SideTile(
              height: 158,
              title: '',
              onTap: () => showDuelMessage(context,
                  title: t.missions,
                  body: t.missionsBody,
                  icon: Icons.flag_rounded),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flag_rounded, color: Color(0xFF8EDB5A), size: 74),
                  const SizedBox(height: 6),
                  Text(t.mission, style: AppText.label(15, color: DuelColors.dim, weight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          // The three games.
          Positioned(
            left: 236,
            top: 234,
            child: GameCard(
              width: _cardW,
              color: DuelColors.green,
              title: t.poolTitle,
              sub: t.poolSub,
              art: const BilliardArt(),
              onPlay: () => _open(const PoolHubScreen()),
            ),
          ),
          Positioned(
            left: 236 + _cardW + _cardGap,
            top: 234,
            child: GameCard(
              width: _cardW,
              color: const Color(0xFFE8721C),
              title: t.ludoTitle,
              sub: t.ludoSub,
              art: const _LudoArt(),
              onPlay: () => _open(const LudoLobbyScreen()),
            ),
          ),
          Positioned(
            left: 236 + 2 * (_cardW + _cardGap),
            top: 234,
            child: GameCard(
              width: _cardW,
              color: const Color(0xFFD9A34A),
              title: t.carromTitle,
              sub: t.carromSub,
              art: const _CarromArt(),
              onPlay: () => _open(const CarromLobbyScreen()),
            ),
          ),
          // Right: what else there is to do.
          Positioned(
            left: 1178,
            top: 132,
            child: HomeBanner(
              title: t.howToPlayTitle,
              sub: t.howToPlaySub,
              colors: const [Color(0xFF2A1A4A), Color(0xFF0E0820)],
              rim: const Color(0xFF7B5BFF),
              titleColor: const Color(0xFFC9B8FF),
              icon: const Icon(Icons.menu_book_rounded, color: Color(0xFFC9B8FF), size: 84),
              onTap: () => _open(const HowToPlayScreen()),
            ),
          ),
          Positioned(
            left: 1178,
            top: 318,
            child: HomeBanner(
              title: t.practiceFreeTitle,
              sub: t.practiceFreeSub,
              colors: const [Color(0xFF0E3A22), Color(0xFF07140D)],
              rim: const Color(0xFF2E8B57),
              titleColor: const Color(0xFF9BF2B5),
              icon: const Icon(Icons.smart_toy_rounded, color: Color(0xFF9BF2B5), size: 84),
              onTap: _practice,
            ),
          ),
          Positioned(
            left: 1178,
            top: 518,
            child: HomeBanner(
              title: t.friendsBannerTitle,
              sub: t.friendsBannerSub,
              colors: const [Color(0xFF0B2A66), Color(0xFF070E24)],
              rim: const Color(0xFF2F6BFF),
              titleColor: const Color(0xFF9CC2FF),
              icon: const Icon(Icons.groups_rounded, color: Color(0xFF9CC2FF), size: 88),
              onTap: _friends,
            ),
          ),
          // Bottom row.
          Positioned(
            left: 42,
            top: 722,
            child: active != null
                ? HighlightPulse(
                    highlightColor: DuelColors.gold,
                    onTap: () {
                      AudioService.tap();
                      _rejoin(active);
                    },
                    child: Container(
                      width: 430,
                      height: 132,
                      decoration: duelPanel(radius: 20, rim: DuelColors.gold, glow: true),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          PulseBadge(
                            minScale: 0.94,
                            maxScale: 1.12,
                            child: const Icon(Icons.play_circle_fill_rounded, color: DuelColors.gold, size: 58),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.matchInProgress, style: AppText.label(14, color: DuelColors.dim)),
                              const SizedBox(height: 4),
                              Text(t.rejoinMatch, style: AppText.label(22, color: DuelColors.gold, weight: FontWeight.w900)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Container(
                        width: 248,
                        height: 132,
                        decoration: duelPanel(radius: 20, rim: const Color(0xFF232A4A), fill: const Color(0x99C7CBDA).withValues(alpha: 0.16)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.public_rounded, color: DuelColors.green, size: 28),
                            const SizedBox(width: 10),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.online, style: AppText.label(12, color: DuelColors.dim)),
                                const SizedBox(height: 2),
                                Text(
                                  lobby.hasError && data == null ? t.offline : (data == null ? '...' : formatCoins(data.online)),
                                  style: AppText.label(26, color: DuelColors.silver, weight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 19),
                      NavTile(
                        icon: Icons.card_giftcard_rounded,
                        label: t.refer,
                        onTap: () => _open(const ReferScreen()),
                      ),
                    ],
                  ),
          ),
          Positioned(
            left: 498,
            top: 722,
            child: Row(
              children: [
                NavTile(icon: Icons.home_rounded, label: t.navHome, active: true, onTap: _reload),
                const SizedBox(width: 19),
                NavTile(icon: Icons.storefront_rounded, label: t.navShop, onTap: () => _open(const ShopScreen())),
                const SizedBox(width: 19),
                NavTile(icon: Icons.leaderboard_rounded, label: t.navRankings, onTap: () => _open(const LeaderboardScreen())),
                const SizedBox(width: 19),
                NavTile(icon: Icons.backpack_rounded, label: t.navItems, onTap: () => _open(const ItemsScreen())),
                const SizedBox(width: 19),
                NavTile(icon: Icons.groups_rounded, label: t.navFriends, onTap: _friends),
                const SizedBox(width: 19),
                NavTile(
                  icon: Icons.sports_kabaddi_rounded,
                  label: t.navChallenge,
                  badge: challengePending,
                  onTap: () => _open(const ChallengeScreen()),
                ),
                const SizedBox(width: 19),
                NavTile(icon: Icons.query_stats_rounded, label: t.navData, onTap: () => _open(const HistoryScreen())),
              ],
            ),
          ),
          if (lobby.hasError && data == null)
            Positioned(
              left: 200,
              width: 978,
              top: 690,
              child: Center(
                child: Text(
                  lobby.error is ApiException ? ref.read(stringsProvider).maybeApi((lobby.error as ApiException).message) : t.offlineServer,
                  style: AppText.label(14, color: DuelColors.red),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SideTile extends StatelessWidget {
  const _SideTile({
    required this.height,
    required this.title,
    required this.child,
    this.onTap,
    this.titleColor = DuelColors.silver,
    this.badge = false,
    this.attention = false,
  });

  final double height;
  final String title;
  final Widget child;
  final VoidCallback? onTap;
  final Color titleColor;
  final bool badge;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title.isNotEmpty) ...[
          Text(title, style: AppText.label(14, color: titleColor, weight: FontWeight.w900)),
          const SizedBox(height: 6),
        ],
        IdleAttentionScale(active: attention, child: child),
      ],
    );
    return PressScale(
      onTap: onTap,
      enabled: onTap != null,
      scale: 0.96,
      child: Container(
        width: 158,
        height: height,
        decoration: duelPanel(radius: 20, rim: const Color(0xFF232A4A), fill: const Color(0xCC0B0E1C)),
        child: Stack(
          children: [
            Center(child: body),
            const DuelGloss(radius: 20, strength: 0.1),
            if (badge)
              Positioned(
                right: 12,
                top: 12,
                child: PulseBadge(child: CircleAvatar(radius: 9, backgroundColor: DuelColors.red)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ticks down to the next daily bonus.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.from, required this.seconds});

  final DateTime from;
  final int seconds;

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
        const Icon(Icons.timer_outlined, color: DuelColors.dim, size: 18),
        const SizedBox(width: 4),
        Text('${two(left ~/ 3600)}:${two(left % 3600 ~/ 60)}:${two(left % 60)}', style: AppText.label(14, color: DuelColors.dim)),
      ],
    );
  }
}

/// Four game cards fill the space between the left tiles and the right banners.
const _cardW = 296.0, _cardGap = 20.0;

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

/// A mini carrom board for the game card.
class _CarromArt extends StatelessWidget {
  const _CarromArt();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _CarromArtPainter());
}

class _CarromArtPainter extends CustomPainter {
  const _CarromArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF4A1414), Color(0xFF1A0808)]).createShader(rect));
    final b = size.shortestSide * 0.82;
    final left = (size.width - b) / 2, top = (size.height - b) / 2 + size.height * 0.04;
    final board = Rect.fromLTWH(left, top, b, b);
    canvas.drawRRect(RRect.fromRectAndRadius(board, Radius.circular(b * 0.05)), Paint()..color = const Color(0xFF5B3A2E));
    final f = b * 0.06;
    final field = board.deflate(f);
    canvas.drawRect(field, Paint()..color = const Color(0xFFE8BF8E));
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = const Color(0xFFA2613B);
    final u = field.width;
    for (final s in const [0.16, 0.84]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(field.left + u * 0.19, field.top + u * (s - 0.03), field.left + u * 0.81, field.top + u * (s + 0.03)), Radius.circular(u * 0.03)), line);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(field.left + u * (s - 0.03), field.top + u * 0.19, field.left + u * (s + 0.03), field.top + u * 0.81), Radius.circular(u * 0.03)), line);
    }
    canvas.drawCircle(field.center, u * 0.17, line);
    for (final c in [field.topLeft, field.topRight, field.bottomLeft, field.bottomRight]) {
      canvas.drawCircle(c + Offset(c.dx < field.center.dx ? u * 0.04 : -u * 0.04, c.dy < field.center.dy ? u * 0.04 : -u * 0.04), u * 0.05, Paint()..color = const Color(0xFF111111));
    }
    // A few pieces round the queen.
    final r = u * 0.03;
    canvas.drawCircle(field.center, r, Paint()..color = const Color(0xFFE53935));
    for (var k = 0; k < 6; k++) {
      final a = -3.14159 / 2 + k * 3.14159 / 3;
      final p = field.center + Offset(2.1 * r * cos(a), 2.1 * r * sin(a));
      canvas.drawCircle(p, r, Paint()..color = k.isEven ? const Color(0xFF2C2F33) : const Color(0xFFEFE3D2));
    }
    // The striker on the near base line.
    canvas.drawCircle(Offset(field.center.dx, field.top + u * 0.84), r * 1.35, Paint()..color = const Color(0xFFE53935));
  }

  @override
  bool shouldRepaint(_CarromArtPainter old) => false;
}

/// A mini Ludo board for the game card.
class _LudoArt extends StatelessWidget {
  const _LudoArt();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _LudoArtPainter());
}

class _LudoArtPainter extends CustomPainter {
  const _LudoArtPainter();

  static const _cols = [Color(0xFFE0333B), Color(0xFF2FA84F), Color(0xFFE8B91C), Color(0xFF2F6BDC)];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A2606), Color(0xFF1A1206)]).createShader(rect));
    // A board centred in the art area.
    final b = size.shortestSide * 0.82;
    final left = (size.width - b) / 2, top = (size.height - b) / 2 + size.height * 0.04;
    final s = b / 15;
    Rect cell(double c, double r, double w) => Rect.fromLTWH(left + c * s, top + r * s, w * s, w * s);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, b, b), Radius.circular(s)), Paint()..color = const Color(0xFFEFF2F8));
    // Four corner yards.
    final yards = [[0.0, 9.0], [0.0, 0.0], [9.0, 0.0], [9.0, 9.0]];
    for (var i = 0; i < 4; i++) {
      canvas.drawRRect(RRect.fromRectAndRadius(cell(yards[i][0], yards[i][1], 6), Radius.circular(s)), Paint()..color = _cols[i]);
      canvas.drawRRect(RRect.fromRectAndRadius(cell(yards[i][0] + 1, yards[i][1] + 1, 4), Radius.circular(s * 0.6)), Paint()..color = Colors.white);
      // a token dot
      canvas.drawCircle(Offset(left + (yards[i][0] + 3) * s, top + (yards[i][1] + 3) * s), s * 1.1, Paint()..color = _cols[i]);
      canvas.drawCircle(Offset(left + (yards[i][0] + 3) * s, top + (yards[i][1] + 3) * s), s * 1.1, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white);
    }
    // Centre.
    final mid = Offset(left + 7.5 * s, top + 7.5 * s);
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromCenter(center: mid, width: 3 * s, height: 3 * s), Paint()..color = const Color(0xFFDDE3EE));
    }
    final c = [Offset(left + 6 * s, top + 6 * s), Offset(left + 9 * s, top + 6 * s), Offset(left + 9 * s, top + 9 * s), Offset(left + 6 * s, top + 9 * s)];
    void tri(Offset a, Offset b2, Color col) => canvas.drawPath(Path()..moveTo(mid.dx, mid.dy)..lineTo(a.dx, a.dy)..lineTo(b2.dx, b2.dy)..close(), Paint()..color = col);
    tri(c[0], c[1], _cols[2]);
    tri(c[1], c[2], _cols[3]);
    tri(c[2], c[3], _cols[0]);
    tri(c[3], c[0], _cols[1]);
  }

  @override
  bool shouldRepaint(_LudoArtPainter old) => false;
}

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

/// Hexagonal rank medal with the division number.
class _RankBadgePainter extends CustomPainter {
  _RankBadgePainter(this.tier, this.name);

  final int tier;
  final String name;

  static const _metals = [
    [Color(0xFFE39A5B), Color(0xFF8A4A1E)], // bronze
    [Color(0xFFE6EAF2), Color(0xFF7D8696)], // silver
    [Color(0xFFFFD75A), Color(0xFFC77A0A)], // gold
    [Color(0xFF9FF3F0), Color(0xFF2C8C96)], // platinum
    [Color(0xFFB9A2FF), Color(0xFF4B2FC0)], // diamond
  ];

  Path _hex(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = -pi / 2 + i * pi / 3;
      final v = c + Offset(cos(a), sin(a)) * r;
      i == 0 ? p.moveTo(v.dx, v.dy) : p.lineTo(v.dx, v.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.5;
    final metal = _metals[tier.clamp(0, _metals.length - 1)];
    final bounds = Rect.fromCircle(center: c, radius: r);
    canvas.drawPath(_hex(c + const Offset(0, 4), r), Paint()..color = const Color(0x99000000));
    canvas.drawPath(_hex(c, r),
        Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: metal).createShader(bounds));
    canvas.drawPath(_hex(c, r * 0.76), Paint()..color = Color.lerp(metal[1], Colors.black, 0.35)!);
    canvas.drawPath(
        _hex(c, r * 0.76),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.5));
    final division = name.split(' ').last.length; // I, II, III
    final tp = TextPainter(
      text: TextSpan(text: '$division', style: AppText.label(r * 0.8, color: metal[0], weight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    // Ribbon tail.
    final ribbon = Path()
      ..moveTo(c.dx - r * 0.42, c.dy + r * 0.8)
      ..lineTo(c.dx + r * 0.42, c.dy + r * 0.8)
      ..lineTo(c.dx + r * 0.3, c.dy + r * 1.05)
      ..lineTo(c.dx, c.dy + r * 0.92)
      ..lineTo(c.dx - r * 0.3, c.dy + r * 1.05)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = const Color(0xFFD13A2A));
  }

  @override
  bool shouldRepaint(_RankBadgePainter old) => old.tier != tier || old.name != name;
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

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final d = widget.daily;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(20),
        decoration: duelPanel(rim: DuelColors.gold, glow: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.dailyBonus, style: AppText.label(22, color: DuelColors.gold, weight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(t.dailyBonusGrow, style: AppText.label(10, color: DuelColors.dim)),
            const SizedBox(height: 14),
            PopCelebration(
              trigger: _celebrate,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < d.rewards.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _DayTile(
                        day: i + 1,
                        coins: d.rewards[i].coins,
                        gems: d.rewards[i].gems,
                        state: i < d.day || (i == d.day && !_available) ? 2 : (i == d.day ? 1 : 0),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_note!, style: AppText.label(16, color: DuelColors.green, weight: FontWeight.w900)),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_available)
                  DuelButton(label: _busy ? '...' : t.claim, width: 190, height: 44, fontSize: 18, onPressed: _busy ? null : _claim),
                if (_available) const SizedBox(width: 12),
                DuelButton(
                  label: t.close,
                  width: 150,
                  height: 44,
                  fontSize: 16,
                  color: DuelColors.rimLight,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTile extends ConsumerWidget {
  const _DayTile({required this.day, required this.coins, required this.gems, required this.state});

  final int day;
  final int coins;
  final int gems;

  /// 0 later, 1 today, 2 collected.
  final int state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final rim = state == 1 ? DuelColors.gold : (state == 2 ? DuelColors.green : DuelColors.rim);
    return Opacity(
      opacity: state == 0 ? 0.7 : 1,
      child: Container(
        width: 78,
        height: 104,
        decoration: duelPanel(radius: 12, rim: rim, glow: state == 1, fill: const Color(0xFF0B0E1C)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(t.dayLabel(day), style: AppText.label(9, color: DuelColors.dim)),
            const SizedBox(height: 4),
            state == 2 ? const Icon(Icons.check_circle_rounded, color: DuelColors.green, size: 30) : const PikoCoinIcon(size: 30),
            const SizedBox(height: 4),
            Text(formatCoins(coins), style: AppText.label(13, color: DuelColors.silver, weight: FontWeight.w900)),
            if (gems > 0) Text(t.gemsBonus(gems), style: AppText.label(8, color: const Color(0xFFB79CFF))),
          ],
        ),
      ),
    );
  }
}
