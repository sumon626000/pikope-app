import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// A WebSocket to the game server that signs in, keeps itself alive and
/// reconnects on its own. While it is down, [connected] is false and callers
/// fall back to plain HTTP.
class RealtimeSocket {
  RealtimeSocket(this.url, this.token, {required this.onMessage, this.onConnected, this.onActivity});

  final String url;
  final String token;

  /// Every JSON message from the server except the sign-in handshake.
  final void Function(Map<String, dynamic> message) onMessage;

  /// Called each time the socket is signed in (first connect and reconnects):
  /// the place to (re)subscribe.
  final void Function()? onConnected;

  /// Called whenever anything arrives: proof the server is still reachable.
  final void Function()? onActivity;

  /// A ping goes out this often; the server answers each one.
  static const _pingEvery = Duration(seconds: 4);

  /// No word from the server for this long means the link is dead, even if
  /// the phone has not noticed yet (a lost signal does not close a socket).
  static const _deadAfter = Duration(seconds: 10);
  DateTime _lastData = DateTime.now();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _keepAlive;
  Timer? _retry;
  int _failures = 0;
  bool _disposed = false;

  /// Signed in and usable right now.
  bool connected = false;

  /// Messages received since creation (diagnostics / tests).
  int received = 0;

  void connect() {
    if (_disposed) return;
    _open();
  }

  Future<void> _open() async {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 5));
      if (_disposed) {
        channel.sink.close();
        return;
      }
      _subscription = channel.stream.listen(_onData, onDone: _onClosed, onError: (_) => _onClosed());
      channel.sink.add(jsonEncode({'t': 'auth', 'token': token}));
      _keepAlive?.cancel();
      _lastData = DateTime.now();
      _keepAlive = Timer.periodic(_pingEvery, (_) {
        if (DateTime.now().difference(_lastData) > _deadAfter) {
          channel.sink.close();
          _onClosed();
        } else {
          send({'t': 'ping'}, force: true);
        }
      });
    } catch (_) {
      _onClosed();
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    received++;
    _lastData = DateTime.now();
    onActivity?.call();
    switch (message['t']) {
      case 'auth_ok':
        connected = true;
        _failures = 0;
        onConnected?.call();
      case 'pong':
        break;
      default:
        onMessage(message);
    }
  }

  void _onClosed() {
    final wasConnected = connected;
    connected = false;
    _keepAlive?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_disposed) return;
    if (wasConnected) onMessage(const {'t': 'disconnected'});
    // Back off: 1, 2, 4 ... 15 seconds.
    _failures++;
    final seconds = _failures > 4 ? 15 : (1 << (_failures - 1));
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), _open);
  }

  /// Sends a message; returns false when the socket is not usable.
  bool send(Map<String, dynamic> message, {bool force = false}) {
    final channel = _channel;
    if (channel == null || (!connected && !force)) return false;
    try {
      channel.sink.add(jsonEncode(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    connected = false;
    _keepAlive?.cancel();
    _retry?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
  }
}
