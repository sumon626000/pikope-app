/// Lightweight section timers, compiled in only with
/// `--dart-define=PERF_LOG=true`.
class Perf {
  static const enabled = bool.fromEnvironment('PERF_LOG');

  static final Map<String, int> _micros = {};
  static final Map<String, int> _calls = {};
  static final Stopwatch _watch = Stopwatch()..start();

  static int begin() => enabled ? _watch.elapsedMicroseconds : 0;

  static void end(String section, int begun) {
    if (!enabled) return;
    _micros[section] = (_micros[section] ?? 0) + _watch.elapsedMicroseconds - begun;
    _calls[section] = (_calls[section] ?? 0) + 1;
  }

  /// Average milliseconds per call since the last report, then resets.
  static String report() {
    final out = [
      for (final k in _micros.keys)
        '$k ${(_micros[k]! / _calls[k]! / 1000).toStringAsFixed(2)}ms x${_calls[k]}'
    ].join(', ');
    _micros.clear();
    _calls.clear();
    return out;
  }
}
