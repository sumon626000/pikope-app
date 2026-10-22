import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../data/demo_data.dart';
import '../carrom/carrom_controller.dart';
import '../carrom/carrom_screen.dart';
import '../game/game_controller.dart' show SeatConfig;
import '../ludo/ludo_controller.dart';
import '../ludo/ludo_screen.dart';

/// Free bot practice — only from the home Practice banner, not from coin lobbies.
void launchLudoPractice(BuildContext context, WidgetRef ref, {required int players, int colour = 0}) {
  final s = ref.read(settingsProvider);
  final colours = players == 2 ? [colour, (colour + 2) % 4] : [colour, 1, 2, 3];
  final seats = [
    SeatConfig(name: s.name, avatar: s.avatar),
    for (var i = 1; i < players; i++)
      SeatConfig(
        name: DemoData.botNames[(i - 1) % DemoData.botNames.length],
        avatar: DemoData.botAvatars[(i - 1) % DemoData.botAvatars.length],
        isBot: true,
      ),
  ];
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => LudoScreen(
      config: LudoMatchConfig(seats: players, players: seats, shotSeconds: s.shotSeconds, humanSeats: 1),
      colours: colours,
    ),
  ));
}

void launchCarromPractice(BuildContext context, WidgetRef ref) {
  final s = ref.read(settingsProvider);
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => CarromScreen(
      config: CarromMatchConfig(
        seats: [
          SeatConfig(name: s.name, avatar: s.avatar),
          SeatConfig(name: DemoData.botNames[0], avatar: DemoData.botAvatars[0], isBot: true, botSkill: s.botSkill),
        ],
        shotSeconds: s.shotSeconds,
        strikerSkin: s.carromStriker,
        pieceSkin: s.carromPieces,
        boardSkin: s.carromBoard,
      ),
    ),
  ));
}
