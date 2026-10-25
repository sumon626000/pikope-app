import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../online/online_screens.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import 'lobby_data.dart';
import 'matchmaking_screen.dart';
import '../../l10n/strings.dart';

/// Opponent for a 1v1 challenge from the bet-level (stake) screen.
class ChallengeTarget {
  const ChallengeTarget({required this.userId, required this.name});

  final int userId;
  final String name;
}

BetLevel betLevelFromRoom(WidgetRef ref, DuelMode mode, Map<String, dynamic> room) {
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
    final bet = betLevelFromRoom(ref, mode, room);
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

/// Waits until the opponent accepts the challenge invite.
class ChallengeWaitScreen extends ConsumerStatefulWidget {
  const ChallengeWaitScreen({super.key, required this.challengeId, required this.opponentName});

  final int challengeId;
  final String opponentName;

  @override
  ConsumerState<ChallengeWaitScreen> createState() => _ChallengeWaitScreenState();
}

class _ChallengeWaitScreenState extends ConsumerState<ChallengeWaitScreen> {
  Timer? _poll;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _cancel() async {
    _poll?.cancel();
    try {
      await ref.read(sessionProvider.notifier).cancelChallenge(widget.challengeId);
    } on ApiException {
      // ignore
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _check() async {
    try {
      final inbox = await ref.read(sessionProvider.notifier).challengeInbox();
      final outgoing = (inbox['outgoing'] as List).cast<Map<String, dynamic>>();
      final mine = outgoing.where((c) => c['id'] == widget.challengeId).toList();
      if (mine.isEmpty) {
        _poll?.cancel();
        if (mounted) setState(() => _error = ref.read(stringsProvider).notAcceptedTryLater);
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

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final name = widget.opponentName.toUpperCase();
    return DuelCanvas(
      child: Stack(
        children: [
          const Positioned(left: 0, right: 0, top: 6, child: DuelTopBar()),
          Center(
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(28),
              decoration: duelPanel(rim: DuelColors.gold),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.waitingShort, style: AppText.label(22, color: DuelColors.gold, weight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  Text(t.waitingAccept(name), textAlign: TextAlign.center, style: AppText.label(15, color: DuelColors.dim)),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: DuelColors.gold),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!.toUpperCase(), textAlign: TextAlign.center, style: AppText.label(13, color: DuelColors.red)),
                  ],
                  const SizedBox(height: 24),
                  DuelButton(label: t.cancel, width: 180, height: 48, color: DuelColors.rimLight, onPressed: _cancel),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
