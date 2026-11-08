import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/duel_ui.dart';
import '../duel/bet_level_screen.dart';
import '../duel/duel_chrome.dart';
import '../duel/lobby_data.dart';
import '../start/auth_prompt.dart';
import 'ludo_board.dart';
import '../../l10n/strings.dart';

/// Ludo coin play: pick 2 or 4 players, then the stake tables (practice is on home only).
class LudoLobbyScreen extends ConsumerStatefulWidget {
  const LudoLobbyScreen({super.key});

  @override
  ConsumerState<LudoLobbyScreen> createState() => _LudoLobbyScreenState();
}

class _LudoLobbyScreenState extends ConsumerState<LudoLobbyScreen> {
  int _players = 2;
  int _colour = 0;

  Future<void> _playForCoins() async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BetLevelScreen(
          mode: _players == 2 ? DuelMode.ludo2 : DuelMode.ludo4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    if (DesignBreakpoints.portraitLayout(context)) {
      return DuelCanvas(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DuelTopBar(showProfile: false, showShortcuts: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  Text(
                    t.ludoTitle,
                    textAlign: TextAlign.center,
                    style: AppText.label(22, weight: FontWeight.w900),
                  ),
                  Text(
                    t.ludoLobbySub,
                    textAlign: TextAlign.center,
                    style: AppText.label(12, color: DuelColors.dim),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _choice(
                          t.twoPlayers,
                          _players == 2,
                          () => setState(() => _players = 2),
                          width: double.infinity,
                          height: 48,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _choice(
                          t.fourPlayers,
                          _players == 4,
                          () => setState(() => _players = 4),
                          width: double.infinity,
                          height: 48,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.yourColour,
                    textAlign: TextAlign.center,
                    style: AppText.label(
                      13,
                      color: DuelColors.dim,
                      weight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var c = 0; c < 4; c++)
                        GestureDetector(
                          onTap: () {
                            AudioService.tap();
                            setState(() => _colour = c);
                          },
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: LudoBoard.colours[c],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _colour == c
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: _colour == c
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.ludoColorName(_colour),
                    textAlign: TextAlign.center,
                    style: AppText.label(
                      14,
                      color: LudoBoard.colours[_colour],
                      weight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: DuelButton(
                      label: t.playForCoin,
                      width: 240,
                      height: 48,
                      fontSize: 16,
                      color: DuelColors.gold,
                      onPressed: _playForCoins,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: NavTile(
                  icon: Icons.reply_rounded,
                  label: t.back,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return DuelCanvas(
      child: LobbyScaffold(
        topBar: const DuelTopBar(showProfile: false, showShortcuts: false),
        title: Center(
          child: DuelTitle(t.ludoTitle, size: 54, sub: t.ludoLobbySub),
        ),
        centerPadding: EdgeInsets.zero,
        center: Column(
          children: [
            const SizedBox(height: DesignSpacing.x6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _choice(
                  t.twoPlayers,
                  _players == 2,
                  () => setState(() => _players = 2),
                ),
                const SizedBox(width: DesignSpacing.x6),
                _choice(
                  t.fourPlayers,
                  _players == 4,
                  () => setState(() => _players = 4),
                ),
              ],
            ),
            const SizedBox(height: DesignSpacing.x10),
            Text(
              t.yourColour,
              style: AppText.label(
                16,
                color: DuelColors.dim,
                weight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                      margin: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.x3,
                      ),
                      decoration: BoxDecoration(
                        color: LudoBoard.colours[c],
                        borderRadius: BorderRadius.circular(DesignRadii.md),
                        border: Border.all(
                          color: _colour == c
                              ? Colors.white
                              : Colors.transparent,
                          width: 4,
                        ),
                        boxShadow: [
                          if (_colour == c)
                            BoxShadow(
                              color: LudoBoard.colours[c].withValues(
                                alpha: 0.7,
                              ),
                              blurRadius: 20,
                            ),
                        ],
                      ),
                      child: _colour == c
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 44,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DesignSpacing.x2),
            Text(
              t.ludoColorName(_colour),
              style: AppText.label(
                16,
                color: LudoBoard.colours[_colour],
                weight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            DuelButton(
              label: t.playForCoin,
              width: 420,
              height: 72,
              color: DuelColors.gold,
              onPressed: _playForCoins,
            ),
            const SizedBox(height: DesignSpacing.x8),
          ],
        ),
        bottomLeading: LobbyBackNav(
          label: t.back,
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Widget _choice(
    String label,
    bool on,
    VoidCallback onTap, {
    double width = 220,
    double height = 72,
    double fontSize = 22,
  }) => GestureDetector(
    onTap: () {
      AudioService.tap();
      onTap();
    },
    child: Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: duelPanel(
        radius: DesignRadii.md,
        rim: on ? DuelColors.green : DuelColors.rim,
        glow: on,
        fill: on ? const Color(0xE60C2414) : const Color(0xCC0B0E1C),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: AppText.label(
            fontSize,
            color: on ? DuelColors.green : DuelColors.silver,
            weight: FontWeight.w900,
          ),
        ),
      ),
    ),
  );
}
