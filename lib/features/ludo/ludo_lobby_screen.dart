import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../data/demo_data.dart';
import '../duel/bet_level_screen.dart';
import '../duel/duel_chrome.dart';
import '../duel/lobby_data.dart';
import '../game/game_controller.dart' show SeatConfig;
import 'ludo_board.dart';
import 'ludo_controller.dart';
import '../../l10n/strings.dart';
import 'ludo_screen.dart';

/// Ludo entry: pick 2 or 4 players and your colour, then practice for free or
/// play for coins (same bet ladder as the pool games).
class LudoLobbyScreen extends ConsumerStatefulWidget {
  const LudoLobbyScreen({super.key});

  @override
  ConsumerState<LudoLobbyScreen> createState() => _LudoLobbyScreenState();
}

class _LudoLobbyScreenState extends ConsumerState<LudoLobbyScreen> {
  int _players = 2;
  int _colour = 0; // your colour slot (practice only)

  List<int> _coloursForPractice() {
    // You take [_colour]; bots fill the rest. 2 players sit opposite.
    if (_players == 2) {
      final opposite = (_colour + 2) % 4;
      return [_colour, opposite];
    }
    final rest = [for (var c = 0; c < 4; c++) if (c != _colour) c];
    return [_colour, ...rest];
  }

  void _practice() {
    final s = ref.read(settingsProvider);
    final colours = _coloursForPractice();
    final seats = [
      SeatConfig(name: s.name, avatar: s.avatar),
      for (var i = 1; i < _players; i++) SeatConfig(name: DemoData.botNames[(i - 1) % 3], avatar: DemoData.botAvatars[(i - 1) % 3], isBot: true),
    ];
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LudoScreen(
        config: LudoMatchConfig(seats: _players, players: seats, shotSeconds: s.shotSeconds, humanSeats: 1),
        colours: colours,
      ),
    ));
  }

  void _playForCoins() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BetLevelScreen(mode: _players == 2 ? DuelMode.ludo2 : DuelMode.ludo4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return DuelCanvas(
      child: Stack(
        children: [
          const Positioned(left: 0, right: 0, top: 6, child: DuelTopBar(showProfile: false, showShortcuts: false)),
          Positioned(left: 0, right: 0, top: 128, child: DuelTitle(t.ludoTitle, size: 54, sub: t.ludoLobbySub)),
          // Players 2 / 4.
          Positioned(
            left: 0,
            right: 0,
            top: 250,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _choice(t.twoPlayers, _players == 2, () => setState(() => _players = 2)),
                  const SizedBox(width: 24),
                  _choice(t.fourPlayers, _players == 4, () => setState(() => _players = 4)),
                ],
              ),
            ),
          ),
          // Colour swatches.
          Positioned(
            left: 0,
            right: 0,
            top: 370,
            child: Center(
              child: Column(
                children: [
                  Text(t.yourColour, style: AppText.label(16, color: DuelColors.dim, weight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = 0; c < 4; c++)
                        GestureDetector(
                          onTap: () {
                            AudioService.tap();
                            setState(() => _colour = c);
                          },
                          child: Container(
                            width: 92,
                            height: 92,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: LudoBoard.colours[c],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _colour == c ? Colors.white : Colors.transparent, width: 4),
                              boxShadow: [if (_colour == c) BoxShadow(color: LudoBoard.colours[c].withValues(alpha: 0.7), blurRadius: 20)],
                            ),
                            child: _colour == c ? const Icon(Icons.check_rounded, color: Colors.white, size: 44) : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(t.ludoColorName(_colour), style: AppText.label(16, color: LudoBoard.colours[_colour], weight: FontWeight.w900)),
                ],
              ),
            ),
          ),
          // Actions.
          Positioned(
            left: 0,
            right: 0,
            top: 616,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DuelButton(label: t.practiceFreeBtn, width: 320, height: 66, color: DuelColors.green, onPressed: _practice),
                  const SizedBox(width: 24),
                  DuelButton(label: t.playForCoin, width: 320, height: 66, color: DuelColors.gold, onPressed: _playForCoins),
                ],
              ),
            ),
          ),
          Positioned(
            left: 42,
            bottom: 34,
            child: NavTile(icon: Icons.reply_rounded, label: t.back, onTap: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }

  Widget _choice(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: () {
          AudioService.tap();
          onTap();
        },
        child: Container(
          width: 220,
          height: 72,
          alignment: Alignment.center,
          decoration: duelPanel(radius: 16, rim: on ? DuelColors.green : DuelColors.rim, glow: on, fill: on ? const Color(0xE60C2414) : const Color(0xCC0B0E1C)),
          child: Text(label, style: AppText.label(22, color: on ? DuelColors.green : DuelColors.silver, weight: FontWeight.w900)),
        ),
      );
}
