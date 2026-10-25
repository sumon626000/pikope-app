import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../online/session.dart';
import 'challenge_incoming_banner.dart';
import 'duel_chrome.dart';
import 'lobby_data.dart';
import 'bet_level_screen.dart';
import 'challenge_flow.dart';
import 'challenge_game_mode_art.dart';
import '../../l10n/strings.dart';

export 'challenge_flow.dart' show openChallengeRoom, ChallengeTarget;

/// Top banner (not full-screen) for an incoming challenge.
Future<void> showIncomingChallenge(BuildContext context, WidgetRef ref, Map<String, dynamic> ch) async {
  await showIncomingChallengeBanner(context, ref, ch);
}

/// See who is online and challenge them to a 1v1.
class ChallengeScreen extends ConsumerStatefulWidget {
  const ChallengeScreen({super.key});

  @override
  ConsumerState<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends ConsumerState<ChallengeScreen> {
  List<Map<String, dynamic>>? _players;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final notifier = ref.read(sessionProvider.notifier);
    try {
      final players = await notifier.onlinePlayers();
      if (mounted) {
        setState(() {
          _players = players;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _challenge(Map<String, dynamic> player) async {
    final t = ref.read(stringsProvider);
    if (ref.read(lobbyProvider).valueOrNull == null) {
      try {
        await ref.read(lobbyProvider.notifier).refreshRequired();
      } on ApiException catch (e) {
        if (mounted) {
          showDuelMessage(context, title: t.challengePageTitle, body: t.maybeApi(e.message));
        }
        return;
      }
    }
    if (!mounted) return;
    final target = ChallengeTarget(userId: player['id'] as int, name: player['name'] as String);
    var gameKey = player['game'] as String? ?? '';
    var mode = duelModeFromApi(gameKey);
    if (mode == null) {
      gameKey = await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => ChallengeGamePickScreen(player: player)),
          ) ??
          '';
      mode = duelModeFromApi(gameKey);
    }
    if (!mounted || mode == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => BetLevelScreen(mode: mode!, challengeTarget: target)),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(lobbyProvider);
    final t = ref.watch(stringsProvider);
    final players = _players;
    return DuelPage(
      title: t.challengePageTitle,
      sub: t.challengePageSub,
      child: players == null
          ? Center(
              child: _error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.maybeApi(_error!), textAlign: TextAlign.center, style: AppText.label(16, color: DuelColors.red)),
                        const SizedBox(height: 12),
                        DuelButton(label: t.retry, width: 140, height: 44, onPressed: _refresh),
                      ],
                    )
                  : const CircularProgressIndicator(color: DuelColors.silver))
          : players.isEmpty
              ? Center(child: Text(t.noPlayersOnline, style: AppText.label(20, color: DuelColors.dim)))
              : GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 4.3,
                  padding: const EdgeInsets.only(bottom: 10),
                  children: [
                    for (final p in players) _PlayerRow(player: p, onChallenge: () => _challenge(p)),
                  ],
                ),
    );
  }
}

String _shortGame(String key) {
  if (key.startsWith('ludo')) return 'Ludo';
  if (key == 'carrom') return 'Carrom';
  if (key == 'poker') return 'Poker';
  if (key == 'eight') return '8-Ball';
  if (key == 'nine') return '9-Ball';
  if (key == 'ten') return '10-Ball';
  if (key.isEmpty) return '';
  return 'Pool';
}

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({required this.player, required this.onChallenge});

  final Map<String, dynamic> player;
  final VoidCallback onChallenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final busy = player['busy'] as bool? ?? false;
    final accepts = player['acceptsChallenges'] as bool? ?? true;
    final gameKey = player['game'] as String? ?? '';
    final activity = t.playerActivityLabel(_shortGame(gameKey), busy);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: duelPanel(radius: 14),
      child: Row(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: AvatarImage(player['avatar'] as String, size: 58)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text((player['name'] as String).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(18, weight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('LV ${player['level']}  -  ${player['rank']}  -  ${formatCoins(player['coins'] as int)}', style: AppText.label(12, color: DuelColors.dim)),
                Text(activity, style: AppText.label(11, color: busy ? DuelColors.red : DuelColors.green, weight: FontWeight.w700)),
              ],
            ),
          ),
          if (busy)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF2A2F4A), borderRadius: BorderRadius.circular(10)),
              child: Text(t.inMatch, style: AppText.label(13, color: DuelColors.dim, weight: FontWeight.w800)),
            )
          else if (!accepts)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF2A2F4A), borderRadius: BorderRadius.circular(10)),
              child: Text(t.challengesOffShort, style: AppText.label(12, color: DuelColors.dim, weight: FontWeight.w800)),
            )
          else
            DuelButton(label: t.challengeBtn, width: 170, height: 46, fontSize: 15, color: DuelColors.gold, onPressed: onChallenge),
        ],
      ),
    );
  }
}

enum _PickGameStep { gameFamily, poolMode, ludoPlayers }

/// Full-screen game picker before the shared bet-level (stake carousel) screen.
class ChallengeGamePickScreen extends ConsumerStatefulWidget {
  const ChallengeGamePickScreen({super.key, required this.player});

  final Map<String, dynamic> player;

  @override
  ConsumerState<ChallengeGamePickScreen> createState() => _ChallengeGamePickScreenState();
}

class _ChallengeGamePickScreenState extends ConsumerState<ChallengeGamePickScreen> {
  _PickGameStep _step = _PickGameStep.gameFamily;
  static const _poolGames = ['eight', 'nine', 'ten', 'billiard'];

  void _finish(String gameKey) {
    AudioService.tap();
    Navigator.of(context).pop(gameKey);
  }

  void _goBack() {
    AudioService.tap();
    setState(() {
      if (_step == _PickGameStep.poolMode || _step == _PickGameStep.ludoPlayers) {
        _step = _PickGameStep.gameFamily;
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  String _poolLabel(AppStrings t, String game) => switch (game) {
        'eight' => t.eightBallTitle,
        'nine' => t.nineBallTitle,
        'ten' => t.tenBallTitle,
        _ => t.billiardTitle,
      };

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return DuelCanvas(
      child: Stack(
        children: [
          const Positioned(left: 0, right: 0, top: 6, child: DuelTopBar()),
          Positioned(
            left: 42,
            top: 722,
            child: NavTile(icon: Icons.reply_rounded, label: t.navBack, onTap: _goBack),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 100, 24, 80),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.challengePlayer(widget.player['name'] as String),
                        textAlign: TextAlign.center, style: AppText.label(22, weight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(t.challengePickGame, style: AppText.label(14, color: DuelColors.dim)),
                    const SizedBox(height: 20),
                    switch (_step) {
                      _PickGameStep.gameFamily => _buildGameFamilyStep(t),
                      _PickGameStep.poolMode => _buildPoolModeStep(t),
                      _PickGameStep.ludoPlayers => _buildLudoPlayersStep(t),
                    },
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameFamilyStep(AppStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.challengePickGame, textAlign: TextAlign.center, style: AppText.label(13, color: DuelColors.dim)),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            final cardH = compact ? 118.0 : 132.0;
            return SizedBox(
              height: cardH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _gameModeCard(
                    label: t.poolTitle,
                    accent: DuelColors.green,
                    icon: Icons.sports_baseball_rounded,
                    art: const ChallengePoolArt(),
                    compact: compact,
                    onTap: () {
                      setState(() => _step = _PickGameStep.poolMode);
                    },
                  ),
                  const SizedBox(width: 8),
                  _gameModeCard(
                    label: t.carromTitle,
                    accent: const Color(0xFFE8A030),
                    icon: Icons.adjust_rounded,
                    art: const ChallengeCarromArt(),
                    compact: compact,
                    onTap: () => _finish('carrom'),
                  ),
                  const SizedBox(width: 8),
                  _gameModeCard(
                    label: t.ludoTitle,
                    accent: const Color(0xFF3B8CFF),
                    icon: Icons.casino_rounded,
                    art: const ChallengeLudoArt(),
                    compact: compact,
                    onTap: () {
                      setState(() => _step = _PickGameStep.ludoPlayers);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _gameModeCard({
    required String label,
    required Color accent,
    required IconData icon,
    required Widget art,
    required bool compact,
    required VoidCallback onTap,
  }) {
    final fontSize = compact ? 11.0 : 13.0;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          AudioService.tap();
          onTap();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.85), width: 1.8),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withValues(alpha: 0.14),
                const Color(0xFF0C101E),
                const Color(0xFF080A14),
              ],
            ),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.28), blurRadius: 10, spreadRadius: -2),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 5 : 7, compact ? 5 : 7, compact ? 5 : 7, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: art,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(4, compact ? 4 : 6, 4, compact ? 6 : 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: compact ? 14 : 16, color: Colors.white.withValues(alpha: 0.9)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppText.label(fontSize, color: Colors.white, weight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoolModeStep(AppStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.poolTitle, textAlign: TextAlign.center, style: AppText.label(18, color: DuelColors.gold, weight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(t.challengePickGame, textAlign: TextAlign.center, style: AppText.label(13, color: DuelColors.dim)),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var i = 0; i < _poolGames.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _poolModeChip(
                  _poolLabel(t, _poolGames[i]),
                  accent: DuelColors.green,
                  selected: false,
                  onTap: () => _finish(_poolGames[i]),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _poolModeChip(String label, {required Color accent, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: Container(
        height: 52,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? accent : DuelColors.rim, width: selected ? 2 : 1),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: selected
                ? [accent.withValues(alpha: 0.22), const Color(0xFF0C101E)]
                : [const Color(0xFF141A2E), const Color(0xFF0A0D18)],
          ),
          boxShadow: selected ? [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 8)] : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.label(12, color: selected ? accent : DuelColors.silver, weight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildLudoPlayersStep(AppStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.ludoTitle, textAlign: TextAlign.center, style: AppText.label(18, color: const Color(0xFF3B8CFF), weight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(t.challengePickGame, textAlign: TextAlign.center, style: AppText.label(13, color: DuelColors.dim)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ludoPlayerChip(
                label: t.ludoPlayers(2),
                selected: false,
                onTap: () => _finish('ludo2'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ludoPlayerChip(
                label: t.ludoPlayers(4),
                selected: false,
                onTap: () => _finish('ludo4'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _ludoPlayerChip({required String label, required bool selected, required VoidCallback onTap}) {
    const accent = Color(0xFF3B8CFF);
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? accent : DuelColors.rim, width: selected ? 2 : 1),
          gradient: LinearGradient(
            colors: selected
                ? [accent.withValues(alpha: 0.2), const Color(0xFF0C101E)]
                : [const Color(0xFF141A2E), const Color(0xFF0A0D18)],
          ),
          boxShadow: selected ? [BoxShadow(color: accent.withValues(alpha: 0.28), blurRadius: 10)] : null,
        ),
        child: Text(label, textAlign: TextAlign.center, style: AppText.label(14, color: selected ? accent : DuelColors.silver, weight: FontWeight.w900)),
      ),
    );
  }
}
