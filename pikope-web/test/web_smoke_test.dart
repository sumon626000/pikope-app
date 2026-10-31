import 'package:billiard_poker/core/env.dart';
import 'package:billiard_poker/core/web_play.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API base URL configured for online builds', () {
    expect(Env.apiBaseUrl, isNotEmpty);
  });

  test('WebSocket normalizer keeps wss URLs', () {
    expect(normalizeWebSocketForWeb('wss://game.example/ws'), 'wss://game.example/ws');
    expect(normalizeWebSocketForWeb(null), isNull);
    expect(normalizeWebSocketForWeb(''), '');
  });
}
