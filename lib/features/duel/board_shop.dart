import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
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
import 'lobby_data.dart';
import '../../l10n/strings.dart';

enum BoardKind { pool, carrom, ludo }

/// Pool, carrom and ludo cloths. Free boards come first. A bought board stays
/// selected until the player picks another one they own.
class BoardShopScreen extends ConsumerWidget {
  const BoardShopScreen({super.key, required this.kind});

  final BoardKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final title = switch (kind) {
      BoardKind.pool => t.poolTableBtn,
      BoardKind.carrom => t.carromTableBtn,
      BoardKind.ludo => t.ludoBoardBtn,
    };
    final boardPrices = ref.watch(lobbyProvider).valueOrNull?.boardPrices;
    final items = _items(kind, boardPrices);
    return DuelPage(
      title: title,
      expanded: true,
      sideBack: true,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final item in items)
                  _BoardCard(
                    item: item,
                    selected: _selected(settings) == item.id,
                    owned: item.price == 0 || _owned(settings).contains(item.id),
                    onPick: () => _pick(context, ref, item),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _selected(AppSettings s) => switch (kind) {
        BoardKind.pool => s.tableSkin,
        BoardKind.carrom => s.carromBoard,
        BoardKind.ludo => s.ludoBoard,
      };

  List<String> _owned(AppSettings s) => switch (kind) {
        BoardKind.pool => s.ownedPoolTables,
        BoardKind.carrom => s.ownedCarromBoards,
        BoardKind.ludo => s.ownedLudoBoards,
      };

  Future<void> _pick(BuildContext context, WidgetRef ref, _BoardItem item) async {
    AudioService.tap();
    final settings = ref.read(settingsProvider);
    final owned = item.price == 0 || _owned(settings).contains(item.id);
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
}

class _BoardItem {
  const _BoardItem(this.id, this.name, this.price, this.preview);
  final String id;
  final String name;
  final int price;
  final Widget preview;
}

int _boardPrice(Map<String, Map<String, int>>? catalog, String kind, String id, int fallback) {
  return catalog?[kind]?[id] ?? fallback;
}

List<_BoardItem> _items(BoardKind kind, Map<String, Map<String, int>>? boardPrices) {
  final kindKey = kind.name;
  switch (kind) {
    case BoardKind.pool:
      final skins = DemoData.tableSkins;
      final items = [
        for (var i = 0; i < skins.length; i++)
          _BoardItem(
            skins[i].id,
            skins[i].name,
            _boardPrice(boardPrices, kindKey, skins[i].id, i < 3 ? 0 : 2000 * (i - 2)),
            TableArt(skin: skins[i], width: 168),
          ),
      ];
      items.sort((a, b) => a.price.compareTo(b.price));
      return items;
    case BoardKind.carrom:
      const fallback = {'classic': 0, 'walnut': 0, 'royal': 4000, 'emerald': 6000, 'cherry': 8000, 'midnight': 12000};
      final items = [
        for (final b in boardSkins)
          _BoardItem(
            b.id,
            b.name,
            _boardPrice(boardPrices, kindKey, b.id, fallback[b.id] ?? 8000),
            CustomPaint(size: const Size(120, 120), painter: CarromBoardPainter(b)),
          ),
      ];
      items.sort((a, b) => a.price.compareTo(b.price));
      return items;
    case BoardKind.ludo:
      final items = [
        for (final theme in ludoBoardThemes)
          _BoardItem(
            theme.id,
            theme.name,
            _boardPrice(boardPrices, kindKey, theme.id, theme.price),
            _LudoSwatch(theme),
          ),
      ];
      items.sort((a, b) => a.price.compareTo(b.price));
      return items;
  }
}

class _BoardCard extends ConsumerWidget {
  const _BoardCard({required this.item, required this.selected, required this.owned, required this.onPick});

  final _BoardItem item;
  final bool selected;
  final bool owned;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final label = selected
        ? t.selectedBoard
        : owned
            ? (item.price == 0 ? t.freeBoard : t.useBoard)
            : formatCoins(item.price);
    final accent = selected ? DuelColors.gold : (owned ? DuelColors.green : DuelColors.rim);
    return GestureDetector(
      onTap: onPick,
      child: Container(
        width: 200,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        decoration: duelPanel(radius: 16, rim: accent, glow: selected),
        child: Column(
          children: [
            SizedBox(height: 110, child: Center(child: item.preview)),
            const SizedBox(height: 8),
            Text(item.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(14, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(label, style: AppText.label(13, color: accent, weight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _LudoSwatch extends StatelessWidget {
  const _LudoSwatch(this.theme);

  final LudoBoardTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(color: theme.field, borderRadius: BorderRadius.circular(10), border: Border.all(color: theme.grid, width: 3)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DecoratedBox(
          decoration: BoxDecoration(color: theme.track, borderRadius: BorderRadius.circular(6)),
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
