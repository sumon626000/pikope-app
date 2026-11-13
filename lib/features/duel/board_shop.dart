import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/audio_service.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../../data/api_client.dart';
import '../../data/demo_data.dart';
import '../online/session.dart';
import '../carrom/carrom_board.dart';
import '../carrom/carrom_skins.dart';
import '../game/widgets/table_art.dart';
import '../ludo/ludo_board.dart';
import 'duel_chrome.dart';
import 'item_cards.dart';
import 'lobby_data.dart';
import '../../l10n/strings.dart';

enum BoardKind { pool, carrom, ludo }

/// One board / table / cloth on offer.
class BoardItem {
  const BoardItem(this.id, this.name, this.price, this.preview);
  final String id;
  final String name;
  final int price;
  final Widget preview;
}

String selectedBoard(BoardKind kind, AppSettings s) => switch (kind) {
      BoardKind.pool => s.tableSkin,
      BoardKind.carrom => s.carromBoard,
      BoardKind.ludo => s.ludoBoard,
    };

List<String> ownedBoards(BoardKind kind, AppSettings s) => switch (kind) {
      BoardKind.pool => s.ownedPoolTables,
      BoardKind.carrom => s.ownedCarromBoards,
      BoardKind.ludo => s.ownedLudoBoards,
    };

int _boardPrice(Map<String, Map<String, int>>? catalog, String kind, String id, int fallback) {
  return catalog?[kind]?[id] ?? fallback;
}

/// Catalogue of a kind, free boards first.
List<BoardItem> boardItems(BoardKind kind, Map<String, Map<String, int>>? boardPrices) {
  final kindKey = kind.name;
  switch (kind) {
    case BoardKind.pool:
      final skins = DemoData.tableSkins;
      final items = [
        for (var i = 0; i < skins.length; i++)
          BoardItem(
            skins[i].id,
            skins[i].name,
            _boardPrice(boardPrices, kindKey, skins[i].id, i < 3 ? 0 : 2000 * (i - 2)),
            TableArt(skin: skins[i], width: 290),
          ),
      ];
      items.sort((a, b) => a.price.compareTo(b.price));
      return items;
    case BoardKind.carrom:
      const fallback = {'classic': 0, 'walnut': 0, 'royal': 4000, 'emerald': 6000, 'cherry': 8000, 'midnight': 12000};
      final items = [
        for (final b in boardSkins)
          BoardItem(
            b.id,
            b.name,
            _boardPrice(boardPrices, kindKey, b.id, fallback[b.id] ?? 8000),
            CustomPaint(size: const Size(170, 170), painter: CarromBoardPainter(b)),
          ),
      ];
      items.sort((a, b) => a.price.compareTo(b.price));
      return items;
    case BoardKind.ludo:
      final items = [
        for (final theme in ludoBoardThemes)
          BoardItem(
            theme.id,
            theme.name,
            _boardPrice(boardPrices, kindKey, theme.id, theme.price),
            LudoSwatch(theme, size: 170),
          ),
      ];
      items.sort((a, b) => a.price.compareTo(b.price));
      return items;
  }
}

/// Select (or buy, then select) a board. A bought board stays selected
/// until the player picks another one they own.
Future<void> pickBoard(BuildContext context, WidgetRef ref, BoardKind kind, BoardItem item) async {
  AudioService.tap();
  final settings = ref.read(settingsProvider);
  final owned = item.price == 0 || ownedBoards(kind, settings).contains(item.id);
  final t = ref.read(stringsProvider);
  if (!owned && settings.coins < item.price) {
    showDuelMessage(context, title: t.notEnoughCoin, body: formatPicoCoins(item.price), icon: Icons.lock_rounded);
    return;
  }
  final api = ref.read(apiProvider);
  if (Env.hasBackend && api != null && ref.read(sessionProvider).signedIn) {
    try {
      final r = await api.post('/boards/select', {'kind': kind.name, 'id': item.id});
      final user = r['user'];
      if (user is Map<String, dynamic>) {
        ref.read(sessionProvider.notifier).adopt(user);
      }
      return;
    } on ApiException catch (e) {
      if (e.status != 404) {
        if (context.mounted) {
          showDuelMessage(context, title: t.notEnoughCoin, body: e.message, icon: Icons.lock_rounded);
        }
        return;
      }
    }
  }
  ref.read(settingsProvider.notifier).update((s) {
    final pool = [...s.ownedPoolTables];
    final carrom = [...s.ownedCarromBoards];
    final ludo = [...s.ownedLudoBoards];
    if (!owned) {
      switch (kind) {
        case BoardKind.pool:
          pool.add(item.id);
        case BoardKind.carrom:
          carrom.add(item.id);
        case BoardKind.ludo:
          ludo.add(item.id);
      }
    }
    return s.copyWith(
      coins: owned ? s.coins : s.coins - item.price,
      tableSkin: kind == BoardKind.pool ? item.id : null,
      carromBoard: kind == BoardKind.carrom ? item.id : null,
      ludoBoard: kind == BoardKind.ludo ? item.id : null,
      ownedPoolTables: pool,
      ownedCarromBoards: carrom,
      ownedLudoBoards: ludo,
    );
  });
}

/// Inventory cards for every board of a kind.
List<Widget> boardCards(BuildContext context, WidgetRef ref, BoardKind kind) {
  final t = ref.watch(stringsProvider);
  final settings = ref.watch(settingsProvider);
  final items = boardItems(kind, ref.watch(lobbyProvider).valueOrNull?.boardPrices);
  return [
    for (final item in items)
      () {
        final selected = selectedBoard(kind, settings) == item.id;
        final owned = item.price == 0 || ownedBoards(kind, settings).contains(item.id);
        return InventoryItemCard(
          rarity: rarityForPrice(item.price),
          name: item.name,
          selected: selected,
          art: item.preview,
          trailing: Text(titleCase(owned ? (item.price == 0 ? t.freeBoard : t.useBoard) : formatCoins(item.price)), style: pcText(28, color: owned ? const Color(0xFF6CF0A0) : DesignColorsAlias.gold)),
          info: ItemStats([(t.navItems, kind == BoardKind.pool ? t.poolTableBtn : kind == BoardKind.carrom ? t.carromTableBtn : t.ludoBoardBtn, const Color(0xFF9FE4FF))]),
          action: selected
              ? ItemActionButton.using(t.selectedBoard)
              : owned
                  ? ItemActionButton.use(t.useBoard, onTap: () => pickBoard(context, ref, kind, item))
                  : ItemActionButton.buy(t.buy, price: item.price, onTap: () => pickBoard(context, ref, kind, item)),
        );
      }(),
  ];
}

/// Pool, carrom and ludo cloths as a page of their own (opened from the shop).
class BoardShopScreen extends ConsumerWidget {
  const BoardShopScreen({super.key, required this.kind});

  final BoardKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final title = switch (kind) {
      BoardKind.pool => t.poolTableBtn,
      BoardKind.carrom => t.carromTableBtn,
      BoardKind.ludo => t.ludoBoardBtn,
    };
    return DuelPage(
      title: title,
      scroll: true,
      child: Column(children: boardCards(context, ref, kind)),
    );
  }
}

/// Ludo board colours as a swatch.
class LudoSwatch extends StatelessWidget {
  const LudoSwatch(this.theme, {super.key, this.size = 108});

  final LudoBoardTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: theme.field, borderRadius: BorderRadius.circular(size * 0.09), border: Border.all(color: theme.grid, width: 3)),
      child: Padding(
        padding: EdgeInsets.all(size * 0.09),
        child: DecoratedBox(
          decoration: BoxDecoration(color: theme.track, borderRadius: BorderRadius.circular(size * 0.05)),
          child: Row(
            children: [
              Expanded(child: ColoredBox(color: LudoBoard.colours[1])),
              Expanded(child: ColoredBox(color: LudoBoard.colours[2])),
              Expanded(child: ColoredBox(color: LudoBoard.colours[0])),
              Expanded(child: ColoredBox(color: LudoBoard.colours[3])),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gold text colour shortcut (kept local to avoid pulling the whole palette).
abstract final class DesignColorsAlias {
  static const gold = Color(0xFFF5B942);
}
