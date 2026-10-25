import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../data/demo_data.dart';
import '../../l10n/strings.dart';
import '../carrom/carrom_controller.dart';
import '../carrom/carrom_screen.dart';
import '../game/game_controller.dart' show SeatConfig;
import '../ludo/ludo_controller.dart';
import '../ludo/ludo_screen.dart';

/// Vs bots or pass & play on one device (same choices as pool practice).
Future<void> showOfflinePracticeModeDialog(
  BuildContext context,
  WidgetRef ref, {
  String? modeLabel,
  required VoidCallback onVsBots,
  required VoidCallback onPassAndPlay,
}) {
  return showDuelDialog<void>(
    context,
    barrierColor: const Color(0xB3000000),
    builder: (dialog) {
      final t = ref.watch(stringsProvider);
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(22),
          decoration: duelPanel(rim: DuelColors.rimLight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.practice, style: AppText.label(18, weight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                modeLabel ?? t.practiceLong,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.4, color: DuelColors.dim),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DuelButton(
                    label: t.vsBots,
                    width: 150,
                    height: 44,
                    fontSize: 14,
                    onPressed: () {
                      Navigator.of(dialog).pop();
                      onVsBots();
                    },
                  ),
                  const SizedBox(width: 10),
                  DuelButton(
                    label: t.passAndPlay,
                    width: 160,
                    height: 44,
                    fontSize: 14,
                    color: DuelColors.blue,
                    onPressed: () {
                      Navigator.of(dialog).pop();
                      onPassAndPlay();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget buildLudoPracticeScreen(
  WidgetRef ref, {
  required int players,
  required bool passAndPlay,
  int colour = 0,
}) {
  final s = ref.read(settingsProvider);
  final t = ref.read(stringsProvider);
  final colours = players == 2 ? [colour, (colour + 2) % 4] : [colour, 1, 2, 3];
  final seats = passAndPlay
      ? [
          SeatConfig(name: s.name, avatar: s.avatar),
          for (var i = 1; i < players; i++)
            SeatConfig(name: t.playerNumber(i + 1), avatar: DemoData.avatars[(i + 3) % 6]),
        ]
      : [
          SeatConfig(name: s.name, avatar: s.avatar),
          for (var i = 1; i < players; i++)
            SeatConfig(
              name: DemoData.botNames[(i - 1) % DemoData.botNames.length],
              avatar: DemoData.botAvatars[(i - 1) % DemoData.botAvatars.length],
              isBot: true,
            ),
        ];
  return LudoScreen(
    config: LudoMatchConfig(
      seats: players,
      players: seats,
      shotSeconds: s.shotSeconds,
      humanSeats: passAndPlay ? players : 1,
    ),
    colours: colours,
  );
}

Widget buildCarromPracticeScreen(WidgetRef ref, {required bool passAndPlay}) {
  final s = ref.read(settingsProvider);
  final t = ref.read(stringsProvider);
  return CarromScreen(
    config: CarromMatchConfig(
      seats: passAndPlay
          ? [
              SeatConfig(name: s.name, avatar: s.avatar),
              SeatConfig(name: t.playerNumber(2), avatar: DemoData.avatars[4]),
            ]
          : [
              SeatConfig(name: s.name, avatar: s.avatar),
              SeatConfig(
                name: DemoData.botNames[0],
                avatar: DemoData.botAvatars[0],
                isBot: true,
                botSkill: s.botSkill,
              ),
            ],
      shotSeconds: s.shotSeconds,
      strikerSkin: s.carromStriker,
      pieceSkin: s.carromPieces,
      boardSkin: s.carromBoard,
    ),
  );
}

void pushLudoPractice(
  BuildContext context,
  WidgetRef ref, {
  required int players,
  required bool passAndPlay,
  int colour = 0,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => buildLudoPracticeScreen(ref, players: players, passAndPlay: passAndPlay, colour: colour),
    ),
  );
}

void pushCarromPractice(BuildContext context, WidgetRef ref, {required bool passAndPlay}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => buildCarromPracticeScreen(ref, passAndPlay: passAndPlay)),
  );
}

/// Home → Practice → Ludo (2 or 4 seats).
void launchLudoPractice(BuildContext context, WidgetRef ref, {required int players, int colour = 0}) {
  final t = ref.read(stringsProvider);
  showOfflinePracticeModeDialog(
    context,
    ref,
    modeLabel: t.ludoPlayers(players),
    onVsBots: () => pushLudoPractice(context, ref, players: players, passAndPlay: false, colour: colour),
    onPassAndPlay: () => pushLudoPractice(context, ref, players: players, passAndPlay: true, colour: colour),
  );
}

void launchCarromPractice(BuildContext context, WidgetRef ref) {
  final t = ref.read(stringsProvider);
  showOfflinePracticeModeDialog(
    context,
    ref,
    modeLabel: t.carromTitle,
    onVsBots: () => pushCarromPractice(context, ref, passAndPlay: false),
    onPassAndPlay: () => pushCarromPractice(context, ref, passAndPlay: true),
  );
}
