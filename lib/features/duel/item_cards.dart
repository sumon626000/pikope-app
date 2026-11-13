import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';

/// Rarity badge of an inventory card, by price tier (the reference labels
/// its cues STANDARD / EPIC / ULTIMATE / MYTHIC).
enum ItemRarity { standard, rare, epic, ultimate, mythic }

ItemRarity rarityForPrice(int price) {
  if (price <= 0) return ItemRarity.standard;
  if (price < 3000) return ItemRarity.rare;
  if (price < 8000) return ItemRarity.epic;
  if (price < 15000) return ItemRarity.ultimate;
  return ItemRarity.mythic;
}

extension ItemRarityLook on ItemRarity {
  String get label => switch (this) {
        ItemRarity.standard => 'STANDARD',
        ItemRarity.rare => 'RARE',
        ItemRarity.epic => 'EPIC',
        ItemRarity.ultimate => 'ULTIMATE',
        ItemRarity.mythic => 'MYTHIC',
      };

  List<Color> get colors => switch (this) {
        ItemRarity.standard => const [Color(0xFF6CF0A0), Color(0xFF1FA85A)],
        ItemRarity.rare => const [Color(0xFF7FC4FF), Color(0xFF2F6BFF)],
        ItemRarity.epic => const [Color(0xFFC89CFF), Color(0xFF7B4DFF)],
        ItemRarity.ultimate => const [Color(0xFFFF8AC8), Color(0xFFE8368F)],
        ItemRarity.mythic => const [Color(0xFFFFE28A), Color(0xFFF0A020)],
      };
}

/// Full-width inventory card of the reference: rarity badge + name along
/// the top with [trailing] (level / owned) on the right, the art across the
/// middle, [info] bottom-left and the action button bottom-right.
class InventoryItemCard extends StatelessWidget {
  const InventoryItemCard({
    super.key,
    required this.rarity,
    required this.name,
    required this.art,
    required this.action,
    this.trailing,
    this.info,
    this.selected = false,
    this.artHeight = 170,
  });

  final ItemRarity rarity;
  final String name;
  final Widget art;
  final Widget action;
  final Widget? trailing;
  final Widget? info;
  final bool selected;
  final double artHeight;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.fromLTRB(26, 20, 26, 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF4A3A92), Color(0xFF3A2A7A)]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? DesignColors.pcGold : const Color(0xFF8C7CE8).withValues(alpha: 0.7), width: selected ? 3 : 2),
          boxShadow: [
            const BoxShadow(color: Color(0x88000000), blurRadius: 14, offset: Offset(0, 6)),
            if (selected) BoxShadow(color: DesignColors.pcGold.withValues(alpha: 0.35), blurRadius: 18),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RarityBadge(rarity),
                const SizedBox(width: 16),
                Expanded(child: Text(titleCase(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: pcText(34))),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(height: artHeight, child: Center(child: art)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: info ?? const SizedBox.shrink()),
                const SizedBox(width: 16),
                action,
              ],
            ),
          ],
        ),
      );
}

/// Italic, gradient-coloured rarity word.
class RarityBadge extends StatelessWidget {
  const RarityBadge(this.rarity, {super.key});

  final ItemRarity rarity;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (b) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: rarity.colors).createShader(b),
        child: Text(
          rarity.label,
          style: pcText(30, shadow: false).copyWith(
            fontStyle: FontStyle.italic,
            letterSpacing: 1,
            shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
        ),
      );
}

/// "Force 550  Spin 300" style stat run: label + coloured value pairs.
class ItemStats extends StatelessWidget {
  const ItemStats(this.stats, {super.key});

  final List<(String, String, Color)> stats;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 22,
        runSpacing: 6,
        children: [
          for (final (label, value, color) in stats)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titleCase(label), style: pcText(28, color: const Color(0xFFD9D2FF), weight: FontWeight.w500)),
                const SizedBox(width: 8),
                Text(value, style: pcText(30, color: color)),
              ],
            ),
        ],
      );
}

/// Action button of a card: grey "Using", gold "Use", or gold "Buy" with the
/// coin price under the word.
class ItemActionButton extends StatelessWidget {
  const ItemActionButton.using(this.label, {super.key})
      : price = null,
        onTap = null,
        gold = false;

  const ItemActionButton.use(this.label, {super.key, required this.onTap})
      : price = null,
        gold = true;

  const ItemActionButton.buy(this.label, {super.key, required this.price, required this.onTap}) : gold = true;

  final String label;
  final int? price;
  final VoidCallback? onTap;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final colors = gold ? const [Color(0xFFF9C64A), Color(0xFFD08A10)] : const [Color(0xFF9CA1B8), Color(0xFF5E6380)];
    return PressScale(
      onTap: onTap,
      enabled: onTap != null,
      scale: 0.95,
      child: Container(
        width: 240,
        height: price == null ? 84 : 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(titleCase(label), style: pcText(34)),
            if (price != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PikoCoinIcon(size: 30),
                  const SizedBox(width: 6),
                  Text(formatCoins(price!), style: pcText(26)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
