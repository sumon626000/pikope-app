import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../duel/bet_level_screen.dart';
import '../duel/home_portrait_widgets.dart' show LudoHeroArt;
import '../duel/lobby_data.dart';
import '../duel/shop_screen.dart';
import '../misc/settings_screen.dart';
import '../online/session.dart';
import '../start/auth_prompt.dart';
import 'ludo_board.dart';
import '../../l10n/strings.dart';

/// Ludo coin play, in the reference's room layout: "Select Mode" cards (2 or
/// 4 players), the colour picker, then a gold Play to the stake tables
/// (practice is on home only).
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
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BetLevelScreen(mode: _players == 2 ? DuelMode.ludo2 : DuelMode.ludo4),
    ));
  }

  Future<void> _gated(Widget screen) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final registered = hasRegisteredAccount(ref);
    return PcPage(
      header: PcHeader(
        avatar: settings.avatar,
        name: settings.name,
        registered: registered,
        level: session.level,
        coins: lobbyDisplayCoins(ref),
        gems: registered ? session.gems : null,
        placeholder: t.signUpOrLogin,
        onProfile: () => _gated(const SettingsScreen()),
        onWallet: () => _gated(const ShopScreen()),
      ),
      title: t.ludoTitle,
      panel: false,
      scroll: true,
      bodyPadding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: pcPanelDecoration(),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                PcSectionBar(t.selectMode),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      for (final n in const [2, 4]) ...[
                        if (n == 4) const SizedBox(width: 22),
                        Expanded(
                          child: PcSelectCard(
                            height: 300,
                            selected: _players == n,
                            label: n == 2 ? t.twoPlayers : t.fourPlayers,
                            onTap: () {
                              AudioService.tap();
                              setState(() => _players = n);
                            },
                            child: DecoratedBox(
                              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF04A95), Color(0xFFB81C6C)])),
                              child: Padding(padding: const EdgeInsets.fromLTRB(30, 12, 30, 74), child: _SeatsArt(n)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  child: Text(t.ludoLobbySub, textAlign: TextAlign.center, style: pcText(28, color: DesignColors.pcTextDim, weight: FontWeight.w500)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: pcPanelDecoration(),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                PcSectionBar(t.yourColour),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      for (var c = 0; c < 4; c++) ...[
                        if (c > 0) const SizedBox(width: 18),
                        Expanded(
                          child: PcSelectCard(
                            height: 200,
                            selected: _colour == c,
                            onTap: () {
                              AudioService.tap();
                              setState(() => _colour = c);
                            },
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(LudoBoard.colours[c], Colors.white, 0.2)!, LudoBoard.colours[c], Color.lerp(LudoBoard.colours[c], Colors.black, 0.35)!]),
                              ),
                              child: Center(child: Icon(Icons.circle, color: Colors.white.withValues(alpha: 0.9), size: 80, shadows: const [Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 4))])),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  child: Text(titleCase(t.ludoColorName(_colour)), style: pcText(34, color: Color.lerp(LudoBoard.colours[_colour], Colors.white, 0.35)!)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Center(child: PcButton(label: t.playForCoin, style: PcButtonStyle.gold, width: 640, height: 120, fontSize: 44, onPressed: _playForCoins)),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// Board art with the number of seats marked by pawns.
class _SeatsArt extends StatelessWidget {
  const _SeatsArt(this.players);

  final int players;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(child: LudoHeroArt()),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_rounded, color: Colors.white, size: 34),
                  Text('×$players', style: pcText(30)),
                ],
              ),
            ),
          ),
        ],
      );
}
