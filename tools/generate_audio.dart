// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const sr = 44100;
final out = Directory('assets/audio');

double clamp(double x) => x.clamp(-1.0, 1.0);

void writeMono(File path, List<double> samples) {
  path.parent.createSync(recursive: true);
  final b = BytesBuilder();
  for (final s in samples) {
    final v = (clamp(s) * 32767).round();
    b.addByte(v & 0xff);
    b.addByte((v >> 8) & 0xff);
  }
  final data = b.toBytes();
  final header = _wavHeader(data.length, 1);
  path.writeAsBytesSync([...header, ...data]);
}

void writeStereo(File path, List<double> left, List<double> right) {
  path.parent.createSync(recursive: true);
  final n = min(left.length, right.length);
  final b = BytesBuilder();
  for (var i = 0; i < n; i++) {
    for (final s in [left[i], right[i]]) {
      final v = (clamp(s) * 32767).round();
      b.addByte(v & 0xff);
      b.addByte((v >> 8) & 0xff);
    }
  }
  final data = b.toBytes();
  final header = _wavHeader(data.length, 2);
  path.writeAsBytesSync([...header, ...data]);
}

List<int> _wavHeader(int dataLen, int channels) {
  final byteRate = sr * channels * 2;
  final blockAlign = channels * 2;
  final chunk = 36 + dataLen;
  return [
    ...'RIFF'.codeUnits,
    chunk & 0xff,
    (chunk >> 8) & 0xff,
    (chunk >> 16) & 0xff,
    (chunk >> 24) & 0xff,
    ...'WAVE'.codeUnits,
    ...'fmt '.codeUnits,
    16, 0, 0, 0,
    1, 0,
    channels, 0,
    sr & 0xff,
    (sr >> 8) & 0xff,
    (sr >> 16) & 0xff,
    (sr >> 24) & 0xff,
    byteRate & 0xff,
    (byteRate >> 8) & 0xff,
    (byteRate >> 16) & 0xff,
    (byteRate >> 24) & 0xff,
    blockAlign, 0,
    16, 0,
    ...'data'.codeUnits,
    dataLen & 0xff,
    (dataLen >> 8) & 0xff,
    (dataLen >> 16) & 0xff,
    (dataLen >> 24) & 0xff,
  ];
}

double sine(double f, double t, [double phase = 0]) => sin(2 * pi * f * t + phase);

double softPad(double f, double t, [double vol = 1]) =>
    vol * (0.55 * sine(f, t) + 0.25 * sine(f * 2.01, t, 0.3) + 0.12 * sine(f * 3.02, t, 0.7));

List<List<double>> genMenu([double seconds = 24]) {
  final n = (seconds * sr).round();
  final left = List<double>.filled(n, 0);
  final right = List<double>.filled(n, 0);
  final rng = Random(42);
  final prog = [
    [220.0, 261.63, 329.63],
    [174.61, 220.0, 261.63],
    [261.63, 329.63, 392.0],
    [196.0, 246.94, 293.66],
  ];
  const bar = 2.0;
  var lpL = 0.0, lpR = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final chord = prog[(t / bar).floor() % 4];
    final local = (t % bar) / bar;
    final swell = 0.5 + 0.5 * sin(pi * local);
    var pad = 0.0;
    for (final f in chord) {
      pad += softPad(f, t, 0.14 / chord.length);
    }
    pad *= swell;
    final sub = 0.08 * sine(chord[0] / 2, t) * swell;
    final shimmer = 0.025 * sine(880 + 40 * sin(t * 0.2), t);
    final beat = (t * (72 / 60)) % 1.0;
    var hat = 0.0;
    if (beat < 0.04 || (beat >= 0.5 && beat < 0.54)) {
      hat = 0.035 * (1 - (beat % 0.04) / 0.04) * (rng.nextDouble() * 2 - 1);
    }
    final sample = (pad + sub + shimmer + hat) * 0.85;
    final pan = 0.15 * sin(t * 0.07);
    lpL = lpL * 0.92 + sample * (1 - pan) * 0.08;
    lpR = lpR * 0.92 + sample * (1 + pan) * 0.08;
    left[i] = lpL;
    right[i] = lpR;
  }
  final fade = (0.8 * sr).round();
  for (var i = 0; i < fade; i++) {
    final f = i / fade;
    left[i] *= f;
    right[i] *= f;
    left[n - 1 - i] *= f;
    right[n - 1 - i] *= f;
  }
  return [left, right];
}

List<List<double>> genGameplay([double seconds = 22]) {
  final n = (seconds * sr).round();
  final left = List<double>.filled(n, 0);
  final right = List<double>.filled(n, 0);
  final rng = Random(7);
  final prog = [
    [246.94, 311.13, 369.99],
    [220.0, 277.18, 329.63],
    [293.66, 369.99, 440.0],
    [261.63, 329.63, 392.0],
  ];
  const bar = 1.5;
  var lpL = 0.0, lpR = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final chord = prog[(t / bar).floor() % 4];
    final local = (t % bar) / bar;
    final swell = 0.45 + 0.55 * pow(sin(pi * local), 0.8);
    var pad = 0.0;
    for (final f in chord) {
      pad += softPad(f, t, 0.11 / chord.length);
    }
    pad *= swell;
    final pulse = 0.06 * sine(chord[0] / 2, t) * (0.6 + 0.4 * sin(t * 4));
    final beat = (t * (88 / 60)) % 1.0;
    var hat = 0.0;
    if (beat < 0.035) {
      hat = 0.05 * (1 - beat / 0.035) * (rng.nextDouble() * 2 - 1);
    }
    final arp = 0.04 * sine(chord[1] * 2, t * 2 + local * 2);
    final sample = (pad + pulse + hat + arp) * 0.9;
    final pan = 0.22 * sin(t * 0.11 + 1);
    lpL = lpL * 0.88 + sample * (1 - pan) * 0.12;
    lpR = lpR * 0.88 + sample * (1 + pan) * 0.12;
    left[i] = lpL;
    right[i] = lpR;
  }
  final fade = (0.6 * sr).round();
  for (var i = 0; i < fade; i++) {
    final f = i / fade;
    left[i] *= f;
    right[i] *= f;
    left[n - 1 - i] *= f;
    right[n - 1 - i] *= f;
  }
  return [left, right];
}

List<double> toneBurst(double freq, double dur, double vol, double decay) {
  final n = (dur * sr).round();
  return [for (var i = 0; i < n; i++) vol * exp(-decay * i / sr) * sine(freq, i / sr)];
}

List<double> noiseBurst(double dur, double vol, double decay, [int seed = 99]) {
  final rng = Random(seed);
  final n = (dur * sr).round();
  var lp = 0.0;
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    lp = lp * 0.85 + (rng.nextDouble() * 2 - 1) * 0.15;
    out.add(vol * exp(-decay * t) * lp);
  }
  return out;
}

List<double> mix(List<List<double>> tracks) {
  final n = tracks.map((e) => e.length).reduce(max);
  return [
    for (var i = 0; i < n; i++)
      tracks.fold<double>(0, (a, t) => a + (i < t.length ? t[i] : 0))
  ];
}

Map<String, List<double> Function()> sfx = {
  'tap': () => mix([toneBurst(920, 0.05, 0.35, 35), toneBurst(480, 0.04, 0.2, 40)]),
  'tick': () => toneBurst(1200, 0.03, 0.25, 50),
  'success': () => mix([
        toneBurst(523.25, 0.12, 0.3, 6),
        toneBurst(659.25, 0.14, 0.28, 5),
        toneBurst(783.99, 0.18, 0.25, 4),
      ]),
  'win': () => mix([
        toneBurst(523.25, 0.15, 0.32, 3.5),
        toneBurst(659.25, 0.15, 0.28, 3.5),
        toneBurst(783.99, 0.2, 0.25, 3),
        toneBurst(1046.5, 0.35, 0.22, 2.5),
      ]),
  'lose': () => mix([toneBurst(392, 0.25, 0.35, 4), toneBurst(311, 0.35, 0.3, 3)]),
  'ball_hit': () => mix([noiseBurst(0.08, 0.45, 18), toneBurst(180, 0.06, 0.35, 25)]),
  'cue_hit': () => mix([toneBurst(320, 0.04, 0.4, 30), noiseBurst(0.03, 0.15, 40)]),
  'cushion': () => mix([noiseBurst(0.06, 0.35, 15), toneBurst(140, 0.05, 0.25, 20)]),
  'pocket': () => mix([toneBurst(220, 0.2, 0.4, 5), noiseBurst(0.1, 0.25, 10)]),
  'card': () => mix([noiseBurst(0.05, 0.3, 25), toneBurst(640, 0.06, 0.2, 20)]),
  'foul': () => mix([toneBurst(180, 0.2, 0.4, 5), toneBurst(150, 0.25, 0.35, 4)]),
  'extra': () => toneBurst(880, 0.15, 0.35, 8),
  'turn': () => toneBurst(660, 0.1, 0.28, 10),
  'match_start': () => mix([
        toneBurst(440, 0.2, 0.3, 4),
        toneBurst(554.37, 0.2, 0.28, 4),
        toneBurst(659.25, 0.35, 0.32, 3),
      ]),
  'dice_roll': () {
    final rng = Random(1);
    final n = (0.35 * sr).round();
    var lp = 0.0;
    return [
      for (var i = 0; i < n; i++)
        () {
          final t = i / sr;
          lp = lp * 0.7 + (rng.nextDouble() * 2 - 1) * 0.3;
          return 0.35 * lp * (0.5 + 0.5 * sin(t * 40));
        }()
    ];
  },
  'dice_land': () => mix([toneBurst(400, 0.08, 0.35, 12), noiseBurst(0.04, 0.2, 25)]),
  'hop': () => toneBurst(520, 0.06, 0.3, 18),
  'token_out': () => mix([toneBurst(600, 0.1, 0.32, 8), toneBurst(800, 0.12, 0.25, 7)]),
  'capture': () => mix([toneBurst(180, 0.2, 0.4, 5), toneBurst(150, 0.25, 0.35, 4), toneBurst(300, 0.15, 0.25, 6)]),
  'token_home': () => mix([
        toneBurst(523.25, 0.12, 0.3, 6),
        toneBurst(659.25, 0.14, 0.28, 5),
        toneBurst(783.99, 0.18, 0.25, 4),
      ]),
  'no_move': () => toneBurst(220, 0.18, 0.3, 6),
  'chat_pop': () => toneBurst(740, 0.07, 0.28, 15),
};

void main() {
  out.createSync(recursive: true);
  print('BGM...');
  final menu = genMenu();
  writeStereo(File('${out.path}/bgm_menu.wav'), menu[0], menu[1]);
  final game = genGameplay();
  writeStereo(File('${out.path}/bgm_gameplay.wav'), game[0], game[1]);
  print('SFX...');
  for (final e in sfx.entries) {
    writeMono(File('${out.path}/${e.key}.wav'), e.value());
    print('  ${e.key}.wav');
  }
  print('Done: ${sfx.length + 2} files');
}
