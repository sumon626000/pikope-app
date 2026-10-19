import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/audio_service.dart';
import '../../data/match_bet.dart';
import '../../game/carrom/carrom_bot.dart';
import '../../game/carrom/carrom_physics.dart';
import '../../game/carrom/carrom_rules.dart';
import '../../game/physics/vec2.dart';
import '../game/game_controller.dart' show SeatConfig;
import '../online/game_link.dart';
import 'carrom_skins.dart';

/// Quick-chat presets; only the index travels over the network.
const carromChatPresets = ['GOOD LUCK!', 'NICE SHOT', 'HAHA', 'OH NO!', 'WELL PLAYED', 'HURRY UP'];

class CarromMatchConfig {
  const CarromMatchConfig({required this.seats, this.shotSeconds = 30, this.seed, this.bet = const MatchBet(), this.strikerSkin = 'classic', this.pieceSkin = 'classic', this.boardSkin = 'classic'});

  final List<SeatConfig> seats;
  final int shotSeconds;
  final int? seed;
  final MatchBet bet;

  /// Looks picked in the lobby (ids from carrom_skins.dart).
  final String strikerSkin;
  final String pieceSkin;
  final String boardSkin;
}

/// A piece dropping into a pocket (drawn shrinking for a moment).
class SinkingDisc {
  const SinkingDisc(this.disc, this.at, this.pocket, this.start);

  final int disc;
  final Vec2 at;
  final int pocket;
  final double start;
  static const seconds = 0.35;
}

/// Short message over the board.
class CarromToast {
  const CarromToast(this.lines, this.good, this.seconds);

  final List<String> lines;

  /// true: something went right for the viewer; false: a foul / bad news.
  final bool? good;
  final double seconds;
}

/// Drives one carrom match: offline (bot opponent, rules applied here) or
/// online (the server simulates and rules; this device animates the same
/// stroke from the same numbers and shows the server's ruling).
class CarromController extends ChangeNotifier {
  CarromController(this.config, this.audio, {this.link})
      : _random = config.seed == null ? Random.secure() : Random(config.seed) {
    state = CarromState(
      players: [
        for (var i = 0; i < 2; i++)
          CarromPlayer(name: config.seats[i].name, avatar: config.seats[i].avatar, colour: i, isBot: config.seats[i].isBot, cue: config.seats[i].cue),
      ],
      turn: _random.nextInt(2),
      shotSeconds: config.shotSeconds,
    );
    _bot = CarromBot(_random, skill: config.seats.length > 1 ? config.seats[1].botSkill : 0.6);
    if (!online) {
      world.setDiscs(CarromWorld.opening());
      presenting = true;
      _toast(CarromToast(['CARROM', '${state.current.name} BREAKS'], null, 1.8));
      _after(2.0, _beginTurn);
    }
    audio.play(Sfx.matchStart, volume: 0.8);
  }

  final CarromMatchConfig config;
  final AudioService audio;
  final OnlineGameDriver? link;
  final Random _random;
  late final CarromBot _bot;

  final CarromWorld world = CarromWorld();
  late final CarromState state;
  late final StrikerSkin strikerSkin = strikerSkinOf(config.strikerSkin);
  late final PieceSkin pieceSkin = pieceSkinOf(config.pieceSkin);
  late final BoardSkin boardSkin = boardSkinOf(config.boardSkin);

  /// Bumps every tick so painters repaint; [clock] is the seconds left.
  final ValueNotifier<int> frame = ValueNotifier(0);
  final ValueNotifier<double> clock = ValueNotifier(0);

  bool get online => link != null;
  int get mySeat => online ? link!.seat : 0;
  bool get over => state.phase == CarromPhase.gameOver;
  int get turn => state.turn;
  CarromPlayer get current => state.current;

  /// Seat 1 looks at the board from the far side.
  bool get viewRotated => mySeat == 1;

  // ---- what the viewer sees ------------------------------------------------

  bool shooting = false;
  bool presenting = true;
  final List<SinkingDisc> sinking = [];
  CarromToast? toast;
  double _toastUntil = 0;

  /// Striker position on the current shooter's base line (while placing / aiming).
  double strikerX = 500;

  /// Aim while the striker is being pulled back; null when idle.
  Vec2? aimDir;
  double power = 0;

  /// Seat whose striker is shown on its base line (null: no striker on board).
  int? get strikerSeat => shooting || over || presenting ? null : turn;

  bool get _myTurnOnline => !online || turn == mySeat;
  bool get isHumanTurn => !current.isBot && !presenting && !shooting && _myTurnOnline && !over;
  bool get canAim => isHumanTurn;

  String get hint {
    if (over) return '';
    if (presenting || shooting) return '';
    if (!isHumanTurn) return '${current.name.toUpperCase()} IS AIMING...';
    if (state.queenPending == turn) return 'COVER THE QUEEN - POCKET ONE OF YOURS';
    return aimDir == null ? 'SLIDE THE STRIKER, THEN DRAG BACK TO SHOOT' : 'RELEASE TO SHOOT';
  }

  double _time = 0;

  /// Seconds since the match opened (for painters).
  double get frameTime => _time;
  double _accumulator = 0;
  final List<({double at, VoidCallback run})> _schedule = [];
  bool _disposed = false;
  int _lastTick = -1;

  void _after(double seconds, VoidCallback run) => _schedule.add((at: _time + seconds, run: run));

  void _toast(CarromToast t) {
    toast = t;
    _toastUntil = _time + t.seconds;
    notifyListeners();
  }

  // ---- chat ------------------------------------------------------------------

  final Map<int, (int, double)> _chats = {};

  int? chatOf(int seat) {
    final c = _chats[seat];
    return c != null && c.$2 > _time ? c.$1 : null;
  }

  void showChat(int seat, int message) {
    if (message < 0 || message >= carromChatPresets.length) return;
    _chats[seat] = (message, _time + 2.8);
    audio.play(Sfx.chatPop, volume: 0.8);
    notifyListeners();
  }

  void sayChat(int message) {
    showChat(mySeat, message);
    link?.sendChat(message);
    if (!online && _random.nextDouble() < 0.6) {
      _after(1.0 + _random.nextDouble(), () => showChat(1, _random.nextInt(carromChatPresets.length)));
    }
  }

  // ---- turn ------------------------------------------------------------------

  void _beginTurn() {
    presenting = false;
    shooting = false;
    power = 0;
    aimDir = null;
    _plan = null;
    _botStroke = null;
    clock.value = state.shotSeconds.toDouble();
    _lastTick = -1;
    if (over) {
      notifyListeners();
      return;
    }
    strikerX = _freeStrikerX(turn, 500);
    if (online) {
      _stage = _NetStage.idle;
      _remoteAim = null;
      if (_myTurnOnline) audio.play(Sfx.turn, volume: 0.5);
      notifyListeners();
      _pump();
      return;
    }
    audio.play(Sfx.turn, volume: 0.5);
    if (current.isBot) {
      _after(0.9, () {
        if (!over && current.isBot && !presenting) _plan = _bot.startPlan(world, state, turn);
      });
    }
    notifyListeners();
  }

  double _freeStrikerX(int seat, double wanted) {
    if (world.strikerFits(seat, wanted)) return wanted;
    for (var off = 2.0; off < 600; off += 2) {
      for (final x in [wanted + off, wanted - off]) {
        if (x >= CarromWorld.baseMinX && x <= CarromWorld.baseMaxX && world.strikerFits(seat, x)) return x;
      }
    }
    return wanted;
  }

  // ---- human input -----------------------------------------------------------

  /// Slides the striker along the base line (snaps clear of pieces).
  void setStrikerX(double x) {
    if (!canAim || aimDir != null) return;
    final cx = x.clamp(CarromWorld.baseMinX, CarromWorld.baseMaxX).toDouble();
    strikerX = world.strikerFits(turn, cx) ? cx : _freeStrikerX(turn, cx);
    notifyListeners();
  }

  /// Pulling the striker back: [pull] is the drag vector in board units.
  void updateAim(Vec2 pull) {
    if (!canAim) return;
    final len = pull.length;
    if (len < 6) {
      aimDir = null;
      power = 0;
      notifyListeners();
      return;
    }
    // Slingshot: the striker flies opposite to the pull. Any direction is
    // allowed, as in Carrom Pool: shots toward your own base line rebound
    // off the cushion.
    aimDir = (pull * -1).normalized;
    power = ((len - 6) / 230).clamp(0.0, 1.0);
    notifyListeners();
  }

  void releaseShot() {
    if (!canAim) return;
    final dir = aimDir;
    if (dir == null || power < 0.04) {
      aimDir = null;
      power = 0;
      notifyListeners();
      return;
    }
    if (power < 0.1) power = 0.1;
    _shoot(dir, power);
  }

  void cancelAim() {
    aimDir = null;
    power = 0;
    notifyListeners();
  }

  // ---- bot ---------------------------------------------------------------------

  CarromBotPlan? _plan;
  CarromBotShot? _botStroke;
  double _botStart = 0;
  double _botFromX = 0;

  void _tickPlan() {
    final plan = _plan;
    if (plan == null) return;
    final watch = Stopwatch()..start();
    while (!plan.done && watch.elapsedMicroseconds < 4000) {
      plan.step();
    }
    if (!plan.done) return;
    _plan = null;
    _botStroke = plan.result;
    _botStart = _time;
    _botFromX = strikerX;
  }

  void _tickBotStroke() {
    final shot = _botStroke;
    if (shot == null) return;
    const slideSeconds = 0.7, aimSeconds = 0.6, pullSeconds = 0.5;
    final t = _time - _botStart;
    if (t < slideSeconds) {
      final k = t / slideSeconds;
      strikerX = _botFromX + (shot.x - _botFromX) * (k * k * (3 - 2 * k));
    } else if (t < slideSeconds + aimSeconds) {
      strikerX = shot.x;
      aimDir = shot.dir;
      power = 0;
    } else if (t < slideSeconds + aimSeconds + pullSeconds) {
      aimDir = shot.dir;
      power = shot.power * (t - slideSeconds - aimSeconds) / pullSeconds;
    } else {
      _botStroke = null;
      _shoot(shot.dir, shot.power);
    }
  }

  // ---- the stroke --------------------------------------------------------------

  void _shoot(Vec2 dir, double strength) {
    strikerX = world.placeStriker(turn, strikerX);
    link?.send({'type': 'shoot', 'x': strikerX, 'dirX': dir.x, 'dirY': dir.y, 'power': strength});
    if (online) _stage = _NetStage.animatingOwn;
    world.shoot(dir, strength);
    shooting = true;
    aimDir = null;
    power = 0;
    audio.play(Sfx.cueHit, volume: 0.4 + strength * 0.6);
    _accumulator = 0;
    notifyListeners();
  }

  void _finishShot() {
    shooting = false;
    if (online) {
      presenting = true;
      notifyListeners();
      final replayed = _replaying;
      _replaying = null;
      if (_stage == _NetStage.animatingReplay && replayed != null) {
        _presentEvent(replayed);
      } else {
        _stage = _NetStage.waitingOwn;
        _pump();
      }
      return;
    }
    final seat = turn;
    final r = CarromRules.resolve(state, world, seat);
    _present(r, seat);
  }

  void _timeout() {
    _plan = null;
    _botStroke = null;
    final seat = turn;
    final r = CarromRules.timeout(state, world);
    _present(r, seat);
  }

  bool _isMe(int seat) => online ? seat == mySeat : !state.players[seat].isBot;

  void _present(CarromShotResult r, int shooter) {
    presenting = true;
    power = 0;
    aimDir = null;
    final name = state.players[shooter].name.toUpperCase();
    final next = state.players[r.nextPlayer].name.toUpperCase();
    final me = _isMe(shooter);
    if (r.winner != null) {
      audio.play(_isMe(r.winner!) ? Sfx.win : Sfx.lose);
      _schedule.clear();
      notifyListeners();
      return;
    }
    var hold = 1.3;
    if (r.timeout) {
      _toast(CarromToast(['TIME OUT', 'NEXT: $next'], me ? false : null, 1.6));
      hold = 1.8;
    } else if (r.foul) {
      audio.play(Sfx.foul);
      _toast(CarromToast([
        'STRIKER POCKETED - FOUL',
        if (r.penalty != null) 'ONE PIECE BACK ON THE BOARD',
        'NEXT: $next',
      ], me ? false : true, 2.2));
      hold = 2.4;
    } else if (r.lastPieceReturned) {
      audio.play(Sfx.foul);
      _toast(CarromToast(['TAKE THE QUEEN FIRST!', 'LAST PIECE BACK ON THE BOARD', r.extraTurn ? '$name SHOOTS AGAIN' : 'NEXT: $next'], me ? false : true, 2.2));
      hold = 2.4;
    } else if (r.queenCovered) {
      audio.play(Sfx.success);
      _toast(CarromToast(['QUEEN COVERED!', '$name SHOOTS AGAIN'], me, 1.6));
      hold = 1.8;
    } else if (r.queenPending) {
      audio.play(Sfx.success);
      _toast(CarromToast(['QUEEN!', 'COVER HER WITH ONE OF YOURS'], me, 1.6));
      hold = 1.8;
    } else if (r.queenReturned) {
      audio.play(Sfx.noMove, volume: 0.7);
      _toast(CarromToast(['QUEEN NOT COVERED', 'SHE RETURNS TO THE CENTRE', 'NEXT: $next'], me ? false : true, 2.0));
      hold = 2.2;
    } else if (r.extraTurn) {
      audio.play(Sfx.success);
      final n = r.pocketed.where((d) => CarromWorld.colourOf(d) == state.players[shooter].colour).length;
      _toast(CarromToast([n > 1 ? '$n PIECES POCKETED' : 'PIECE POCKETED', '$name SHOOTS AGAIN'], me, 1.3));
      hold = 1.5;
    } else if (r.pocketed.isNotEmpty) {
      _toast(CarromToast(['OPPONENT\'S PIECE POCKETED', 'NEXT: $next'], me ? false : true, 1.5));
      hold = 1.7;
    } else {
      _toast(CarromToast(['MISS', 'NEXT: $next'], null, 1.1));
    }
    _after(hold, _beginTurn);
    notifyListeners();
  }

  // ---- tick ----------------------------------------------------------------------

  void tick(double dt) {
    if (_disposed) return;
    dt = min(dt, 0.1);
    _time += dt;
    _tickAimSharing(dt);
    if (_previewing) {
      _tickPreview(dt);
      frame.value++;
      return;
    }
    while (_schedule.isNotEmpty) {
      final due = _schedule.where((s) => s.at <= _time).toList();
      if (due.isEmpty) break;
      due.sort((a, b) => a.at.compareTo(b.at));
      _schedule.remove(due.first);
      due.first.run();
    }
    sinking.removeWhere((d) => _time - d.start > SinkingDisc.seconds);
    if (toast != null && _time >= _toastUntil) {
      toast = null;
      notifyListeners();
    }
    if (_chats.isNotEmpty && _chats.values.any((c) => c.$2 <= _time)) {
      _chats.removeWhere((_, c) => c.$2 <= _time);
      notifyListeners();
    }
    if (shooting) {
      _accumulator += dt;
      while (_accumulator >= CarromWorld.fixedDt) {
        world.step();
        _accumulator -= CarromWorld.fixedDt;
      }
      for (final e in world.events) {
        switch (e.type) {
          case CarromEventType.hit:
            audio.play(Sfx.ballHit, volume: e.intensity);
          case CarromEventType.cushion:
            audio.play(Sfx.cushion, volume: e.intensity * 0.8);
          case CarromEventType.pocket:
            audio.play(Sfx.pocket);
            sinking.add(SinkingDisc(e.disc, e.at, e.pocket, _time));
        }
      }
      world.events.clear();
      if (!world.isMoving) _finishShot();
    } else if (!presenting && !over) {
      _tickPlan();
      _tickBotStroke();
      if (!shooting) {
        clock.value = max(0, clock.value - dt);
        final whole = clock.value.ceil();
        if (!current.isBot && _myTurnOnline && whole <= 5 && whole != _lastTick && whole > 0) {
          _lastTick = whole;
          audio.play(Sfx.tick);
        }
        if (clock.value <= 0 && !online) _timeout();
      }
    }
    frame.value++;
  }

  // ---- online ----------------------------------------------------------------------

  Map<String, dynamic>? _remote;
  int _serverOffsetMs = 0;
  bool _started = false;
  bool _overAnnounced = false;
  final List<Map<String, dynamic>> _events = [];
  int _lastQueuedResult = 0;
  static const _skipped = 'skippedRulings';
  _NetStage _stage = _NetStage.presenting;
  Map<String, dynamic>? _replaying;

  /// Newest view of the match from the server.
  void applyRemote(Map<String, dynamic> v, int serverNow) {
    if (_disposed || !online) return;
    _serverOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
    _remote = v;
    if (!_started) {
      _started = true;
      state.applyJson(v);
      world.setDiscs((v['discs'] as List).cast<List<dynamic>>());
      _lastQueuedResult = (v['lastResult'] as Map?)?['seq'] as int? ?? 0;
      presenting = true;
      _toast(CarromToast(['CARROM', '${current.name.toUpperCase()} BREAKS'], null, 1.8));
      _after(2.0, _beginTurn);
      notifyListeners();
      return;
    }
    final seq = (v['lastResult'] as Map?)?['seq'] as int? ?? 0;
    if (seq > _lastQueuedResult) {
      _events.add(seq == _lastQueuedResult + 1 ? v : {...v, _skipped: true});
      _lastQueuedResult = seq;
    }
    _pump();
  }

  void _syncClock(Map<String, dynamic> v) {
    final left = ((v['deadline'] as int) - DateTime.now().millisecondsSinceEpoch - _serverOffsetMs) / 1000;
    clock.value = left.clamp(0.0, state.shotSeconds.toDouble());
  }

  void _pump() {
    final latest = _remote;
    if (latest == null || !_started) return;
    if (_stage == _NetStage.waitingOwn) {
      if (_events.isNotEmpty) _presentEvent(_events.removeAt(0));
      return;
    }
    if (_stage != _NetStage.idle) return;
    if (_events.isEmpty) {
      final turnBefore = turn;
      state.applyJson(latest);
      _syncClock(latest);
      if (over && !_overAnnounced) {
        _overAnnounced = true;
        audio.play(_isMe(state.winner!) ? Sfx.win : Sfx.lose);
        _schedule.clear();
      } else if (turnBefore != turn) {
        strikerX = _freeStrikerX(turn, 500);
      }
      notifyListeners();
      return;
    }
    final e = _events.removeAt(0);
    final shot = e['lastShot'] as Map<String, dynamic>?;
    final result = e['lastResult'] as Map<String, dynamic>;
    final played = result['timeout'] != true && shot != null;
    if (!played || shot['by'] == mySeat || e[_skipped] == true) {
      _presentEvent(e);
      return;
    }
    // Physics is deterministic: replaying the stroke shows the same shot.
    final by = shot['by'] as int;
    strikerX = world.placeStriker(by, (shot['x'] as num).toDouble());
    final dir = Vec2((shot['dirX'] as num).toDouble(), (shot['dirY'] as num).toDouble());
    _armPreview(e, dir, (shot['power'] as num).toDouble());
  }

  bool _previewing = false;
  double _previewLeft = 0;
  Vec2? _previewDir;
  double _previewPower = 0;
  static const _previewHold = 1.05;

  /// Holds the striker on the shot line so the piece it will hit is visible.
  void _armPreview(Map<String, dynamic> e, Vec2 dir, double strength) {
    aimDir = dir;
    power = 0.12;
    _previewDir = dir;
    _previewPower = strength;
    _previewLeft = _previewHold;
    _previewing = true;
    presenting = false;
    shooting = false;
    _stage = _NetStage.animatingReplay;
    _replaying = e;
    notifyListeners();
  }

  void _tickPreview(double dt) {
    _previewLeft -= dt;
    final t = (1 - _previewLeft / _previewHold).clamp(0.0, 1.0);
    power = t < 0.4 ? 0.12 : _previewPower * ((t - 0.4) / 0.6);
    if (_previewLeft > 0) {
      notifyListeners();
      return;
    }
    _previewing = false;
    final dir = _previewDir ?? const Vec2(0, -1);
    final strength = _previewPower;
    shooting = true;
    aimDir = null;
    power = 0;
    world.shoot(dir, strength);
    audio.play(Sfx.cueHit, volume: 0.4 + strength * 0.6);
    _accumulator = 0;
    notifyListeners();
  }

  /// Largest distance between where this device's own simulation left a
  /// disc and where the server says it rests (diagnostic; expected 0).
  double replayDrift = 0;

  void _presentEvent(Map<String, dynamic> e) {
    final result = CarromShotResult.fromJson(e['lastResult'] as Map<String, dynamic>);
    _stage = _NetStage.presenting;
    final discs = (e['discs'] as List).cast<List<dynamic>>();
    if (!result.timeout && e[_skipped] != true) {
      for (var i = 1; i < CarromWorld.count; i++) {
        if (!(discs[i][2] as bool) && !world.gone[i] && !result.returned.contains(i)) {
          replayDrift = max(replayDrift, Vec2(world.x[i] - (discs[i][0] as num), world.y[i] - (discs[i][1] as num)).length);
        }
      }
    }
    state.applyJson(e);
    world.setDiscs(discs);
    state.lastResult = result;
    if (over) _overAnnounced = true;
    _present(result, result.player);
  }

  /// The server refused an action: drop whatever was assumed, show its state.
  void onActionRejected() {
    final v = _remote;
    if (!online || v == null || !_started) return;
    _stage = _NetStage.idle;
    _replaying = null;
    _previewing = false;
    presenting = false;
    shooting = false;
    power = 0;
    aimDir = null;
    state.applyJson(v);
    world.setDiscs((v['discs'] as List).cast<List<dynamic>>());
    _syncClock(v);
    notifyListeners();
  }

  // ---- opponent's striker (online) ------------------------------------------------

  bool get showRemoteStriker =>
      _previewing || (online && !_myTurnOnline && !presenting && !shooting && !over && _stage == _NetStage.idle && _events.isEmpty);

  Vec2? _remoteAim;
  double _aimShareIn = 0;
  String _aimShared = '';

  void applyRemoteAim(Map<String, dynamic> m) {
    if (_disposed || _previewing || !showRemoteStriker || m['s'] != turn) return;
    final a = (m['a'] as num?)?.toDouble(), p = (m['p'] as num?)?.toDouble(), x = (m['x'] as num?)?.toDouble();
    if (x != null && x.isFinite) strikerX = x.clamp(CarromWorld.baseMinX, CarromWorld.baseMaxX).toDouble();
    if (a == null || p == null || !a.isFinite) {
      _remoteAim = null;
      aimDir = null;
      power = 0;
      return;
    }
    _remoteAim = Vec2.fromAngle(a);
    aimDir ??= _remoteAim;
    power = p.clamp(0.0, 1.0);
  }

  void _tickAimSharing(double dt) {
    if (!online || _previewing) return;
    if (showRemoteStriker) {
      final target = _remoteAim;
      if (target != null) {
        final current = aimDir?.angle ?? target.angle;
        final diff = atan2(sin(target.angle - current), cos(target.angle - current));
        aimDir = Vec2.fromAngle(current + diff * min(1.0, dt * 14));
      }
      return;
    }
    if (!canAim) return;
    _aimShareIn -= dt;
    if (_aimShareIn > 0) return;
    final a = aimDir?.angle;
    final now = '${a?.toStringAsFixed(3)} ${power.toStringAsFixed(2)} ${strikerX.toStringAsFixed(1)}';
    if (now == _aimShared) return;
    _aimShared = now;
    _aimShareIn = 0.09;
    link!.sendAim({'a': a, 'p': power, 'x': strikerX});
  }

  @override
  void dispose() {
    _disposed = true;
    frame.dispose();
    clock.dispose();
    super.dispose();
  }
}

enum _NetStage { idle, animatingOwn, animatingReplay, waitingOwn, presenting }
