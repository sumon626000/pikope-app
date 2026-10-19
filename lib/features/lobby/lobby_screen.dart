import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/app_game.dart';
import '../../data/demo_data.dart';
import '../game/game_controller.dart';
import '../game/game_screen.dart';
import '../misc/page_frame.dart';
import '../online/session.dart';
import '../pool/pool_controller.dart';
import '../../l10n/strings.dart';
import '../pool/pool_screen.dart';

/// Match setup: seat 1 is the local player, seats 2-4 are bots or further
/// local players sharing the device (pass & play).
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, this.passAndPlay = false, this.game = AppGame.poker});

  final bool passAndPlay;
  final AppGame game;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  late final List<bool> _human = [true, for (var i = 1; i < widget.game.players; i++) widget.passAndPlay];

  List<SeatConfig> _seats(AppSettings s) {
    var bot = 0;
    return [
      SeatConfig(name: s.name, avatar: s.avatar, cue: ref.read(sessionProvider).cue),
      for (var i = 1; i < widget.game.players; i++)
        if (_human[i])
          SeatConfig(name: ref.read(stringsProvider).playerNumber(i + 1), avatar: DemoData.avatars[(i + 3) % 6])
        else
          SeatConfig(
            name: DemoData.botNames[bot],
            avatar: DemoData.botAvatars[bot++],
            isBot: true,
            botSkill: s.botSkill,
          ),
    ];
  }

  Widget _match(AppSettings s) {
    final pool = widget.game.poolGame;
    return pool == null
        ? GameScreen(config: MatchConfig(seats: _seats(s), shotSeconds: s.shotSeconds))
        : PoolScreen(
            config: PoolMatchConfig(game: pool, seats: _seats(s), shotSeconds: s.shotSeconds));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final s = ref.watch(settingsProvider);
    final seats = _seats(s);
    final count = widget.game.players;
    return PageFrame(
      title: t.matchSetupGame(t.appGameTitle(widget.game)),
      action: GameButton(
        label: t.startMatch,
        icon: Icons.play_arrow_rounded,
        width: 220,
        height: 44,
        fontSize: 14,
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => _match(s)),
        ),
      ),
      child: Column(
        children: [
          SectionCard(
            title: count == 4 ? t.fourPlayersFreeForAll : t.twoPlayersOneVsOne,
            child: Row(
              children: [
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: Column(
                      children: [
                        FramedTile(
                          size: 60,
                          frameColor: i == 0 ? AppColors.active : AppColors.frame,
                          child: AvatarImage(seats[i].avatar, size: 60),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(seats[i].name.toUpperCase(), style: AppText.label(13)),
                        ),
                        const SizedBox(height: 6),
                        if (i == 0)
                          Text(t.you, style: AppText.label(12, color: AppColors.active))
                        else
                          GestureDetector(
                            onTap: () => setState(() => _human[i] = !_human[i]),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundAlt,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.frame, width: 2),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_human[i] ? Icons.person_rounded : Icons.smart_toy_rounded,
                                      size: 16, color: AppColors.gold),
                                  const SizedBox(width: 6),
                                  Text(_human[i] ? t.humanSeat : t.botSeat, style: AppText.label(12)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.swap_horiz_rounded, size: 16, color: AppColors.textDim),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionCard(
                  title: t.botLevelLabel,
                  child: ChoiceRow<int>(
                    options: {0: t.botEasy, 1: t.botNormal, 2: t.botHard},
                    value: s.botLevel,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).update((s) => s.copyWith(botLevel: v)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SectionCard(
                  title: t.shotClockLabel,
                  child: ChoiceRow<int>(
                    options: const {20: '20S', 30: '30S', 45: '45S', 60: '60S'},
                    value: s.shotSeconds,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).update((s) => s.copyWith(shotSeconds: v)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
