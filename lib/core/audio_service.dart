import 'package:audioplayers/audioplayers.dart';

enum Sfx {
  ballHit, cueHit, cushion, pocket, card, tick, foul, success, extra, win, turn, tap, matchStart,
  // Ludo
  diceRoll, diceLand, hop, tokenOut, capture, tokenHome, noMove, chatPop, lose,
}

/// Background music beds (looped).
enum Bgm { menu, gameplay }

extension on Sfx {
  String get file => switch (this) {
        Sfx.ballHit => 'ball_hit',
        Sfx.cueHit => 'cue_hit',
        Sfx.cushion => 'cushion',
        Sfx.pocket => 'pocket',
        Sfx.card => 'card',
        Sfx.tick => 'tick',
        Sfx.foul => 'foul',
        Sfx.success => 'success',
        Sfx.extra => 'extra',
        Sfx.win => 'win',
        Sfx.turn => 'turn',
        Sfx.tap => 'tap',
        Sfx.matchStart => 'match_start',
        Sfx.diceRoll => 'dice_roll',
        Sfx.diceLand => 'dice_land',
        Sfx.hop => 'hop',
        Sfx.tokenOut => 'token_out',
        Sfx.capture => 'capture',
        Sfx.tokenHome => 'token_home',
        Sfx.noMove => 'no_move',
        Sfx.chatPop => 'chat_pop',
        Sfx.lose => 'lose',
      };
}

class AudioService {
  AudioService({this.enabled = true});

  /// The app's player, for widgets that only need a button sound.
  static AudioService? instance;

  /// Button touch — use on every tappable control.
  static void tap() => instance?.play(Sfx.tap, volume: 0.75);

  bool enabled;

  static const _poolSize = 8;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  final Map<Sfx, DateTime> _lastPlayed = {};

  final List<AudioPlayer> _loaded = [];
  bool _warm = false;

  AudioPlayer? _music;
  Bgm? _musicTrack;

  /// Game sounds mix with each other and with the user's music app.
  static final AudioContext _context = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

  Future<void> warmUp() async {
    if (_warm) return;
    _warm = true;
    try {
      await AudioPlayer.global.setAudioContext(_context);
    } catch (_) {
      // Older platforms: keep the default context.
    }
    for (final sfx in Sfx.values) {
      try {
        final player = AudioPlayer()..positionUpdater = null;
        _loaded.add(player);
        await player.setAudioContext(_context);
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setSource(AssetSource('audio/${sfx.file}.wav'));
      } catch (_) {
        // Loads on first use instead.
      }
    }
  }

  void play(Sfx sfx, {double volume = 1}) {
    if (!enabled) return;
    final now = DateTime.now();
    final last = _lastPlayed[sfx];
    if (last != null && now.difference(last).inMilliseconds < 40) return;
    _lastPlayed[sfx] = now;
    try {
      if (_pool.length < _poolSize) {
        final player = AudioPlayer()..positionUpdater = null;
        player.setAudioContext(_context).catchError((_) {});
        _pool.add(player);
      }
      final player = _pool[_next++ % _pool.length];
      player
          .play(AssetSource('audio/${sfx.file}.wav'),
              volume: volume.clamp(0.0, 1.0), mode: PlayerMode.lowLatency)
          .catchError((_) {});
    } catch (_) {}
  }

  /// Soft lobby / shop bed. Idempotent — safe to call when a route becomes visible.
  Future<void> playMenuMusic({double? volume}) => playBgm(Bgm.menu, volume: volume);

  /// Match bed — pool, ludo, carrom, poker practice.
  Future<void> playGameplayMusic({double? volume}) => playBgm(Bgm.gameplay, volume: volume);

  Future<void> playBgm(Bgm track, {double? volume}) async {
    // Lobby and match beds stay off. Button taps still play.
  }

  Future<void> stopMusic() async {
    _musicTrack = null;
    try {
      await _music?.stop();
    } catch (_) {}
  }

  /// When sound is toggled off in settings, pause everything; restore last bed when on.
  set soundEnabled(bool on) {
    enabled = on;
    if (!on) {
      stopMusic();
    } else if (_musicTrack != null) {
      final t = _musicTrack!;
      _musicTrack = null;
      playBgm(t);
    }
  }

  void dispose() {
    stopMusic();
    _music?.dispose().catchError((_) {});
    _music = null;
    for (final p in [..._pool, ..._loaded]) {
      p.dispose().catchError((_) {});
    }
    _pool.clear();
    _loaded.clear();
  }
}
