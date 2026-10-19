import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../core/audio_service.dart';
import '../../data/match_bet.dart';
import '../../game/ludo/ludo_bot.dart';
import '../../game/ludo/ludo_rules.dart';
import '../game/game_controller.dart' show SeatConfig;
import '../online/game_link.dart';
import 'ludo_board.dart';

/// Quick-chat presets; only the index travels over the network.
const ludoChatPresets = ['GOOD LUCK!', 'NICE MOVE', 'HAHA', 'OH NO!', 'WELL PLAYED', 'HURRY UP'];

class LudoMatchConfig {
  const LudoMatchConfig({required this.seats, required this.players, this.shotSeconds = 30, this.seed, this.bet = const MatchBet(), this.humanSeats = 1});

  final int seats;
  final List<SeatConfig> players;

  /// Each seat's colour (0 red,1 green,2 yellow,3 blue).
  final int shotSeconds;
  final int? seed;
  final MatchBet bet;

  /// Offline: how many seats are human (pass & play); the rest are bots.
  final int humanSeats;
}

/// Drives one Ludo match: offline (bots / pass & play, die rolled locally) or
/// online (the server rolls the die and rules; this mirrors its state).
class LudoController extends ChangeNotifier {
  LudoController(this.config, this.audio, {this.link, List<int>? colours})
      : _rng = config.seed == null ? Random.secure() : Random(config.seed) {
    final cols = colours ?? (config.seats == 2 ? const [0, 2] : const [0, 1, 2, 3]);
    if (online) {
      // State arrives from the server; start empty until the first view.
      _state = null;
    } else {
      _state = LudoState.initial([
        for (var i = 0; i < config.seats; i++)
          LudoPlayer(
            name: config.players[i].name,
            avatar: config.players[i].avatar,
            colour: cols[i],
            isBot: i >= config.humanSeats,
          ),
      ], config.shotSeconds);
      _snapshotPositions();
    }
  }

  final LudoMatchConfig config;
  final AudioService audio;
  final OnlineGameDriver? link;
  final Random _rng;

  bool get online => link != null;
  int get mySeat => online ? _mySeat : _localTurnSeat;
  int get activeSeat => _state?.turn ?? 0;
  int _mySeat = 0;

  LudoState? _state;
  LudoState? get state => _state;

  /// Offline pass & play: whose device-turn it is to act (the current human).
  int get _localTurnSeat => _state?.turn ?? 0;

  // ---- rendering positions (animated) -------------------------------------

  /// Current drawn centre (col,row) of every token, animated between cells.
  final Map<int, List<double>> _pos = {}; // key seat*4+token -> [col,row]
  int _lastSeq = 0;
  bool _disposed = false;

  // animation of one token move, hopping cell by cell along [_animPath]
  int? _animKey;
  List<double>? _animFrom;
  List<double>? _animTo;
  List<List<double>> _animPath = const [];
  int _animHop = 0;
  double _animT = 0;
  final List<_Capture> _captures = [];
  String? _pendingToast;

  /// Footprints along the latest moves, newest last.
  final List<LudoTrailMark> _trail = [];
  static const trailLife = 1.4;
  List<LudoTrailMark> get trail => _trail;
  double trailAlpha(LudoTrailMark m) => (1 - (_time - m.born) / trailLife).clamp(0.0, 1.0);

  /// Leaves a footprint on [cell] heading towards [next].
  void _footprint(List<double> cell, List<double> next) {
    final key = _animKey;
    if (key == null || _state == null) return;
    _trail.add(LudoTrailMark(cell[0], cell[1], _colour(key ~/ 4), atan2(next[1] - cell[1], next[0] - cell[0]), _time));
  }

  /// Dice: the value being shown, and a short roll animation.
  int? die;
  double _diceSpin = 0;
  bool get diceRolling => _diceSpin > 0;
  int _rollFace = 1;

  /// While a roll is being shown after the turn already passed (a dead roll),
  /// the dice stays on the roller's card with the rolled value.
  int? _diceSeat;
  int? _heldDie;
  int get diceSeat => _diceSeat ?? turn;
  int get diceFace => diceRolling ? _rollFace : (_heldDie ?? die ?? 1);

  /// Seconds since the match opened; ticks every frame (drives hint pulses).
  final ValueNotifier<double> clock = ValueNotifier(0);

  /// Short message over the board (no moves, capture, roll again...).
  String? toast;
  double _toastUntil = 0;

  void _toast(String text, [double seconds = 1.4]) {
    toast = text;
    _toastUntil = _time + seconds;
    notifyListeners();
  }

  /// Quick-chat bubbles: seat -> (preset index, shown until).
  final Map<int, (int, double)> _chats = {};

  /// The preset a seat is saying right now, if any.
  int? chatOf(int seat) {
    final c = _chats[seat];
    return c != null && c.$2 > _time ? c.$1 : null;
  }

  void showChat(int seat, int message) {
    if (message < 0 || message >= ludoChatPresets.length) return;
    _chats[seat] = (message, _time + 2.8);
    audio.play(Sfx.chatPop, volume: 0.8);
    notifyListeners();
  }

  /// The local player says a preset; offline a bot may answer.
  void sayChat(int message) {
    showChat(mySeatForChat, message);
    link?.sendChat(message);
    if (!online && _state != null && _rng.nextDouble() < 0.6) {
      final bots = [for (var i = 0; i < _state!.seats; i++) if (_state!.players[i].isBot) i];
      if (bots.isNotEmpty) {
        final seat = bots[_rng.nextInt(bots.length)];
        _after(1.0 + _rng.nextDouble(), () => showChat(seat, _rng.nextInt(ludoChatPresets.length)));
      }
    }
  }

  int get mySeatForChat => online ? _mySeat : 0;

  /// Online turn clock: local time the current turn runs out.
  int? _deadlineAt;

  /// Fraction of the turn time left (online only), else null.
  double? get turnLeft {
    final at = _deadlineAt, st = _state;
    if (!online || at == null || st == null || over || st.shotSeconds <= 0) return null;
    return ((at - DateTime.now().millisecondsSinceEpoch) / (st.shotSeconds * 1000)).clamp(0.0, 1.0);
  }

  /// Extra upward offset (cells) of a token while it hops.
  double liftOf(int seat, int token) => (seat * 4 + token) == _animKey ? sin(pi * _animT) * 0.3 : 0;

  /// Whether a seat is played by this device's human (for messages).
  bool _isMe(int seat) => online ? seat == _mySeat : !(_state?.players[seat].isBot ?? true);

  double _botCooldown = 0;
  bool _presenting = false;

  int get seats => _state?.seats ?? config.seats;
  bool get over => _state?.phase == LudoPhase.gameOver;
  int? get winner => _state?.winner;
  String? get winReason => _state?.winReason;
  int get turn => _state?.turn ?? 0;

  LudoPlayer? player(int seat) => (_state != null && seat < _state!.players.length) ? _state!.players[seat] : null;

  bool get _busy => _animKey != null || _captures.isNotEmpty || _presenting || diceRolling;
  bool get isMyTurn {
    final s = _state;
    if (s == null || s.phase != LudoPhase.playerTurn) return false;
    return online ? s.turn == _mySeat : !s.players[s.turn].isBot;
  }
  bool get canRoll => isMyTurn && _state!.mustRoll && !_busy && !(_state!.players[mySeat].out);
  List<int> get movable => (isMyTurn && !_state!.mustRoll && !_busy) ? (_state!.movable ?? const []) : const [];

  /// Human turn with exactly one movable token: play it automatically.
  void _autoMoveIfForced() {
    if (online) return;
    if (isMyTurn && !_state!.mustRoll && !_busy) {
      final m = _state!.movable ?? const [];
      if (m.length == 1) _after(0.25, () => moveToken(m.first));
    }
  }
  bool canMoveToken(int token) => movable.contains(token);

  /// Token render position (col,row) centre.
  List<double> tokenPos(int seat, int token) {
    final key = seat * 4 + token;
    return _pos[key] ?? LudoBoard.cellOf(_colour(seat), _state?.players[seat].tokens[token] ?? -1, token);
  }

  int _colour(int seat) => _state!.players[seat].colour;

  void _snapshotPositions() {
    if (_state == null) return;
    for (var s = 0; s < _state!.seats; s++) {
      for (var t = 0; t < 4; t++) {
        _pos[s * 4 + t] = List.of(LudoBoard.cellOf(_state!.players[s].colour, _state!.players[s].tokens[t], t));
      }
    }
  }

  // ---- online: reflect the server ----------------------------------------

  void applyRemote(Map<String, dynamic> view, int serverNow) {
    if (_disposed || !online) return;
    _mySeat = view['you'] as int? ?? 0;
    final fresh = LudoState.fromJson(view);
    final first = _state == null;
    final newSeq = (view['lastResult'] as Map?)?['seq'] as int? ?? 0;
    final deadline = view['deadline'];
    _deadlineAt = deadline is int ? DateTime.now().millisecondsSinceEpoch + (deadline - serverNow) : null;
    final lastRoll = view['lastRoll'] as Map<String, dynamic>?;
    final rollSeq = lastRoll?['seq'] as int? ?? 0;
    _state = fresh;
    die = fresh.die;
    if (first) {
      _snapshotPositions();
      _lastSeq = newSeq;
      _lastRollSeq = rollSeq;
      notifyListeners();
      return;
    }
    if (rollSeq > _lastRollSeq && lastRoll != null) {
      _lastRollSeq = rollSeq;
      _showRemoteRoll(lastRoll['seat'] as int, lastRoll['die'] as int, lastRoll['dead'] == true, lastRoll['three'] == true);
    }
    if (newSeq > _lastSeq && fresh.lastResult != null) {
      _lastSeq = newSeq;
      _present(fresh.lastResult!);
    } else {
      _snapshotPositions();
      notifyListeners();
    }
  }

  int _lastRollSeq = 0;

  /// Online: spin the dice on the roller's card, then show what came up.
  void _showRemoteRoll(int seat, int value, bool dead, bool threeSixes) {
    _diceSeat = seat;
    void settle() {
      if (dead) {
        _heldDie = value;
        if (seat == _mySeat) {
          _toast(threeSixes ? 'THREE SIXES - TURN LOST' : 'NO MOVES');
          audio.play(Sfx.noMove, volume: 0.7);
        }
        _presenting = true;
        _after(1.0, () {
          _presenting = false;
          _diceSeat = null;
          _heldDie = null;
          notifyListeners();
        });
      } else {
        _diceSeat = null;
        _heldDie = null;
      }
      notifyListeners();
    }

    if (diceRolling) {
      _afterSpin = settle;
    } else {
      _startDiceSpin(settle);
    }
  }

  void onActionRejected() {
    // The server refused (turn moved on, etc.); re-sync from its last view.
    if (online) _snapshotPositions();
    notifyListeners();
  }

  // ---- actions ------------------------------------------------------------

  void roll() {
    if (online) {
      if (canRoll) {
        _diceSeat = _mySeat;
        _startDiceSpin(() {
          _diceSeat = null;
          notifyListeners();
        });
        link!.send({'type': 'roll'});
      }
      return;
    }
    if (!canRoll) return;
    _doRollOffline();
  }

  /// Offline roll (human or bot): spin the dice, then apply a local value.
  void _doRollOffline() {
    final seat = _state!.turn;
    _diceSeat = seat;
    _startDiceSpin(() {
      final value = _rng.nextInt(6) + 1;
      final threeSixes = value == 6 && _state!.sixes == 2;
      final moves = LudoRules.roll(_state!, value);
      die = value;
      if (moves.isEmpty) {
        // Dead roll: keep the dice on the roller's card briefly, then move on.
        _heldDie = value;
        if (_isMe(seat)) {
          _toast(threeSixes ? 'THREE SIXES - TURN LOST' : 'NO MOVES');
          audio.play(Sfx.noMove, volume: 0.7);
        }
        _presenting = true;
        _after(1.0, () {
          _presenting = false;
          _diceSeat = null;
          _heldDie = null;
          die = null;
          _afterTurnChanged();
          notifyListeners();
        });
        notifyListeners();
      } else {
        _diceSeat = null;
        if (_isMe(seat) && moves.length > 1) _toast('TAP A TOKEN TO MOVE', 1.2);
        notifyListeners();
        _maybeBotMove();
        _autoMoveIfForced();
      }
    });
  }

  void moveToken(int token) {
    if (online) {
      if (movable.contains(token)) link!.send({'type': 'move', 'token': token});
      return;
    }
    if (!canMoveToken(token)) return;
    _doMoveOffline(token);
  }

  void _doMoveOffline(int token) {
    final seat = _state!.turn;
    final fromStep = _state!.players[seat].tokens[token];
    final result = LudoRules.move(_state!, token);
    _presentOffline(seat, token, fromStep, result);
  }

  /// Cell centres a token passes through from [from] to [to] (one per hop).
  bool _fromYard = false;

  List<List<double>> _hops(int colour, int from, int to, int token) {
    _fromYard = from == -1;
    if (from == -1 || to < from) return [LudoBoard.cellOf(colour, to, token)];
    return [for (var st = from + 1; st <= to; st++) LudoBoard.cellOf(colour, st, token)];
  }

  String? _messageFor(int seat, List<int> captured, bool finished, bool extra) {
    if (_isMe(seat)) {
      if (captured.isNotEmpty) return 'CAPTURED! ROLL AGAIN';
      if (finished) return 'TOKEN HOME! ROLL AGAIN';
      if (extra) return 'ROLL AGAIN';
      return null;
    }
    if (captured.any((enc) => _isMe(enc ~/ 4))) return 'YOUR TOKEN WAS CAPTURED';
    return null;
  }

  // ---- presentation / animation ------------------------------------------

  void _present(LudoResult r) {
    // Online: animate the moved token and any captures using the new state.
    die = r.die;
    final seat = r.player;
    final key = seat * 4 + r.token;
    final from = _pos[key] ?? LudoBoard.cellOf(_colour(seat), r.from, r.token);
    final to = LudoBoard.cellOf(_colour(seat), r.to, r.token);
    for (final enc in r.captured) {
      final cs = enc ~/ 4, ct = enc % 4;
      _captures.add(_Capture(cs * 4 + ct, _pos[cs * 4 + ct] ?? to, LudoBoard.cellOf(_colour(cs), -1, ct)));
    }
    _pendingToast = _state!.phase == LudoPhase.gameOver ? null : _messageFor(seat, r.captured, r.finishedToken, r.extraTurn);
    _animateMove(key, from, _hops(_colour(seat), r.from, r.to, r.token));
  }

  void _presentOffline(int seat, int token, int fromStep, LudoMove m) {
    final p = _state!.players[seat];
    final key = seat * 4 + token;
    final from = _pos[key]!;
    for (final enc in m.captured) {
      final cs = enc ~/ 4, ct = enc % 4;
      _captures.add(_Capture(cs * 4 + ct, _pos[cs * 4 + ct]!, LudoBoard.cellOf(_state!.players[cs].colour, -1, ct)));
    }
    _pendingToast = m.won ? null : _messageFor(seat, m.captured, m.finished, m.extraTurn);
    _animateMove(key, from, _hops(p.colour, fromStep, p.tokens[token], token));
  }

  void _animateMove(int key, List<double> from, List<List<double>> path) {
    _animKey = key;
    _animFrom = from;
    _animPath = path;
    _animHop = 0;
    _animTo = path.first;
    _animT = 0;
    // Leaving the yard is a slide; on the track the start cell gets a print.
    if (path.length > 1) _footprint(from, path.first);
    audio.play(path.length == 1 && _fromYard ? Sfx.tokenOut : Sfx.hop, volume: 0.7);
    notifyListeners();
  }

  void _finishMove() {
    final moved = _animKey;
    final reachedHome = moved != null && _state != null && _state!.players[moved ~/ 4].tokens[moved % 4] == LudoRules.homeStep;
    if (_animKey != null) {
      _pos[_animKey!] = List.of(_animTo!);
      _animKey = null;
      _animFrom = null;
      _animTo = null;
    }
    if (_captures.isNotEmpty) {
      audio.play(Sfx.capture, volume: 0.9);
      for (final c in _captures) {
        _pos[c.key] = List.of(c.to);
      }
      _captures.clear();
    }
    _snapshotPositions();
    if (over) {
      final w = winner;
      audio.play(w != null && _isMe(w) ? Sfx.win : Sfx.lose);
      notifyListeners();
      return;
    }
    if (reachedHome) audio.play(Sfx.tokenHome, volume: 0.85);
    if (_pendingToast != null) {
      _toast(_pendingToast!);
      _pendingToast = null;
    }
    die = _state!.die; // null unless an extra roll is due
    if (!online) {
      // Offline: continue the turn (same player on an extra roll, else next).
      _afterTurnChanged();
    }
    notifyListeners();
  }

  void _afterTurnChanged() {
    if (over) return;
    _maybeBotRoll();
  }

  // ---- offline bots -------------------------------------------------------

  void _maybeBotRoll() {
    if (online || over) return;
    final seat = _state!.turn;
    if (_state!.players[seat].isBot && _state!.mustRoll) {
      _botCooldown = 0.6;
    }
  }

  void _maybeBotMove() {
    if (online || over) return;
    final seat = _state!.turn;
    if (_state!.players[seat].isBot && !_state!.mustRoll) {
      _botCooldown = 0.5;
    }
  }

  void _startDiceSpin(VoidCallback then) {
    _diceSpin = 0.6;
    audio.play(Sfx.diceRoll, volume: 0.9);
    _afterSpin = then;
    notifyListeners();
  }

  VoidCallback? _afterSpin;

  // ---- ticker -------------------------------------------------------------

  final List<_Timer> _timers = [];
  double _time = 0;

  void _after(double seconds, VoidCallback run) => _timers.add(_Timer(_time + seconds, run));

  void tick(double dt) {
    if (_disposed) return;
    _time += dt;
    clock.value = _time;
    if (_trail.isNotEmpty && _time - _trail.first.born > trailLife) {
      _trail.removeWhere((m) => _time - m.born > trailLife);
    }
    if (toast != null && _time >= _toastUntil) {
      toast = null;
      notifyListeners();
    }
    if (_chats.isNotEmpty && _chats.values.any((c) => c.$2 <= _time)) {
      _chats.removeWhere((_, c) => c.$2 <= _time);
      notifyListeners();
    }
    for (final t in _timers.where((t) => t.at <= _time).toList()) {
      _timers.remove(t);
      t.run();
    }

    if (_diceSpin > 0) {
      _diceSpin -= dt;
      _rollFace = _rng.nextInt(6) + 1;
      if (_diceSpin <= 0) {
        _diceSpin = 0;
        audio.play(Sfx.diceLand, volume: 0.8);
        final cb = _afterSpin;
        _afterSpin = null;
        cb?.call();
      }
      notifyListeners();
      return;
    }

    if (_animKey != null) {
      // Leaving the yard is one longer slide; the track is hopped cell by cell.
      _animT += dt / (_animPath.length == 1 ? 0.26 : 0.15);
      if (_animT >= 1) {
        _pos[_animKey!] = List.of(_animTo!);
        if (_animHop + 1 < _animPath.length) {
          _animHop++;
          _animFrom = _animTo;
          _animTo = _animPath[_animHop];
          _footprint(_animFrom!, _animTo!);
          _animT = 0;
          audio.play(Sfx.hop, volume: 0.6);
          notifyListeners();
        } else {
          _animT = 0;
          _finishMove();
        }
      } else {
        _pos[_animKey!] = _lerp(_animFrom!, _animTo!, Curves.easeInOut.transform(_animT));
        notifyListeners();
      }
      return;
    }

    if (_botCooldown > 0) {
      _botCooldown -= dt;
      if (_botCooldown <= 0) {
        _botCooldown = 0;
        _runBot();
      }
    }
  }

  void _runBot() {
    if (online || over) return;
    final seat = _state!.turn;
    final p = _state!.players[seat];
    if (!p.isBot) return;
    if (_state!.mustRoll) {
      _doRollOffline();
    } else {
      final moves = _state!.movable ?? const [];
      if (moves.isNotEmpty) {
        final t = LudoBot(_rng).chooseToken(_state!, seat, _state!.die!, moves);
        _doMoveOffline(t);
      }
    }
  }

  List<double> _lerp(List<double> a, List<double> b, double t) =>
      [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];

  /// Call once after construction (offline) to let a bot open if it leads.
  void start() {
    if (!online) _maybeBotRoll();
  }

  @override
  void dispose() {
    _disposed = true;
    clock.dispose();
    super.dispose();
  }
}

/// A footprint left on a cell a token hopped through; fades out.
class LudoTrailMark {
  LudoTrailMark(this.x, this.y, this.colour, this.angle, this.born);

  /// Grid-unit centre of the cell.
  final double x, y;
  final int colour;

  /// Direction of travel (radians, screen space).
  final double angle;
  final double born;
}

class _Capture {
  _Capture(this.key, this.from, this.to);
  final int key;
  final List<double> from;
  final List<double> to;
}

class _Timer {
  _Timer(this.at, this.run);
  final double at;
  final VoidCallback run;
}
