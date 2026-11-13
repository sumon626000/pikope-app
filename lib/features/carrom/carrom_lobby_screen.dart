import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../duel/bet_level_screen.dart';
import '../duel/lobby_data.dart';
import '../duel/shop_screen.dart';
import '../misc/settings_screen.dart';
import '../online/session.dart';
import '../start/auth_prompt.dart';
import 'carrom_skins.dart';
import '../../l10n/strings.dart';

/// Carrom coin play in the reference's room layout: pick striker and pieces
/// (select cards), then a gold Play to the stake tables. Boards are bought
/// in Items.
class CarromLobbyScreen extends ConsumerWidget {
  const CarromLobbyScreen({super.key});

  Future<void> _gated(BuildContext context, WidgetRef ref, Widget screen) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final registered = hasRegisteredAccount(ref);
    final striker = strikerSkinOf(settings.carromStriker);
    final pieces = pieceSkinOf(settings.carromPieces);
    return PcPage(
      header: PcHeader(
        avatar: settings.avatar,
        name: settings.name,
        registered: registered,
        level: session.level,
        coins: lobbyDisplayCoins(ref),
        gems: registered ? session.gems : null,
        placeholder: t.signUpOrLogin,
        onProfile: () => _gated(context, ref, const SettingsScreen()),
        onWallet: () => _gated(context, ref, const ShopScreen()),
      ),
      title: t.carromTitle,
      panel: false,
      scroll: true,
      bodyPadding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            title: t.yourStriker,
            selectedName: striker.name,
            sub: t.carromLobbySub,
            children: [
              for (final sk in strikerSkins)
                PcSelectCard(
                  width: 190,
                  height: 190,
                  selected: sk.id == settings.carromStriker,
                  onTap: () {
                    AudioService.tap();
                    ref.read(settingsProvider.notifier).update((s) => s.copyWith(carromStriker: sk.id));
                  },
                  child: _Felt(child: CustomPaint(painter: _DiscPreview(const [DiscKind.striker], sk, pieces))),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _Section(
            title: t.yourPieces,
            selectedName: pieces.name,
            children: [
              for (final pk in pieceSkins)
                PcSelectCard(
                  width: 300,
                  height: 170,
                  selected: pk.id == settings.carromPieces,
                  onTap: () {
                    AudioService.tap();
                    ref.read(settingsProvider.notifier).update((s) => s.copyWith(carromPieces: pk.id));
                  },
                  child: _Felt(child: CustomPaint(painter: _DiscPreview(const [DiscKind.light, DiscKind.queen, DiscKind.dark], striker, pk))),
                ),
            ],
          ),
          const SizedBox(height: 40),
          Center(
            child: PcButton(
              label: t.playForCoin,
              style: PcButtonStyle.gold,
              width: 640,
              height: 120,
              fontSize: 44,
              onPressed: () => _gated(context, ref, const BetLevelScreen(mode: DuelMode.carrom)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.selectedName, required this.children, this.sub});

  final String title;
  final String selectedName;
  final String? sub;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: pcPanelDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            PcSectionBar(title),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Wrap(spacing: 18, runSpacing: 18, alignment: WrapAlignment.center, children: children),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: Column(
                children: [
                  Text(titleCase(selectedName), style: pcText(34, color: DesignColors.pcGold)),
                  if (sub != null) ...[
                    const SizedBox(height: 6),
                    Text(sub!, textAlign: TextAlign.center, style: pcText(26, color: DesignColors.pcTextDim, weight: FontWeight.w500)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

/// Carrom-board wood behind a swatch.
class _Felt extends StatelessWidget {
  const _Felt({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE8BF8E), Color(0xFFC9955E)])),
        child: Padding(padding: const EdgeInsets.all(24), child: child),
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
    final gap = kinds.length == 1 ? 0.0 : (size.width - 2 * r) / (kinds.length - 1);
    final x0 = kinds.length == 1 ? size.width / 2 : r;
    for (var i = 0; i < kinds.length; i++) {
      paintCarromDisc(canvas, Offset(x0 + gap * i, size.height / 2), r, kinds[i], striker: striker, pieces: pieces);
    }
  }

  @override
  bool shouldRepaint(_DiscPreview old) => old.striker != striker || old.pieces != pieces || old.kinds != kinds;
}
