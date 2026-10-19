import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../online/online_screens.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import 'lobby_data.dart';
import '../../l10n/strings.dart';

/// Opens the match for a room returned by a challenge accept / status poll.
Future<void> openChallengeRoom(BuildContext context, WidgetRef ref, Map<String, dynamic> room, {bool replace = false}) async {
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
    gameKey: room['game'] as String,
    seat: me['seat'] as int,
    shotSeconds: room['shotSeconds'] as int,
    players: players,
    wsUrl: wsUrl,
    bet: {'mode': room['game'], 'stake': room['stake'], 'prize': room['prize'], 'multiplier': room['multiplier']},
    replace: replace,
  );
}

/// Shows an incoming challenge; on accept, opens the match.
Future<void> showIncomingChallenge(BuildContext context, WidgetRef ref, Map<String, dynamic> ch) async {
  final from = ch['from'] as Map<String, dynamic>;
  final game = (ch['game'] as String);
  final title = game.startsWith('ludo') ? 'LUDO' : (game == 'carrom' ? 'CARROM' : 'BILLIARD');
  final buyIn = (ch['stake'] as int?) ?? ch['buyIn'] as int;
  await showDuelDialog<void>(
    context,
    barrierColor: const Color(0xCC000000),
    builder: (dialog) => _IncomingDialog(ch: ch, from: from, title: title, buyIn: buyIn),
  );
}

class _IncomingDialog extends ConsumerStatefulWidget {
  const _IncomingDialog({required this.ch, required this.from, required this.title, required this.buyIn});

  final Map<String, dynamic> ch;
  final Map<String, dynamic> from;
  final String title;
  final int buyIn;

  @override
  ConsumerState<_IncomingDialog> createState() => _IncomingDialogState();
}

class _IncomingDialogState extends ConsumerState<_IncomingDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final room = await ref.read(sessionProvider.notifier).acceptChallenge(widget.ch['id'] as int);
      if (!mounted) return;
      Navigator.of(context).pop();
      await openChallengeRoom(context, ref, room);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    try {
      await ref.read(sessionProvider.notifier).declineChallenge(widget.ch['id'] as int);
    } on ApiException {
      // ignore
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(24),
          decoration: duelPanel(rim: DuelColors.gold, glow: true),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.challengeTitle, style: AppText.label(24, color: DuelColors.gold, weight: FontWeight.w900)),
              const SizedBox(height: 16),
              Container(
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF5C8BFF), Color(0xFFFF3B4E)])),
                child: ClipOval(child: AvatarImage(widget.from['avatar'] as String, size: 88)),
              ),
              const SizedBox(height: 10),
              Text((widget.from['name'] as String).toUpperCase(), style: AppText.label(22, weight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(t.challengesYou(widget.title), style: AppText.label(15, color: DuelColors.silver)),
              const SizedBox(height: 8),
              if (widget.buyIn > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const PikoCoinIcon(size: 26),
                    const SizedBox(width: 6),
                    Text(t.buyInWin(widget.buyIn, formatCoins(widget.ch['prize'] as int)),
                        style: AppText.label(16, color: DuelColors.gold, weight: FontWeight.w800)),
                  ],
                )
              else
                Text(t.friendlyNoStake, style: AppText.label(14, color: DuelColors.dim)),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!.toUpperCase(), style: AppText.label(13, color: DuelColors.red)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DuelButton(label: _busy ? '...' : t.accept, width: 180, height: 52, onPressed: _busy ? null : _accept),
                  const SizedBox(width: 12),
                  DuelButton(label: t.decline, width: 150, height: 52, color: DuelColors.rimLight, onPressed: _busy ? null : _decline),
                ],
              ),
            ],
          ),
        ),
      );
  }
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
  bool _dialogOpen = false;
  final _handled = <int>{};

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
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
    // Incoming challenges.
    try {
      final inbox = await notifier.challengeInbox();
      final incoming = (inbox['incoming'] as List).cast<Map<String, dynamic>>();
      if (mounted && !_dialogOpen && incoming.isNotEmpty) {
        final ch = incoming.first;
        final id = ch['id'] as int;
        if (!_handled.contains(id)) {
          _handled.add(id);
          _dialogOpen = true;
          await showIncomingChallenge(context, ref, ch);
          _dialogOpen = false;
        }
      }
    } on ApiException {
      // ignore
    }
  }

  Future<void> _challenge(Map<String, dynamic> player) async {
    var levels = ref.read(lobbyProvider).valueOrNull?.levelsFor(DuelMode.billiard);
    if (levels == null || levels.isEmpty) {
      try {
        await ref.read(lobbyProvider.notifier).refresh();
      } catch (_) {}
      levels = ref.read(lobbyProvider).valueOrNull?.levelsFor(DuelMode.billiard) ?? const [];
    }
    final bets = levels ?? const <BetLevel>[];
    if (!mounted) return;
    await showDuelDialog<void>(
      context,
      barrierColor: const Color(0xCC000000),
      builder: (dialog) => _SendDialog(player: player, levels: bets),
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

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({required this.player, required this.onChallenge});

  final Map<String, dynamic> player;
  final VoidCallback onChallenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final busy = player['busy'] as bool? ?? false;
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
              ],
            ),
          ),
          if (busy)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF2A2F4A), borderRadius: BorderRadius.circular(10)),
              child: Text(t.inMatch, style: AppText.label(13, color: DuelColors.dim, weight: FontWeight.w800)),
            )
          else
            DuelButton(label: t.challengeBtn, width: 170, height: 46, fontSize: 15, color: DuelColors.gold, onPressed: onChallenge),
        ],
      ),
    );
  }
}

class _SendDialog extends ConsumerStatefulWidget {
  const _SendDialog({required this.player, required this.levels});

  final Map<String, dynamic> player;
  final List<BetLevel> levels;

  @override
  ConsumerState<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends ConsumerState<_SendDialog> {
  String _game = 'billiard';
  int? _level; // null = free
  bool _busy = false;
  String? _error;
  int? _sentId;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ch = await ref.read(sessionProvider.notifier).sendChallenge(widget.player['id'] as int, _game, _level);
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _gameChip(t.billiardTitle, 'billiard'),
                  const SizedBox(width: 12),
                  _gameChip(t.ludoTitle, 'ludo2'),
                  const SizedBox(width: 12),
                  _gameChip(t.carromTitle, 'carrom'),
                ],
              ),
              const SizedBox(height: 18),
              Text(t.stake, style: AppText.label(13, color: DuelColors.dim)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _stakeChip(t.freeStake, null),
                      for (final l in widget.levels) _stakeChip('${l.stake}', l.level),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!.toUpperCase(), style: AppText.label(13, color: DuelColors.red)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DuelButton(label: _busy ? '...' : t.send, width: 180, height: 50, color: DuelColors.gold, onPressed: _busy ? null : _send),
                  const SizedBox(width: 12),
                  DuelButton(label: t.close, width: 150, height: 50, color: DuelColors.rimLight, onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gameChip(String label, String game) {
    final on = _game == game;
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        setState(() => _game = game);
      },
      child: Container(
        width: 150,
        height: 52,
        alignment: Alignment.center,
        decoration: duelPanel(radius: 12, rim: on ? DuelColors.green : DuelColors.rim, glow: on, fill: on ? const Color(0xE60C2414) : const Color(0xCC0B0E1C)),
        child: Text(label, style: AppText.label(17, color: on ? DuelColors.green : DuelColors.silver, weight: FontWeight.w900)),
      ),
    );
  }

  Widget _stakeChip(String label, int? level) {
    final on = _level == level;
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        setState(() => _level = level);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: duelPanel(radius: 10, rim: on ? DuelColors.gold : DuelColors.rim, glow: on),
        child: Text(label, style: AppText.label(15, color: on ? DuelColors.gold : DuelColors.silver, weight: FontWeight.w800)),
      ),
    );
  }
}
