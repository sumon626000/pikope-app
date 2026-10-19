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
import 'carrom_controller.dart';
import '../../l10n/strings.dart';
import 'carrom_screen.dart';
import 'carrom_skins.dart';

/// Carrom entry: pick your striker, piece set and board, then practice against a
/// bot for free or play for coins (same bet ladder as the pool games, winner
/// takes the pot).
class CarromLobbyScreen extends ConsumerWidget {
  const CarromLobbyScreen({super.key});

  void _practice(BuildContext context, WidgetRef ref) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final striker = strikerSkinOf(settings.carromStriker);
    final pieces = pieceSkinOf(settings.carromPieces);
    return DuelCanvas(
      child: Stack(
        children: [
          const Positioned(left: 0, right: 0, top: 6, child: DuelTopBar(showProfile: false, showShortcuts: false)),
          Positioned(left: 0, right: 0, top: 96, child: DuelTitle(t.carromTitle, size: 48, sub: t.carromLobbySub)),
          // Striker choice.
          Positioned(
            left: 0,
            right: 0,
            top: 196,
            child: Center(
              child: _Picker(
                title: t.yourStriker,
                selectedName: striker.name,
                children: [
                  for (final sk in strikerSkins)
                    _Swatch(
                      selected: sk.id == settings.carromStriker,
                      onTap: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(carromStriker: sk.id)),
                      child: CustomPaint(size: const Size(64, 64), painter: _DiscPreview(const [DiscKind.striker], sk, pieces)),
                    ),
                ],
              ),
            ),
          ),
          // Piece set choice.
          Positioned(
            left: 0,
            right: 0,
            top: 350,
            child: Center(
              child: _Picker(
                title: t.yourPieces,
                selectedName: pieces.name,
                children: [
                  for (final pk in pieceSkins)
                    _Swatch(
                      selected: pk.id == settings.carromPieces,
                      onTap: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(carromPieces: pk.id)),
                      child: CustomPaint(size: const Size(150, 64), painter: _DiscPreview(const [DiscKind.light, DiscKind.queen, DiscKind.dark], striker, pk)),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 540,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DuelButton(label: t.practiceFreeBtn, width: 320, height: 66, color: DuelColors.green, onPressed: () => _practice(context, ref)),
                  const SizedBox(width: 24),
                  DuelButton(
                    label: t.playForCoin,
                    width: 320,
                    height: 66,
                    color: DuelColors.gold,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BetLevelScreen(mode: DuelMode.carrom))),
                  ),
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
}

class _Picker extends StatelessWidget {
  const _Picker({required this.title, required this.selectedName, required this.children});

  final String title;
  final String selectedName;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppText.label(16, color: DuelColors.dim, weight: FontWeight.w800)),
              const SizedBox(width: 12),
              Text(selectedName, style: AppText.label(16, color: DuelColors.gold, weight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          Row(mainAxisSize: MainAxisSize.min, children: children),
        ],
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          AudioService.tap();
          onTap();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 7),
          padding: const EdgeInsets.all(10),
          decoration: duelPanel(radius: 16, rim: selected ? DuelColors.green : DuelColors.rim, glow: selected, fill: selected ? const Color(0xE60C2414) : const Color(0xCC0B0E1C)),
          child: child,
        ),
      );
}

/// A row of discs drawn with the given skins (for the pickers).
class _DiscPreview extends CustomPainter {
  const _DiscPreview(this.kinds, this.striker, this.pieces);

  final List<DiscKind> kinds;
  final StrikerSkin striker;
  final PieceSkin pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.42;
    final gap = kinds.length == 1 ? 0.0 : (size.width - 2 * r) / (kinds.length - 1);
    for (var i = 0; i < kinds.length; i++) {
      paintCarromDisc(canvas, Offset(r + gap * i, size.height / 2), r, kinds[i], striker: striker, pieces: pieces);
    }
  }

  @override
  bool shouldRepaint(_DiscPreview old) => old.striker != striker || old.pieces != pieces || old.kinds != kinds;
}
