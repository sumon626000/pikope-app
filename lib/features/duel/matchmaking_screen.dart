import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../online/online_screens.dart';
import '../online/realtime_socket.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import '../../l10n/strings.dart';
import 'lobby_data.dart';

/// Waits for opponents at the chosen bet level, then opens the match.
class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({super.key, required this.mode, required this.level});

  final DuelMode mode;
  final BetLevel level;

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  Map<String, dynamic>? _room;
  Timer? _timer;
  RealtimeSocket? _socket;
  String? _wsUrl;
  String? _error;
  bool _started = false;
  bool _left = false;

  ApiClient get _api => ref.read(apiProvider)!;

  @override
  void initState() {
    super.initState();
    ref.read(audioProvider).playGameplayMusic();
    _join();
  }

  Future<void> _join() async {
    try {
      await ref.read(sessionProvider.notifier).ensureSignedIn();
      final room = await _api.post('/rooms/quick', {'game': widget.mode.apiName, 'level': widget.level.level});
      if (!mounted || _left) {
        // Backed out while the request was on its way: give the seat up.
        _api.post('/rooms/${room['id']}/leave').catchError((_) => <String, dynamic>{});
        return;
      }
      setState(() => _room = room);
      // Polling keeps the seat alive whenever the socket is not connected.
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
      _watchLive();
      _maybeStart();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = ref.read(stringsProvider).maybeApi(e.message));
    }
  }

  Future<void> _watchLive() async {
    final url = await ref.read(sessionProvider.notifier).realtimeUrl();
    if (!mounted || _started || _left) return;
    _wsUrl = url;
    if (url == null || url.isEmpty || _api.token == null) return;
    _socket = RealtimeSocket(
      url,
      _api.token!,
      onConnected: () => _socket?.send({'t': 'room', 'roomId': _room!['id']}),
      onMessage: (message) {
        if (message['t'] != 'room' || !mounted || _started) return;
        setState(() => _room = message['room'] as Map<String, dynamic>);
        _maybeStart();
      },
    )..connect();
  }

  Future<void> _poll() async {
    if (_started || _left || _room == null || (_socket?.connected ?? false)) return;
    try {
      final room = await _api.get('/rooms/${_room!['id']}');
      if (!mounted) return;
      setState(() {
        _room = room;
        _error = null;
      });
      _maybeStart();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 403 || e.status == 404) {
        // Lost the seat (connection was away too long): queue again.
        _timer?.cancel();
        _socket?.dispose();
        _socket = null;
        setState(() => _room = null);
        _join();
      }
    }
  }

  Future<void> _maybeStart() async {
    final room = _room;
    if (_started || room == null || room['status'] != 'playing' || room['gameId'] == null) return;
    _started = true;
    _timer?.cancel();
    _socket?.dispose();
    ref.read(audioProvider).play(Sfx.matchStart);
    setState(() {});
    _wsUrl ??= await ref.read(sessionProvider.notifier).realtimeUrl();
    // Let the players see who they drew.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final myId = ref.read(sessionProvider).userId;
    final players = (room['players'] as List).cast<Map<String, dynamic>>();
    openOnlineMatch(
      Navigator.of(context),
      _api,
      gameId: room['gameId'] as int,
      roomId: room['id'] as int,
      gameKey: room['game'] as String,
      seat: players.firstWhere((p) => p['id'] == myId)['seat'] as int,
      shotSeconds: room['shotSeconds'] as int,
      players: players,
      wsUrl: _wsUrl,
      bet: {
        'mode': widget.mode.apiName,
        'stake': room['stake'],
        'prize': room['prize'],
        'multiplier': room['multiplier'],
      },
      intro: widget.mode.isPoker,
    );
  }

  Future<void> _cancel() async {
    if (_started) return;
    _left = true;
    _timer?.cancel();
    _socket?.dispose();
    final room = _room;
    if (room != null) {
      try {
        await _api.post('/rooms/${room['id']}/leave');
      } on ApiException {
        // The server drops an idle seat by itself.
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _spin.dispose();
    _timer?.cancel();
    _socket?.dispose();
    if (!_started) ref.read(audioProvider).playMenuMusic();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final myId = ref.watch(sessionProvider).userId;
    final seats = widget.mode.seats;
    final players = ((_room?['players'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final others = [for (final p in players) if (p['id'] != myId) p];
    final poker = widget.mode == DuelMode.poker;
    final tile = poker ? 240.0 : 230.0;
    final prizeLine = _started && (_room?['prize'] as int? ?? 0) > 0
        ? t.prizeColon(formatCoins(_room!['prize'] as int))
        : poker
            ? t.entryWinUpTo(formatCoins(widget.level.buyIn), formatCoins(widget.level.maxPrize!, compact: true))
            : t.prizeColon(formatCoins(widget.level.prize!));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: DuelCanvas(
        child: Stack(
          children: [
            const Positioned(left: 0, right: 0, top: 6, child: DuelTopBar(showProfile: false, showShortcuts: false)),
            Positioned(
              left: 0,
              right: 0,
              top: 206,
              child: DuelTitle(_started ? t.matchFound : t.matchmaking, size: 66, sub: prizeLine),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 386,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Seat(size: tile, name: settings.name, avatar: settings.avatar),
                  SizedBox(
                    width: poker ? 96 : 110,
                    height: tile,
                    child: OverflowBox(
                      maxWidth: 200,
                      child: Text(t.vs,
                          style: AppText.label(poker ? 60 : 92, color: DuelColors.gold, weight: FontWeight.w900).copyWith(shadows: const [
                            Shadow(color: Color(0xFF7A4A00), offset: Offset(0, 5)),
                            Shadow(color: Color(0xCC000000), blurRadius: 14, offset: Offset(0, 8)),
                          ])),
                    ),
                  ),
                  for (var i = 0; i < seats - 1; i++) ...[
                    if (i > 0) SizedBox(width: poker ? 36 : 0),
                    i < others.length
                        ? _Seat(size: tile, name: others[i]['name'] as String, avatar: others[i]['avatar'] as String, looking: t.lookingForOpponent)
                        : _Seat(size: tile, spin: _spin, looking: t.lookingForOpponent),
                  ],
                ],
              ),
            ),
            if (_error != null)
              Positioned(
                left: 0,
                right: 0,
                top: 716,
                child: Column(
                  children: [
                    Text(_error!.toUpperCase(), style: AppText.label(18, color: DuelColors.red)),
                    const SizedBox(height: 12),
                    DuelButton(label: t.back, color: DuelColors.rimLight, onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
            if (!_started && _error == null)
              Positioned(left: 42, bottom: 34, child: NavTile(icon: Icons.reply_rounded, label: t.cancel, onTap: _cancel)),
            if (!_started && _error == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 70,
                child: Center(
                  child: Text(t.buyInHeld,
                      style: AppText.label(13, color: DuelColors.dim, weight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.size, this.name, this.avatar, this.spin, this.looking = 'LOOKING...'});

  final double size;
  final String? name;
  final String? avatar;
  final String looking;

  /// Set for a seat still being filled.
  final Animation<double>? spin;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4A4973),
              borderRadius: BorderRadius.circular(size * 0.14),
              boxShadow: const [BoxShadow(color: Color(0xB3000000), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.1),
              child: avatar != null
                  ? AvatarImage(avatar!, size: size - 16)
                  : AnimatedBuilder(
                      animation: spin!,
                      builder: (context, _) => CustomPaint(size: Size.square(size - 16), painter: _SearchPainter(spin!.value)),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: size + 30,
            child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text((name ?? looking).toUpperCase(),
                                maxLines: 1,
                style: AppText.label(30, color: DuelColors.silver, weight: FontWeight.w800)),
            ),
          ),
        ],
      );
}

/// A blurred, flickering silhouette while a seat is empty.
class _SearchPainter extends CustomPainter {
  _SearchPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF1C2A4A));
    final c = size.center(Offset.zero);
    final blur = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.07);
    // Head and shoulders, wobbling as if cycling through faces.
    final wobble = sin(t * 2 * pi) * size.width * 0.03;
    canvas.drawCircle(c + Offset(wobble, -size.height * 0.1), size.width * 0.2, blur..color = const Color(0xFF6C86C8));
    canvas.drawOval(
        Rect.fromCenter(center: c + Offset(-wobble, size.height * 0.42), width: size.width * 0.78, height: size.height * 0.6),
        blur..color = const Color(0xFF3F5FAE));
    // Sweep of light.
    final x = (t * 1.6 - 0.3) * size.width;
    canvas.drawRect(
      Rect.fromLTWH(x, 0, size.width * 0.3, size.height),
      Paint()
        ..shader = const LinearGradient(colors: [Color(0x00FFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF)])
            .createShader(Rect.fromLTWH(x, 0, size.width * 0.3, size.height)),
    );
    final tp = TextPainter(
      text: TextSpan(text: '?', style: AppText.label(size.width * 0.34, color: Colors.white.withValues(alpha: 0.55), weight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2 + size.height * 0.08));
  }

  @override
  bool shouldRepaint(_SearchPainter old) => old.t != t;
}
