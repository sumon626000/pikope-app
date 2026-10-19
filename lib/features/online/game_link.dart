import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api_client.dart';
import 'realtime_socket.dart';

/// How a match controller talks to the server in an online game.
abstract class GameLink {
  /// The local player's seat.
  int get seat;

  /// Sends a player action (`{type: ..., ...}`).
  void send(Map<String, dynamic> action);

  /// Shares where the local player's cue points (`a` angle, `p` power,
  /// `x`/`y` cue ball) so the others can watch the shot being lined up.
  /// Best effort: dropped when there is no live connection.
  void sendAim(Map<String, dynamic> aim);
}

/// Connects one online match to its controller.
///
/// With a WebSocket address the match is live: actions go over the socket and
/// every change is pushed the moment it happens. Whenever the socket is not
/// available (no WebSocket server, a dropped connection) it falls back to
/// HTTP - actions are posted and the state is polled - so play never depends
/// on the socket.
class OnlineGameDriver implements GameLink {
  OnlineGameDriver(
    this.api,
    this.gameId,
    this.seat, {
    this.roomId,
    this.wsUrl,
    this.pollInterval = const Duration(milliseconds: 350),
  });

  final ApiClient api;
  final int gameId;
  @override
  final int seat;

  /// Room this match came from (for "play again").
  final int? roomId;

  /// WebSocket server, or null to use HTTP only.
  final String? wsUrl;
  final Duration pollInterval;

  /// Called with the server's view of the game and the server clock (ms).
  void Function(Map<String, dynamic> state, int serverNow)? onState;

  /// Called with another player's cue position while they aim.
  void Function(Map<String, dynamic> aim)? onAim;

  /// Called when another player sends a quick-chat preset (seat, preset index).
  void Function(int seat, int message)? onChat;

  /// Called when an action was refused or the server is unreachable.
  void Function(ApiException error)? onError;

  int _version = 0;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();

  RealtimeSocket? _socket;
  bool _joined = false;
  int _nextAction = 0;
  final Map<int, Completer<void>> _pending = {};

  /// True while the match is running over the WebSocket.
  bool get realtime => _joined && (_socket?.connected ?? false);

  /// True while the server cannot be reached (no answer over the socket or
  /// over HTTP for [_offlineAfter]). Play resumes by itself once it is back.
  final ValueNotifier<bool> offline = ValueNotifier(false);
  /// Shown as "reconnecting" until contact returns; match state keeps polling.
  static const _offlineAfter = Duration(seconds: 20);
  DateTime _lastContact = DateTime.now();

  void _contact() {
    _lastContact = DateTime.now();
    if (!_disposed) offline.value = false;
  }

  /// States delivered over the socket / over HTTP (diagnostics, tests).
  int pushedStates = 0;
  int polledStates = 0;

  void start() {
    final url = wsUrl;
    if (url != null && url.isNotEmpty && api.token != null) {
      _socket = RealtimeSocket(
        url,
        api.token!,
        onMessage: _onSocketMessage,
        onConnected: () => _socket?.send({'t': 'join', 'gameId': gameId}),
        onActivity: _contact,
      )..connect();
    }
    _lastContact = DateTime.now();
    _timer ??= Timer.periodic(pollInterval, (_) {
      if (!realtime) poll();
      if (DateTime.now().difference(_lastContact) > _offlineAfter) offline.value = true;
    });
    poll();
  }

  void _onSocketMessage(Map<String, dynamic> message) {
    if (_disposed) return;
    switch (message['t']) {
      case 'state':
        _joined = true;
        _settle(message['re']);
        if (_deliver(message)) pushedStates++;
      case 'aim':
        onAim?.call(message);
      case 'chat':
        final seat = message['s'], m = message['m'];
        if (seat is int && m is int) onChat?.call(seat, m);
      case 'error':
        _settle(message['re']);
        onError?.call(ApiException(409, message['code'] as String? ?? 'error',
            message['message'] as String? ?? 'Request refused'));
      case 'disconnected':
        // Whatever was in flight may or may not have arrived: let the HTTP
        // poll bring the truth.
        _joined = false;
        for (final c in _pending.values) {
          if (!c.isCompleted) c.complete();
        }
        _pending.clear();
        poll();
    }
  }

  void _settle(Object? actionNumber) {
    if (actionNumber is int) _pending.remove(actionNumber)?.complete();
  }

  Future<void> poll() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      final reply = await api.get('/games/$gameId?since=$_version');
      _contact();
      _offerAim(reply);
      if (_deliver(reply)) polledStates++;
    } on ApiException catch (e) {
      if (e.code != 'network') _contact(); // refused, but the server answered
      if (!_disposed) onError?.call(e);
    } finally {
      _polling = false;
    }
  }

  int _httpInFlight = 0;

  @override
  void send(Map<String, dynamic> action) {
    // Never overtake an action that is still travelling over HTTP.
    if (realtime && _httpInFlight == 0) {
      final n = ++_nextAction;
      if (_socket!.send({'t': 'act', 'gameId': gameId, 'n': n, 'action': action})) {
        _pending[n] = Completer<void>();
        return;
      }
    }
    _httpInFlight++;
    _queue = _queue.then((_) async {
      try {
        if (_disposed) return;
        final reply = await api.post('/games/$gameId/actions', action);
        _contact();
        _offerAim(reply);
        if (_deliver(reply)) polledStates++;
      } on ApiException catch (e) {
        if (e.code != 'network') _contact();
        if (!_disposed) onError?.call(e);
      } finally {
        _httpInFlight--;
      }
    });
  }

  DateTime _nextAimHttp = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void sendAim(Map<String, dynamic> aim) {
    if (realtime) {
      _socket!.send({'t': 'aim', 'gameId': gameId, 's': seat, ...aim});
      return;
    }
    // No WebSocket on the live host: post the cue so the next poll can show it.
    final now = DateTime.now();
    if (!now.isAfter(_nextAimHttp)) return;
    _nextAimHttp = now.add(const Duration(milliseconds: 160));
    api.post('/games/$gameId/aim', {
      'a': aim['a'],
      'p': aim['p'],
      'x': aim['x'],
      'y': aim['y'],
    }).then((_) {
      if (!_disposed) _contact();
    }, onError: (_) {});
  }

  void _offerAim(Map<String, dynamic> reply) {
    final raw = reply['aim'];
    if (raw is! Map) return;
    final aim = Map<String, dynamic>.from(raw);
    final who = aim['s'];
    if (who == seat) return;
    onAim?.call(aim);
  }

  /// Sends a quick-chat preset to the other players. Best effort: dropped
  /// when there is no live connection.
  void sendChat(int message) {
    if (realtime) _socket!.send({'t': 'chat', 'gameId': gameId, 'm': message});
  }

  /// Completes once every action sent so far has been answered.
  Future<void> get idle => Future.wait<void>([_queue, for (final c in _pending.values) c.future])
      .timeout(const Duration(seconds: 5), onTimeout: () => const []);

  bool _deliver(Map<String, dynamic> reply) {
    if (_disposed || reply['unchanged'] == true) return false;
    final version = reply['version'] as int;
    if (version <= _version) return false;
    _version = version;
    onState?.call(reply['state'] as Map<String, dynamic>, reply['serverNow'] as int);
    return true;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _socket?.dispose();
  }
}
