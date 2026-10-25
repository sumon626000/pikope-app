import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../online/online_screens.dart';
import '../online/session.dart';
import 'challenge_inbox_pulse.dart';
import 'challenge_incoming_banner.dart';
import 'duel_chrome.dart';
import 'lobby_data.dart';
import 'matchmaking_screen.dart';
import '../../l10n/strings.dart';

BetLevel _betFromRoom(WidgetRef ref, DuelMode mode, Map<String, dynamic> room) {
  final levelIdx = room['level'] as int?;
  final lobby = ref.read(lobbyProvider).valueOrNull;
  if (levelIdx != null && lobby != null) {
    for (final b in lobby.levelsFor(mode)) {
      if (b.level == levelIdx) return b;
    }
  }
  final stake = (room['stake'] as int?) ?? 0;
  final fee = (room['fee'] as int?) ?? 0;
  return BetLevel(
    level: levelIdx ?? 0,
    name: stake > 0 ? '$stake' : '',
    stake: stake,
    fee: fee,
    buyIn: stake + fee,
    players: mode.seats,
    prize: room['prize'] as int?,
  );
}

/// After accept: join matchmaking or go straight into a live match.
Future<void> openChallengeRoom(BuildContext context, WidgetRef ref, Map<String, dynamic> room, {bool replace = false}) async {
  final gameKey = room['game'] as String;
  final mode = duelModeFromApi(gameKey);
  if (mode == null) return;
  final playing = room['status'] == 'playing' && room['gameId'] != null;
  if (!playing) {
    final bet = _betFromRoom(ref, mode, room);
    final route = MaterialPageRoute<void>(builder: (_) => MatchmakingScreen(mode: mode, level: bet, initialRoom: room));
    if (replace) {
      await Navigator.of(context).pushReplacement(route);
    } else {
      await Navigator.of(context).push(route);
    }
    return;
  }
  final navigator = Navigator.of(context);
  final wsUrl = await ref.read(sessionProvider.notifier).realtimeUrl();
  final myId = ref.read(sessionProvider).userId;
  final players = (room['players'] as List).cast<Map<String, dynamic>>();
  final me = players.firstWhere((p) => p['id'] == myId, orElse: () => players.first);
  await openOnlineMatch(
    navigator,
    ref.read(apiProvider)!,
    gameId: room['gameId'] as int,
    roomId: room['id'] as int,
    gameKey: gameKey,
    seat: me['seat'] as int,
    shotSeconds: room['shotSeconds'] as int,
    players: players,
    wsUrl: wsUrl,
    bet: {'mode': gameKey, 'stake': room['stake'], 'prize': room['prize'], 'multiplier': room['multiplier']},
    replace: replace,
  );
}

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
    if (ref.read(lobbyProvider).valueOrNull == null) {
      try {
        await ref.read(lobbyProvider.notifier).refresh();
      } catch (_) {}
    }
    if (!mounted) return;
    await showDuelDialog<void>(
      context,
      barrierColor: const Color(0xCC000000),
      builder: (dialog) => _SendDialog(player: player),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final players = _players;
    return DuelPage(
      title: t.challengePageTitle,
      sub: t.challengePageSub,
      child: players == null
          ? Center(
              child: _error != null
                  ? Text(t.offlineServer, style: AppText.label(18, color: DuelColors.red))
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

enum _SendChallengeStep { gameFamily, poolMode, stake }

class _SendDialog extends ConsumerStatefulWidget {
  const _SendDialog({required this.player});

  final Map<String, dynamic> player;

  @override
  ConsumerState<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends ConsumerState<_SendDialog> {
  _SendChallengeStep _step = _SendChallengeStep.gameFamily;
  String? _game;
  int? _level;
  bool _busy = false;
  String? _error;
  int? _sentId;
  Timer? _poll;

  static const _poolGames = ['eight', 'nine', 'ten', 'billiard'];

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  List<BetLevel> _paidLevelsFor(String game) {
    final mode = duelModeFromApi(game);
    if (mode == null) return const [];
    final all = ref.read(lobbyProvider).valueOrNull?.levelsFor(mode) ?? const [];
    return all.where((l) => l.stake > 0).toList();
  }

  void _pickDefaultLevel() {
    final game = _game;
    if (game == null) {
      _level = null;
      return;
    }
    final levels = _paidLevelsFor(game);
    _level = levels.isNotEmpty ? levels.first.level : null;
  }

  void _goBack() {
    AudioService.tap();
    setState(() {
      _error = null;
      if (_step == _SendChallengeStep.stake) {
        if (_game != null && _poolGames.contains(_game)) {
          _step = _SendChallengeStep.poolMode;
        } else {
          _step = _SendChallengeStep.gameFamily;
          _game = null;
          _level = null;
        }
      } else if (_step == _SendChallengeStep.poolMode) {
        _step = _SendChallengeStep.gameFamily;
        _game = null;
        _level = null;
      }
    });
  }

  Future<void> _send() async {
    final game = _game;
    final level = _level;
    if (game == null || level == null) {
      setState(() => _error = ref.read(stringsProvider).challengePickStake);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ch = await ref.read(sessionProvider.notifier).sendChallenge(widget.player['id'] as int, game, level);
      requestChallengeInboxPoll();
      _sentId = ch['id'] as int;
      // Wait for acceptance.
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _checkAccepted());
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = ref.read(stringsProvider).maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkAccepted() async {
    try {
      final inbox = await ref.read(sessionProvider.notifier).challengeInbox();
      final outgoing = (inbox['outgoing'] as List).cast<Map<String, dynamic>>();
      final mine = outgoing.where((c) => c['id'] == _sentId).toList();
      if (mine.isEmpty) {
        // Declined, expired or cancelled: the server no longer lists it.
        _poll?.cancel();
        if (mounted) {
          setState(() {
            _sentId = null;
            _error = ref.read(stringsProvider).notAcceptedTryLater;
          });
        }
        return;
      }
      final c = mine.first;
      if (c['status'] == 'accepted' && c['roomId'] != null) {
        _poll?.cancel();
        final room = await ref.read(apiProvider)!.get('/rooms/${c['roomId']}');
        if (!mounted) return;
        Navigator.of(context).pop();
        await openChallengeRoom(context, ref, room);
      }
    } on ApiException {
      // keep waiting
    }
  }

  Future<void> _cancel() async {
    _poll?.cancel();
    if (_sentId != null) {
      try {
        await ref.read(sessionProvider.notifier).cancelChallenge(_sentId!);
      } on ApiException {
        // ignore
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final waiting = _sentId != null;
    final name = (widget.player['name'] as String).toUpperCase();
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(22),
        decoration: duelPanel(rim: DuelColors.rimLight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(waiting ? t.waitingShort : t.challengePlayer(widget.player['name'] as String),
                textAlign: TextAlign.center, style: AppText.label(20, weight: FontWeight.w900)),
            const SizedBox(height: 16),
            if (waiting) ...[
              const CircularProgressIndicator(color: DuelColors.gold),
              const SizedBox(height: 14),
              Text(t.waitingAccept(name), textAlign: TextAlign.center, style: AppText.label(14, color: DuelColors.dim)),
              const SizedBox(height: 20),
              DuelButton(label: t.cancel, width: 180, height: 48, color: DuelColors.rimLight, onPressed: _cancel),
            ] else ...[
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.52),
                child: SingleChildScrollView(child: _buildSetupStep(t)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!.toUpperCase(), style: AppText.label(13, color: DuelColors.red)),
              ],
              const SizedBox(height: 16),
              _buildSetupActions(t),
            ],
          ],
        ),
      ),
    );
  }

  String _poolLabel(AppStrings t, String game) => switch (game) {
        'eight' => t.eightBallTitle,
        'nine' => t.nineBallTitle,
        'ten' => t.tenBallTitle,
        _ => t.billiardTitle,
      };

  String _gameTitle(AppStrings t, String game) => switch (game) {
        'ludo2' => t.ludoTitle,
        'carrom' => t.carromTitle,
        _ => _poolLabel(t, game),
      };

  Widget _buildSetupStep(AppStrings t) {
    return switch (_step) {
      _SendChallengeStep.gameFamily => _buildGameFamilyStep(t),
      _SendChallengeStep.poolMode => _buildPoolModeStep(t),
      _SendChallengeStep.stake => _buildStakeStep(t),
    };
  }

  Widget _buildGameFamilyStep(AppStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.challengePickGame, textAlign: TextAlign.center, style: AppText.label(13, color: DuelColors.dim)),
        const SizedBox(height: 12),
        _familyTile(t.billiardTitle, DuelColors.green, () {
          setState(() {
            _step = _SendChallengeStep.poolMode;
            _game = null;
            _level = null;
            _error = null;
          });
        }),
        const SizedBox(height: 10),
        _familyTile(t.ludoTitle, const Color(0xFFE8721C), () {
          setState(() {
            _game = 'ludo2';
            _step = _SendChallengeStep.stake;
            _pickDefaultLevel();
            _error = null;
          });
        }),
        const SizedBox(height: 10),
        _familyTile(t.carromTitle, const Color(0xFFD9A34A), () {
          setState(() {
            _game = 'carrom';
            _step = _SendChallengeStep.stake;
            _pickDefaultLevel();
            _error = null;
          });
        }),
      ],
    );
  }

  Widget _familyTile(String label, Color accent, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: duelPanel(radius: 14, rim: accent, fill: const Color(0xCC0B0E1C)),
        child: Text(label, style: AppText.label(20, color: accent, weight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildPoolModeStep(AppStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.challengePickGame, textAlign: TextAlign.center, style: AppText.label(13, color: DuelColors.dim)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            for (final g in _poolGames)
              _modeTile(_poolLabel(t, g), _game == g, () {
                setState(() {
                  _game = g;
                  _step = _SendChallengeStep.stake;
                  _pickDefaultLevel();
                  _error = null;
                });
              }),
          ],
        ),
      ],
    );
  }

  Widget _modeTile(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: Container(
        alignment: Alignment.center,
        decoration: duelPanel(radius: 12, rim: on ? DuelColors.green : DuelColors.rim, glow: on, fill: on ? const Color(0xE60C2414) : const Color(0xCC0B0E1C)),
        child: Text(label, textAlign: TextAlign.center, style: AppText.label(16, color: on ? DuelColors.green : DuelColors.silver, weight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildStakeStep(AppStrings t) {
    final game = _game;
    final levels = game == null ? const <BetLevel>[] : _paidLevelsFor(game);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (game != null)
          Text(_gameTitle(t, game), textAlign: TextAlign.center, style: AppText.label(18, color: DuelColors.gold, weight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(t.stake, textAlign: TextAlign.center, style: AppText.label(13, color: DuelColors.dim)),
        const SizedBox(height: 12),
        if (levels.isEmpty)
          Text(t.offlineServer, textAlign: TextAlign.center, style: AppText.label(14, color: DuelColors.red))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.1,
            ),
            itemCount: levels.length,
            itemBuilder: (context, i) {
              final l = levels[i];
              final on = _level == l.level;
              return GestureDetector(
                onTap: () {
                  AudioService.tap();
                  setState(() => _level = l.level);
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: duelPanel(radius: 10, rim: on ? DuelColors.gold : DuelColors.rim, glow: on),
                  child: Text(l.displayName, style: AppText.label(15, color: on ? DuelColors.gold : DuelColors.silver, weight: FontWeight.w800)),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSetupActions(AppStrings t) {
    final onStake = _step == _SendChallengeStep.stake;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_step != _SendChallengeStep.gameFamily)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: DuelButton(label: t.back, width: 120, height: 50, color: DuelColors.rimLight, onPressed: _goBack),
          ),
        if (onStake) ...[
          DuelButton(label: _busy ? '...' : t.send, width: 180, height: 50, color: DuelColors.gold, onPressed: _busy ? null : _send),
          const SizedBox(width: 10),
        ],
        DuelButton(label: t.close, width: onStake ? 130 : 180, height: 50, color: DuelColors.rimLight, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
