import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/duel_ui.dart';
import '../duel/bet_level_screen.dart';
import '../duel/duel_chrome.dart';
import '../duel/lobby_data.dart';
import '../start/auth_prompt.dart';
import 'carrom_skins.dart';
import '../../l10n/strings.dart';

/// Carrom coin play: pick striker and pieces here, then stake tables (boards in Items shop).
class CarromLobbyScreen extends ConsumerWidget {
  const CarromLobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final striker = strikerSkinOf(settings.carromStriker);
    final pieces = pieceSkinOf(settings.carromPieces);
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
                    t.carromTitle,
                    textAlign: TextAlign.center,
                    style: AppText.label(22, weight: FontWeight.w900),
                  ),
                  Text(
                    t.carromLobbySub,
                    textAlign: TextAlign.center,
                    style: AppText.label(12, color: DuelColors.dim),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _Picker(
                    title: t.yourStriker,
                    selectedName: striker.name,
                    children: [
                      for (final sk in strikerSkins)
                        _Swatch(
                          selected: sk.id == settings.carromStriker,
                          onTap: () => ref
                              .read(settingsProvider.notifier)
                              .update((s) => s.copyWith(carromStriker: sk.id)),
                          child: CustomPaint(
                            size: const Size(52, 52),
                            painter: _DiscPreview(
                              const [DiscKind.striker],
                              sk,
                              pieces,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Picker(
                    title: t.yourPieces,
                    selectedName: pieces.name,
                    children: [
                      for (final pk in pieceSkins)
                        _Swatch(
                          selected: pk.id == settings.carromPieces,
                          onTap: () => ref
                              .read(settingsProvider.notifier)
                              .update((s) => s.copyWith(carromPieces: pk.id)),
                          child: CustomPaint(
                            size: const Size(120, 52),
                            painter: _DiscPreview(
                              const [
                                DiscKind.light,
                                DiscKind.queen,
                                DiscKind.dark,
                              ],
                              striker,
                              pk,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: DuelButton(
                      label: t.playForCoin,
                      width: 240,
                      height: 48,
                      fontSize: 16,
                      color: DuelColors.gold,
                      onPressed: () async {
                        if (!await requireRegisteredAccount(context, ref))
                          return;
                        if (!context.mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const BetLevelScreen(mode: DuelMode.carrom),
                          ),
                        );
                      },
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
          child: DuelTitle(t.carromTitle, size: 48, sub: t.carromLobbySub),
        ),
        centerPadding: EdgeInsets.zero,
        center: Column(
          children: [
            const SizedBox(height: DesignSpacing.x5),
            _Picker(
              title: t.yourStriker,
              selectedName: striker.name,
              children: [
                for (final sk in strikerSkins)
                  _Swatch(
                    selected: sk.id == settings.carromStriker,
                    onTap: () => ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(carromStriker: sk.id)),
                    child: CustomPaint(
                      size: const Size(64, 64),
                      painter: _DiscPreview(
                        const [DiscKind.striker],
                        sk,
                        pieces,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DesignSpacing.x10),
            _Picker(
              title: t.yourPieces,
              selectedName: pieces.name,
              children: [
                for (final pk in pieceSkins)
                  _Swatch(
                    selected: pk.id == settings.carromPieces,
                    onTap: () => ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(carromPieces: pk.id)),
                    child: CustomPaint(
                      size: const Size(150, 64),
                      painter: _DiscPreview(
                        const [DiscKind.light, DiscKind.queen, DiscKind.dark],
                        striker,
                        pk,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            DuelButton(
              label: t.playForCoin,
              width: 420,
              height: 72,
              color: DuelColors.gold,
              onPressed: () async {
                if (!await requireRegisteredAccount(context, ref)) return;
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BetLevelScreen(mode: DuelMode.carrom),
                  ),
                );
              },
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
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.title,
    required this.selectedName,
    required this.children,
  });

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
          Text(
            title,
            style: AppText.label(
              16,
              color: DuelColors.dim,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: DesignSpacing.x3),
          Text(
            selectedName,
            style: AppText.label(
              16,
              color: DuelColors.gold,
              weight: FontWeight.w900,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    ],
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.selected,
    required this.onTap,
    required this.child,
  });

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
      decoration: duelPanel(
        radius: DesignRadii.md,
        rim: selected ? DuelColors.green : DuelColors.rim,
        glow: selected,
        fill: selected ? const Color(0xE60C2414) : const Color(0xCC0B0E1C),
      ),
      child: child,
    ),
  );
}

class _DiscPreview extends CustomPainter {
  const _DiscPreview(this.kinds, this.striker, this.pieces);

  final List<DiscKind> kinds;
  final StrikerSkin striker;
  final PieceSkin pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.42;
    final gap = kinds.length == 1
        ? 0.0
        : (size.width - 2 * r) / (kinds.length - 1);
    for (var i = 0; i < kinds.length; i++) {
      paintCarromDisc(
        canvas,
        Offset(r + gap * i, size.height / 2),
        r,
        kinds[i],
        striker: striker,
        pieces: pieces,
      );
    }
  }

  @override
  bool shouldRepaint(_DiscPreview old) =>
      old.striker != striker || old.pieces != pieces || old.kinds != kinds;
}
