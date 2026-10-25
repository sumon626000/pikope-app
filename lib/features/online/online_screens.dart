import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bd_phone.dart';
import '../../core/app_state.dart';
import '../../core/widgets/bd_phone_field.dart';
import '../../core/app_theme.dart';
import '../../core/duel_ui.dart' show formatCoins;
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../data/app_game.dart';
import '../../data/match_bet.dart';
import '../game/game_controller.dart';
import '../game/game_screen.dart';
import '../misc/page_frame.dart';
import '../pool/pool_controller.dart';
import '../pool/pool_screen.dart';
import '../carrom/carrom_controller.dart';
import '../carrom/carrom_screen.dart';
import '../ludo/ludo_controller.dart';
import '../ludo/ludo_screen.dart';
import '../start/forgot_password_screen.dart';
import '../start/login_screen.dart';
import 'game_link.dart';
import 'realtime_socket.dart';
import 'session.dart';
import '../duel/lobby_data.dart';
import '../../l10n/strings.dart';

/// Opens the match screen for an online game - from a full room, or when
/// rejoining a match that is already running.
Future<void> openOnlineMatch(
  NavigatorState navigator,
  ApiClient api, {
  required int gameId,
  required int? roomId,
  required String gameKey,
  required int seat,
  required int shotSeconds,
  required List<Map<String, dynamic>> players,
  required String? wsUrl,
  Map<String, dynamic>? bet,
  bool intro = false,
  bool replace = true,
}) {
  final seats = [
    for (final p in players)
      SeatConfig(name: p['name'] as String, avatar: p['avatar'] as String, cue: p['cue'] as String? ?? 'classic'),
  ];
  final stake = MatchBet.fromJson(bet);
  final driver = OnlineGameDriver(api, gameId, seat, roomId: roomId, wsUrl: wsUrl);
  final MaterialPageRoute<void> route;
  if (gameKey.startsWith('ludo')) {
    route = MaterialPageRoute<void>(
      builder: (_) => LudoScreen(
        config: LudoMatchConfig(seats: players.length, players: seats, shotSeconds: shotSeconds, bet: stake),
        driver: driver,
      ),
    );
  } else if (gameKey == 'carrom') {
    route = MaterialPageRoute<void>(
      builder: (_) => Consumer(builder: (context, ref, _) {
        final prefs = ref.read(settingsProvider);
        return CarromScreen(
          config: CarromMatchConfig(seats: seats, shotSeconds: shotSeconds, bet: stake, strikerSkin: prefs.carromStriker, pieceSkin: prefs.carromPieces, boardSkin: prefs.carromBoard),
          driver: driver,
        );
      }),
    );
  } else {
    final game = AppGameInfo.fromApi(gameKey);
    final pool = game.poolGame;
    route = MaterialPageRoute<void>(
      builder: (_) => pool == null
          ? GameScreen(config: MatchConfig(seats: seats, shotSeconds: shotSeconds, bet: stake), driver: driver, intro: intro)
          : PoolScreen(
              config: PoolMatchConfig(game: pool, seats: seats, shotSeconds: shotSeconds, bet: stake),
              driver: driver,
              intro: intro,
            ),
    );
  }
  return replace ? navigator.pushReplacement<void, void>(route) : navigator.push(route);
}

const _body = TextStyle(fontFamily: 'sans-serif', fontSize: 14, height: 1.4, color: AppColors.text);

/// Online entry for one game: quick match, private room, or join by code.
///
/// Pool / poker games use the default constructor; Ludo uses [OnlineLobbyScreen.ludo]
/// and carrom [OnlineLobbyScreen.carrom] (free private rooms only - those have
/// no free public quick match).
class OnlineLobbyScreen extends ConsumerStatefulWidget {
  const OnlineLobbyScreen({super.key, required this.game})
      : ludoPlayers = null,
        carrom = false,
        friendLevel = null,
        friendGameKey = null;

  /// A Ludo private room for [players] (2 or 4).
  const OnlineLobbyScreen.ludo(this.ludoPlayers, {super.key})
      : game = null,
        carrom = false,
        friendLevel = null,
        friendGameKey = null;

  /// A carrom private room.
  const OnlineLobbyScreen.carrom({super.key})
      : game = null,
        ludoPlayers = null,
        carrom = true,
        friendLevel = null,
        friendGameKey = null;

  /// Private room at a chosen stake (play with friends).
  const OnlineLobbyScreen.stakedPrivate({super.key, required String gameKey, required BetLevel level})
      : game = null,
        ludoPlayers = gameKey == 'ludo2' ? 2 : (gameKey == 'ludo4' ? 4 : null),
        carrom = gameKey == 'carrom',
        friendLevel = level,
        friendGameKey = gameKey;

  final AppGame? game;
  final int? ludoPlayers;
  final bool carrom;
  final BetLevel? friendLevel;
  final String? friendGameKey;

  bool get isLudo => ludoPlayers != null;
  String get gameKey =>
      friendGameKey ?? (carrom ? 'carrom' : (isLudo ? (ludoPlayers == 2 ? 'ludo2' : 'ludo4') : game!.apiName));

  bool get stakedFriends => friendLevel != null;
  String get titleText => carrom
      ? 'CARROM'
      : isLudo
          ? 'LUDO'
          : (game?.title ?? AppGameInfo.titleOf(friendGameKey ?? gameKey));
  String get taglineText => carrom
      ? '1 V 1 - PRIVATE ROOM'
      : isLudo
          ? (ludoPlayers == 2 ? '2 PLAYERS - PRIVATE ROOM' : '4 PLAYERS - PRIVATE ROOM')
          : game!.tagline;

  @override
  ConsumerState<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends ConsumerState<OnlineLobbyScreen> {
  final _code = TextEditingController();
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _signIn();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _signIn() => _run(() => ref.read(sessionProvider.notifier).ensureSignedIn());

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      _error = ref.read(stringsProvider).maybeApi(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enter(String path, Map<String, dynamic> body) => _run(() async {
        final room = await ref.read(apiProvider)!.post(path, body);
        if (!mounted) return;
        await Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => RoomScreen(room: room)));
      });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(settingsProvider);
    final level = widget.friendLevel;
    final gameTitle = widget.carrom
        ? t.carromTitle
        : widget.isLudo
            ? t.ludoTitle
            : (widget.game != null ? t.appGameTitle(widget.game!) : AppGameInfo.titleOf(widget.gameKey));
    final tagline = widget.carrom
        ? t.taglinePrivateCarrom
        : widget.isLudo
            ? t.taglinePrivateLudo(widget.ludoPlayers ?? 4)
            : widget.game != null
                ? t.appGameTagline(widget.game!)
                : t.poolFriendsBody;
    return PageFrame(
      title: t.onlineSuffix(gameTitle),
      maxWidth: 760,
      child: Column(
        children: [
          SectionCard(
            title: t.you,
            child: Row(
              children: [
                FramedTile(size: 52, child: AvatarImage(settings.avatar, size: 52)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(settings.name.toUpperCase(), style: AppText.label(16, weight: FontWeight.w900)),
                      Text(
                        !session.signedIn
                            ? t.connecting
                            : session.isGuest
                                ? t.guestHint
                                : session.phone ?? '',
                        style: AppText.label(11, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
                GameButton(
                  label: t.account,
                  icon: Icons.person_rounded,
                  height: 40,
                  width: 170,
                  fontSize: 13,
                  color: AppColors.frame,
                  onPressed: session.signedIn
                      ? () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const AccountScreen()))
                      : null,
                ),
              ],
            ),
          ),
          if (_error != null)
            SectionCard(
              title: t.problem,
              child: Row(
                children: [
                  Expanded(child: Text(_error!, style: _body)),
                  if (!session.signedIn)
                    GameButton(label: t.retry, height: 40, width: 130, fontSize: 13, onPressed: _signIn),
                ],
              ),
            ),
          if (level != null) ...[
            Builder(builder: (context) {
              final seats = widget.isLudo
                  ? (widget.ludoPlayers ?? 2)
                  : (widget.carrom ? 2 : (widget.game?.players ?? 2));
              final prize = level.prize ?? level.stake * seats;
              return SectionCard(
                title: level.displayName,
                child: Text(t.friendsStakeLine(formatCoins(level.buyIn), formatCoins(prize)), style: _body),
              );
            }),
          ],
          SectionCard(
            title: tagline,
            child: Column(
              children: [
                Row(
                  children: [
                    // Ludo friendly rooms are private only (no public quick match).
                    if (!widget.isLudo && !widget.stakedFriends) ...[
                      Expanded(
                        child: GameButton(
                          label: t.quickMatch,
                          icon: Icons.bolt_rounded,
                          height: 54,
                          fontSize: 17,
                          onPressed: _busy || !session.signedIn
                              ? null
                              : () => _enter('/rooms/quick', {'game': widget.gameKey}),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: GameButton(
                        label: t.privateRoom,
                        icon: Icons.lock_rounded,
                        height: 54,
                        fontSize: 17,
                        color: AppColors.gold,
                        onPressed: _busy || !session.signedIn
                            ? null
                            : () {
                                final body = <String, dynamic>{'game': widget.gameKey, 'private': true};
                                if (widget.friendLevel != null) body['level'] = widget.friendLevel!.level;
                                _enter('/rooms', body);
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        maxLength: 6,
                        textCapitalization: TextCapitalization.characters,
                        style: AppText.label(18),
                        decoration: InputDecoration(labelText: t.roomCode, counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GameButton(
                      label: t.join,
                      icon: Icons.login_rounded,
                      height: 48,
                      width: 150,
                      fontSize: 15,
                      color: AppColors.frame,
                      onPressed: _busy || !session.signedIn
                          ? null
                          : () {
                              final code = _code.text.trim();
                              if (code.length == 6) _enter('/rooms/join', {'code': code});
                            },
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

/// Waiting room: shows who is seated and starts the match when it is full.
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key, required this.room});

  final Map<String, dynamic> room;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  late Map<String, dynamic> _room = widget.room;
  Timer? _timer;
  bool _started = false;
  String? _error;
  String? _wsUrl;
  RealtimeSocket? _socket;

  ApiClient get _api => ref.read(apiProvider)!;

  @override
  void initState() {
    super.initState();
    // HTTP polling keeps the seat alive whenever the socket is not connected.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
    _watchLive();
  }

  /// With a WebSocket server the room updates the moment someone joins.
  Future<void> _watchLive() async {
    final url = await ref.read(sessionProvider.notifier).realtimeUrl();
    if (!mounted || _started) return;
    _wsUrl = url;
    if (url == null || url.isEmpty || _api.token == null) return;
    _socket = RealtimeSocket(
      url,
      _api.token!,
      onConnected: () => _socket?.send({'t': 'room', 'roomId': _room['id']}),
      onMessage: (message) {
        if (message['t'] != 'room' || !mounted || _started) return;
        setState(() {
          _room = message['room'] as Map<String, dynamic>;
          _error = null;
        });
        _maybeStart();
      },
    )..connect();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_started || (_socket?.connected ?? false)) return;
    try {
      final room = await _api.get('/rooms/${_room['id']}');
      if (!mounted) return;
      setState(() {
        _room = room;
        _error = null;
      });
      _maybeStart();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = ref.read(stringsProvider).maybeApi(e.message));
    }
  }

  Future<void> _maybeStart() async {
    if (_started || _room['status'] != 'playing' || _room['gameId'] == null) return;
    _started = true;
    _timer?.cancel();
    _socket?.dispose();
    // The room may fill before the address was looked up.
    _wsUrl ??= await ref.read(sessionProvider.notifier).realtimeUrl();
    if (!mounted) return;
    final myId = ref.read(sessionProvider).userId;
    final players = (_room['players'] as List).cast<Map<String, dynamic>>();
    openOnlineMatch(
      Navigator.of(context),
      _api,
      gameId: _room['gameId'] as int,
      roomId: _room['id'] as int,
      gameKey: _room['game'] as String,
      seat: players.firstWhere((p) => p['id'] == myId)['seat'] as int,
      shotSeconds: _room['shotSeconds'] as int,
      players: players,
      wsUrl: _wsUrl,
    );
  }

  Future<void> _leave() async {
    _timer?.cancel();
    _socket?.dispose();
    try {
      await _api.post('/rooms/${_room['id']}/leave');
    } on ApiException {
      // Leaving anyway; the server drops idle seats on its own.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final players = (_room['players'] as List).cast<Map<String, dynamic>>();
    final seats = _room['seats'] as int;
    final gameKey = _room['game'] as String;
    final gameTitle = t.gameTitleKey(gameKey);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: PageFrame(
        title: t.roomTitle(gameTitle, _room['code'] as String),
        maxWidth: 760,
        action: GameButton(
          label: t.leave,
          icon: Icons.logout_rounded,
          width: 150,
          height: 42,
          fontSize: 13,
          color: AppColors.danger,
          onPressed: _leave,
        ),
        child: Column(
          children: [
            SectionCard(
              title: t.waitingPlayers(players.length, seats),
              child: Row(
                children: [
                  for (var i = 0; i < seats; i++)
                    Expanded(
                      child: Column(
                        children: [
                          FramedTile(
                            size: 64,
                            frameColor: i < players.length ? AppColors.active : AppColors.frame,
                            child: i < players.length
                                ? AvatarImage(players[i]['avatar'] as String, size: 64)
                                : const Icon(Icons.hourglass_empty_rounded, color: AppColors.textDim, size: 30),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              i < players.length ? (players[i]['name'] as String).toUpperCase() : t.emptySeat,
                              style: AppText.label(13,
                                  color: i < players.length ? AppColors.text : AppColors.textDim),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: _room['isPrivate'] == true ? t.privateRoom : t.publicRoom,
              child: Row(
                children: [
                  Text(t.code, style: AppText.label(13, color: AppColors.textDim)),
                  const SizedBox(width: 12),
                  SelectableText(_room['code'] as String,
                      style: AppText.label(26, color: AppColors.gold, weight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _error ??
                          (_room['isPrivate'] == true ? t.sharePrivateRoom : t.publicRoomHint),
                      style: _body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add a login to the guest account, sign in to an existing one, or sign out.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      _message = done;
    } on ApiException catch (e) {
      _message = ref.read(stringsProvider).maybeApi(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final session = ref.watch(sessionProvider);
    final notifier = ref.read(sessionProvider.notifier);
    final guest = !session.signedIn || session.isGuest;
    return PageFrame(
      title: t.account,
      maxWidth: 620,
      child: Column(
        children: [
          SectionCard(
            title: guest ? t.keepProgress : t.signedIn,
            child: guest
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.guestAccountBody, style: _body),
                      BdPhoneField(
                        controller: _phone,
                        decoration: InputDecoration(labelText: t.mobile880),
                      ),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        decoration: InputDecoration(labelText: t.password8),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: GameButton(
                              label: t.createLogin,
                              height: 46,
                              fontSize: 14,
                              onPressed: _busy
                                  ? null
                                  : () {
                                      final err = BdPhone.validationMessage(_phone.text.trim(), t);
                                      if (err != null) {
                                        setState(() => _message = err);
                                        return;
                                      }
                                      _run(
                                        () => notifier.register(_phone.text.trim(), _password.text),
                                        t.msgLoginAdded,
                                      );
                                    },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GameButton(
                              label: t.signIn,
                              height: 46,
                              fontSize: 14,
                              color: AppColors.frame,
                              onPressed: _busy
                                  ? null
                                  : () {
                                      final err = BdPhone.validationMessage(_phone.text.trim(), t);
                                      if (err != null) {
                                        setState(() => _message = err);
                                        return;
                                      }
                                      _run(
                                        () => notifier.login(_phone.text.trim(), _password.text),
                                        t.msgSignedIn,
                                      );
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      GameButton(
                        label: t.forgotPasswordBtn,
                        height: 40,
                        fontSize: 12,
                        color: const Color(0xFF2B2B38),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ForgotPasswordScreen(initialPhoneLocal: _phone.text.trim()),
                                  ),
                                ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: Text(session.phone ?? '', style: AppText.label(15))),
                      GameButton(
                        label: t.signOut,
                        height: 42,
                        width: 170,
                        fontSize: 13,
                        color: AppColors.danger,
                        onPressed: _busy
                            ? null
                            : () async {
                                final navigator = Navigator.of(context);
                                await notifier.logout();
                                // Back to the sign-in screen, nothing behind it.
                                navigator.pushAndRemoveUntil(
                                    MaterialPageRoute<void>(builder: (_) => const LoginScreen()), (_) => false);
                              },
                      ),
                    ],
                  ),
          ),
          if (_message != null) SectionCard(title: t.status, child: Text(_message!, style: _body)),
        ],
      ),
    );
  }
}
