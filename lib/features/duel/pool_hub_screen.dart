import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../l10n/strings.dart';
import '../misc/settings_screen.dart';
import '../online/session.dart';
import 'bet_level_screen.dart';
import 'duel_home_screen.dart' show PokerArt;
import 'home_portrait_widgets.dart' show RackArt;
import 'lobby_data.dart';
import 'shop_screen.dart';
import '../start/auth_prompt.dart';

/// Everything pool lives here, laid out like the reference's room page:
/// "Select Mode" cards (8-, 9-, 10-ball, Billiard Poker), the jackpot line,
/// the quick random duel, and a gold Play button to the stake tables.
class PoolHubScreen extends ConsumerStatefulWidget {
  const PoolHubScreen({super.key});

  @override
  ConsumerState<PoolHubScreen> createState() => _PoolHubScreenState();
}

class _PoolHubScreenState extends ConsumerState<PoolHubScreen> {
  DuelMode _mode = DuelMode.eight;

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    ref.read(lobbyProvider.notifier).refresh();
  }

  Future<void> _openStaked(Widget screen) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (!mounted) return;
    await _open(screen);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final data = ref.watch(lobbyProvider).valueOrNull;
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final registered = hasRegisteredAccount(ref);
    final modes = [
      (DuelMode.eight, t.eightBallTitle, t.eightBallSubShort, const RackArt()),
      (DuelMode.nine, t.nineBallTitle, t.nineBallSubShort, const _BigBalls([9, 2])),
      (DuelMode.ten, t.tenBallTitle, t.tenBallSubShort, const _BigBalls([10, 3])),
      (DuelMode.poker, t.billiardPokerCardTitle, t.jackpotSubLine, const PokerArt()),
    ];
    return PcPage(
      header: PcHeader(
        avatar: settings.avatar,
        name: settings.name,
        registered: registered,
        level: session.level,
        coins: lobbyDisplayCoins(ref),
        gems: registered ? session.gems : null,
        placeholder: t.signUpOrLogin,
        onProfile: () => _openStaked(const SettingsScreen()),
        onWallet: () => _openStaked(const ShopScreen()),
      ),
      title: t.poolHubTitle,
      panel: false,
      scroll: true,
      bodyPadding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Select Mode
          Container(
            decoration: pcPanelDecoration(),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                PcSectionBar(t.selectMode),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Wrap(
                    spacing: 22,
                    runSpacing: 22,
                    children: [
                      for (final (mode, title, _, art) in modes)
                        PcSelectCard(
                          width: 464,
                          height: 300,
                          selected: _mode == mode,
                          label: title,
                          onTap: () {
                            AudioService.tap();
                            setState(() => _mode = mode);
                          },
                          child: _ModeArt(art: art, poker: mode == DuelMode.poker),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  child: Text(modes.firstWhere((m) => m.$1 == _mode).$3, textAlign: TextAlign.center, style: pcText(28, color: DesignColors.pcTextDim, weight: FontWeight.w500)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // --- Jackpot (Billiard Poker) and the quick random duel
          Container(
            decoration: pcPanelDecoration(),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                PcSectionBar(t.jackpotUpTo(data == null ? '10,000' : formatCoins(data.jackpot.reduce(max)))),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      const PikoCoinIcon(size: 120),
                      const SizedBox(width: 20),
                      Expanded(child: Text(t.jackpotSubLine, style: pcText(28, color: DesignColors.pcTextDim, weight: FontWeight.w500).copyWith(height: 1.3))),
                      const SizedBox(width: 16),
                      PcButton(label: t.playBtn, style: PcButtonStyle.gold, width: 220, height: 90, fontSize: 36, onPressed: () => _openStaked(const BetLevelScreen(mode: DuelMode.poker))),
                    ],
                  ),
                ),
                Divider(height: 2, color: Colors.white.withValues(alpha: 0.12)),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      const Icon(Icons.shuffle_rounded, color: Color(0xFF9CC2FF), size: 100),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(titleCase(t.quickDuel), style: pcText(34)),
                            const SizedBox(height: 4),
                            Text(t.quickDuelSubRandom, style: pcText(26, color: DesignColors.pcTextDim, weight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      PcButton(label: t.playBtn, width: 220, height: 90, fontSize: 36, onPressed: () => _openStaked(const BetLevelScreen(mode: DuelMode.billiard))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: PcButton(
              label: t.playBtn,
              style: PcButtonStyle.gold,
              width: 520,
              height: 120,
              fontSize: 48,
              onPressed: () => _openStaked(BetLevelScreen(mode: _mode)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// Green cloth behind a mode's art, like the reference's mode cards.
class _ModeArt extends StatelessWidget {
  const _ModeArt({required this.art, required this.poker});

  final Widget art;
  final bool poker;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: poker ? const [Color(0xFF5A2FB0), Color(0xFF2C1466)] : const [Color(0xFF2AA86A), Color(0xFF167A4A)],
          ),
        ),
        child: Padding(padding: const EdgeInsets.fromLTRB(40, 16, 40, 76), child: art),
      );
}

/// Two or three big numbered balls (9 / 10-ball mode cards).
class _BigBalls extends StatelessWidget {
  const _BigBalls(this.numbers);

  final List<int> numbers;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final r = min(c.maxWidth, c.maxHeight) * 0.36;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(left: c.maxWidth * 0.12, top: c.maxHeight * 0.2, child: BallIcon(numbers.last, size: r * 1.5)),
              Positioned(right: c.maxWidth * 0.14, top: c.maxHeight * 0.05, child: BallIcon(numbers.first, size: r * 2.2)),
            ],
          );
        },
      );
}
