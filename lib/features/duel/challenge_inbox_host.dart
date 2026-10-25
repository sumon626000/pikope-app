import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/env.dart';
import '../../core/push_service.dart';
import '../../core/root_nav.dart';
import '../../l10n/strings.dart';
import '../online/session.dart';
import 'challenge_incoming_banner.dart';
import 'challenge_inbox_pulse.dart';
import 'challenge_prefs.dart';
import 'challenge_screen.dart';

/// Pending incoming 1v1 invites (for nav badges).
final challengePendingCountProvider = StateProvider<int>((ref) => 0);

/// Polls the challenge inbox app-wide so online players see invites on any
/// screen (lobby, bet tables, matchmaking), not only on the home screen.
class ChallengeInboxHost extends ConsumerStatefulWidget {
  const ChallengeInboxHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ChallengeInboxHost> createState() => _ChallengeInboxHostState();
}

class _ChallengeInboxHostState extends ConsumerState<ChallengeInboxHost> {
  Timer? _poll;
  bool _dialogOpen = false;
  int? _showingId;
  final Set<int> _notifiedIds = {};

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 900), (_) => _tick());
    triggerChallengeInboxPoll = _tick;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    if (triggerChallengeInboxPoll == _tick) {
      triggerChallengeInboxPoll = null;
    }
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!mounted || !Env.hasBackend) return;
    final settings = ref.read(settingsProvider);
    if (!anyChallengeReceiveEnabled(settings)) {
      ref.read(challengePendingCountProvider.notifier).state = 0;
      return;
    }
    if (ref.read(settingsProvider).authToken.isEmpty) return;
    if (ref.read(apiProvider) == null) return;
    try {
      final inbox = await ref.read(sessionProvider.notifier).challengeInbox();
      if (!mounted) return;
      final incoming = (inbox['incoming'] as List).cast<Map<String, dynamic>>();
      final visible = incoming
          .where((c) => acceptsIncomingChallenge(settings, (c['game'] as String?) ?? ''))
          .toList();
      ref.read(challengePendingCountProvider.notifier).state = visible.length;
      if (visible.isEmpty) return;
      final ch = visible.first;
      final id = ch['id'] as int;
      if (!_notifiedIds.contains(id)) {
        _notifiedIds.add(id);
        final t = ref.read(stringsProvider);
        final from = ch['from'] as Map<String, dynamic>?;
        final name = from?['name'] as String? ?? 'Player';
        final game = challengeGameTitle((ch['game'] as String?) ?? '');
        unawaited(PushService.show(title: t.challengeTitle, body: t.challengesYou(game.isEmpty ? name : '$name · $game')));
      }
      if (_dialogOpen) return;
      // Hide only during an active seated match, not in lobby/matchmaking.
      final active = ref.read(activeMatchProvider).valueOrNull;
      if (active != null && (active['status'] as String?) == 'playing') return;
      if (_showingId == id) return;
      final navCtx = rootNavigatorKey.currentContext;
      if (navCtx == null || !navCtx.mounted) return;
      _showingId = id;
      _dialogOpen = true;
      await showIncomingChallenge(navCtx, ref, ch);
      _dialogOpen = false;
      _showingId = null;
    } on Object {
      // offline / not signed in
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
