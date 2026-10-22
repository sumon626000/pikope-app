import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../data/cues.dart';
import 'board_shop.dart';
import 'cues_screen.dart';
import 'duel_chrome.dart';
import '../../l10n/strings.dart';
import 'lobby_data.dart';

/// Boards and cues only — no coin buy, redeem or transfer (those live in Shop).
class ItemsScreen extends ConsumerWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return DuelPage(
      title: t.navItems,
      sub: t.itemsScreenSub,
      expanded: true,
      sideBack: true,
      contentTop: 198,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth >= 520 ? 2 : 1;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.shopItemsSection, style: AppText.label(22, color: DuelColors.gold, weight: FontWeight.w900)),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: cols,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: cols == 2 ? 3.4 : 2.8,
                  children: [
                _ItemDoor(label: t.poolTableBtn, color: DuelColors.green, icon: Icons.crop_16_9_rounded, onTap: () => pushScreen(context, const BoardShopScreen(kind: BoardKind.pool))),
                _ItemDoor(label: t.carromTableBtn, color: const Color(0xFFD9A34A), icon: Icons.grid_on_rounded, onTap: () => pushScreen(context, const BoardShopScreen(kind: BoardKind.carrom))),
                _ItemDoor(label: t.ludoBoardBtn, color: const Color(0xFFE8721C), icon: Icons.casino_rounded, onTap: () => pushScreen(context, const BoardShopScreen(kind: BoardKind.ludo))),
                    _ItemDoor(label: t.navCues, color: DuelColors.blue, icon: NavTile.cuesIcon, onTap: () => pushScreen(context, const CuesScreen(asShop: true))),
                  ],
                ),
                const SizedBox(height: 18),
                Text(t.cuesSection, style: AppText.label(20, color: DuelColors.blue, weight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(t.cuesSamePlayHint, style: AppText.label(13, color: DuelColors.silver, weight: FontWeight.w600)),
                const SizedBox(height: 10),
                _CuePreviewStrip(
                  cues: ref.watch(lobbyProvider).valueOrNull?.cues ?? [for (final s in CueStyle.all) CueOffer(id: s.id, name: s.name, price: 0, currency: 'coins', owned: s.id == 'classic')],
                  onOpenShop: () => pushScreen(context, const CuesScreen(asShop: true)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CuePreviewStrip extends StatelessWidget {
  const _CuePreviewStrip({required this.cues, required this.onOpenShop});

  final List<CueOffer> cues;
  final VoidCallback onOpenShop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cues.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final cue = cues[i];
          return GestureDetector(
            onTap: () {
              AudioService.tap();
              onOpenShop();
            },
            child: Container(
              width: 132,
              decoration: duelPanel(radius: 12, rim: DuelColors.blue.withValues(alpha: 0.55)),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                children: [
                  Expanded(child: CueStickPreview(cueId: cue.id, stroke: 14)),
                  const SizedBox(height: 2),
                  Text(
                    cue.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(11, color: Colors.white, weight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ItemDoor extends StatelessWidget {
  const _ItemDoor({required this.label, required this.color, required this.icon, required this.onTap});

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AudioService.tap();
        onTap();
      },
      child: Container(
        width: double.infinity,
        decoration: duelPanel(radius: 14, rim: color, glow: true),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(16, color: Colors.white, weight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
