import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import 'board_shop.dart';
import 'cues_screen.dart';
import 'duel_chrome.dart';
import '../../l10n/strings.dart';

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
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.shopItemsSection, style: AppText.label(26, color: DuelColors.gold, weight: FontWeight.w900)),
            const SizedBox(height: 14),
            Row(
              children: [
                _ItemDoor(label: t.poolTableBtn, color: DuelColors.green, icon: Icons.crop_16_9_rounded, onTap: () => pushScreen(context, const BoardShopScreen(kind: BoardKind.pool))),
                const SizedBox(width: 16),
                _ItemDoor(label: t.carromTableBtn, color: const Color(0xFFD9A34A), icon: Icons.grid_on_rounded, onTap: () => pushScreen(context, const BoardShopScreen(kind: BoardKind.carrom))),
                const SizedBox(width: 16),
                _ItemDoor(label: t.ludoBoardBtn, color: const Color(0xFFE8721C), icon: Icons.casino_rounded, onTap: () => pushScreen(context, const BoardShopScreen(kind: BoardKind.ludo))),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _ItemDoor(label: t.navCues, color: DuelColors.blue, icon: NavTile.cuesIcon, onTap: () => pushScreen(context, const CuesScreen(asShop: true))),
              ],
            ),
          ],
        ),
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
    return Expanded(
      child: GestureDetector(
        onTap: () {
          AudioService.tap();
          onTap();
        },
        child: Container(
          height: 104,
          decoration: duelPanel(radius: 16, rim: color, glow: true),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(width: 12),
              Flexible(child: Text(label, style: AppText.label(22, color: Colors.white, weight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}
