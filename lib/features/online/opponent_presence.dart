import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../l10n/strings.dart';

/// Server-side disconnect grace countdown for the other human player.
class OpponentPresenceSnapshot {
  OpponentPresenceSnapshot({required this.online, required this.forfeitAtMs, required this.serverNowMs});

  final bool online;
  final int forfeitAtMs;
  final int serverNowMs;

  int secondsLeft(int localNowMs, int serverOffsetMs) {
    final serverNow = localNowMs + serverOffsetMs;
    final left = ((forfeitAtMs - serverNow) / 1000).ceil();
    return left.clamp(0, 999);
  }
}

OpponentPresenceSnapshot? opponentPresenceFromPoll(
  Object? raw,
  int mySeat, {
  required int serverNowMs,
}) {
  if (raw is! Map) return null;
  OpponentPresenceSnapshot? pick(Map<dynamic, dynamic> entry) {
    final forfeitAt = entry['forfeitAt'];
    if (forfeitAt is! num) return null;
    return OpponentPresenceSnapshot(
      online: entry['online'] as bool? ?? true,
      forfeitAtMs: forfeitAt.round(),
      serverNowMs: serverNowMs,
    );
  }
  for (final e in raw.entries) {
    final seat = int.tryParse(e.key.toString());
    if (seat == null || seat == mySeat || e.value is! Map) continue;
    final snap = pick(e.value as Map);
    if (snap != null && !snap.online) return snap;
  }
  final opp = mySeat == 0 ? 1 : 0;
  final fallback = raw[opp] ?? raw['$opp'];
  if (fallback is Map) return pick(fallback);
  return null;
}

OpponentPresenceSnapshot? opponentPresenceFromState(Map<String, dynamic> state, int mySeat, int serverNowMs) {
  final ps = state['players'];
  if (ps is! List) return null;
  final opp = mySeat == 0 ? 1 : 0;
  if (opp >= ps.length) return null;
  final p = ps[opp];
  if (p is! Map) return null;
  final pr = p['presence'];
  if (pr is! Map) return null;
  final forfeitAt = pr['forfeitAt'];
  if (forfeitAt is! num) return null;
  return OpponentPresenceSnapshot(
    online: pr['online'] as bool? ?? true,
    forfeitAtMs: forfeitAt.round(),
    serverNowMs: serverNowMs,
  );
}

/// Top banner while the opponent is disconnected (forfeit countdown).
class OpponentDisconnectBanner extends ConsumerStatefulWidget {
  const OpponentDisconnectBanner({
    super.key,
    required this.presence,
    required this.serverOffsetMs,
    required this.opponentName,
  });

  final OpponentPresenceSnapshot? presence;
  final int serverOffsetMs;
  final String opponentName;

  @override
  ConsumerState<OpponentDisconnectBanner> createState() => _OpponentDisconnectBannerState();
}

class _OpponentDisconnectBannerState extends ConsumerState<OpponentDisconnectBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.presence;
    if (p == null || p.online) return const SizedBox.shrink();
    final t = ref.watch(stringsProvider);
    final sec = p.secondsLeft(DateTime.now().millisecondsSinceEpoch, widget.serverOffsetMs);
    if (sec <= 0) return const SizedBox.shrink();
    return Positioned(
      left: 24,
      right: 24,
      top: 12,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xE0141028),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DuelColors.gold.withValues(alpha: 0.85), width: 2),
              boxShadow: [BoxShadow(color: DuelColors.gold.withValues(alpha: 0.25), blurRadius: 18)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.signal_wifi_off_rounded, color: DuelColors.gold, size: 28),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    t.opponentDisconnectBanner(widget.opponentName, sec),
                    textAlign: TextAlign.center,
                    style: AppText.label(18, color: Colors.white, weight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
