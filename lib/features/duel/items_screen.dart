import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../../data/cues.dart';
import '../online/session.dart';
import '../start/auth_prompt.dart';
import '../misc/settings_screen.dart';
import 'board_shop.dart';
import 'duel_chrome.dart';
import 'item_cards.dart';
import 'shop_screen.dart';
import '../../l10n/strings.dart';
import 'lobby_data.dart';

/// Inventory in the reference's layout: player header, a tab strip (cues,
/// pool tables, carrom boards, ludo boards), a list of rarity cards with
/// Use / Using / Buy, and the five-tab bar with Items lit.
class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  late int _tab = widget.initialTab;
  String? _busy;

  Future<void> _run(
    String id,
    Future<void> Function() action, {
    bool celebrate = false,
  }) async {
    setState(() => _busy = id);
    try {
      await action();
      if (celebrate) ref.read(audioProvider).play(Sfx.success);
    } on ApiException catch (e) {
      if (mounted) {
        final t = ref.read(stringsProvider);
        showDuelMessage(
          context,
          title: e.code.startsWith('not_enough')
              ? e.message.toUpperCase()
              : t.notDone,
          body: e.code.startsWith('not_enough')
              ? t.notEnoughCueBody
              : t.maybeApi(e.message),
          icon: Icons.lock_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _buyCue(CueOffer cue) async {
    final t = ref.read(stringsProvider);
    final yes = await showDuelDialog<bool>(
      context,
      builder: (dialog) => PcDialog(
        title: t.buyCue(cue.name),
        width: 820,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const PikoCoinIcon(size: 72),
                const SizedBox(width: 14),
                Text(
                  formatCoins(cue.price),
                  style: pcText(48, color: DesignColors.pcGold),
                ),
              ],
            ),
            const SizedBox(height: 28),
            PcButton(
              label: t.buy,
              style: PcButtonStyle.gold,
              width: 640,
              height: 84,
              fontSize: 34,
              onPressed: () => Navigator.of(dialog).pop(true),
            ),
            const SizedBox(height: 14),
            PcButton(
              label: t.cancel,
              style: PcButtonStyle.gray,
              width: 640,
              height: 76,
              fontSize: 30,
              onPressed: () => Navigator.of(dialog).pop(false),
            ),
          ],
        ),
      ),
    );
    if (yes == true)
      await _run(
        cue.id,
        () => ref.read(lobbyProvider.notifier).buyCue(cue.id),
        celebrate: true,
      );
  }

  List<Widget> _cueCards(AppStrings t) {
    final lobby = ref.watch(lobbyProvider);
    final session = ref.watch(sessionProvider);
    final cues =
        lobby.valueOrNull?.cues ??
        [
          for (final s in CueStyle.all)
            CueOffer(
              id: s.id,
              name: s.name,
              price: 0,
              currency: 'coins',
              owned: s.id == 'classic',
            ),
        ];
    final owned = session.cues;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Text(
          t.cuesSamePlayHint,
          textAlign: TextAlign.center,
          style: pcText(
            26,
            color: DesignColors.pcTextDim,
            weight: FontWeight.w500,
          ),
        ),
      ),
      for (final cue in cues)
        () {
          final isOwned = owned.contains(cue.id) || cue.owned;
          final equipped = session.cue == cue.id;
          final busy = _busy == cue.id;
          final rarity = rarityForPrice(cue.price);
          return InventoryItemCard(
            rarity: rarity,
            name: cue.name,
            selected: equipped,
            trailing: Text(
              titleCase(isOwned ? t.inUse : formatCoins(cue.price)),
              style: pcText(
                28,
                color: isOwned ? const Color(0xFF6CF0A0) : DesignColors.pcGold,
              ),
            ).withOpacity(isOwned && !equipped ? 0 : 1),
            art: SizedBox(
              width: 940,
              height: 150,
              child: CueStickPreview(cueId: cue.id, stroke: 26),
            ),
            info: ItemStats([
              (t.navCues, rarity.label, rarity.colors.first),
              ('ID', cue.id.toUpperCase(), const Color(0xFF9FE4FF)),
            ]),
            action: equipped
                ? ItemActionButton.using(t.inUse)
                : isOwned
                ? ItemActionButton.use(
                    busy ? '...' : t.useCue,
                    onTap: busy
                        ? null
                        : () => _run(
                            cue.id,
                            () => ref
                                .read(lobbyProvider.notifier)
                                .equipCue(cue.id),
                          ),
                  )
                : ItemActionButton.buy(
                    busy ? '...' : t.buy,
                    price: cue.price,
                    onTap: busy ? null : () => _buyCue(cue),
                  ),
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final registered = hasRegisteredAccount(ref);
    final lobby = ref.watch(lobbyProvider);
    final tabs = [t.navCues, t.poolTableBtn, t.carromTableBtn, t.ludoBoardBtn];
    final cards = switch (_tab) {
      0 => _cueCards(t),
      1 => boardCards(context, ref, BoardKind.pool),
      2 => boardCards(context, ref, BoardKind.carrom),
      _ => boardCards(context, ref, BoardKind.ludo),
    };
    return PcPage(
      header: PcHeader(
        avatar: settings.avatar,
        name: settings.name,
        registered: registered,
        level: session.level,
        coins: lobbyDisplayCoins(ref),
        gems: registered ? session.gems : null,
        placeholder: t.signUpOrLogin,
        onProfile: () => pushScreen(context, const SettingsScreen()),
        onWallet: () => pushScreen(context, const ShopScreen()),
      ),
      tabs: PcTabs(
        labels: tabs,
        index: _tab,
        onChanged: (i) {
          AudioService.tap();
          setState(() => _tab = i);
        },
      ),
      panel: false,
      scroll: true,
      bodyPadding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
      nav: duelTabNav(context, ref, active: 3),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_tab == 0 && lobby.valueOrNull == null && lobby.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                titleCase(t.offlineServer),
                textAlign: TextAlign.center,
                style: pcText(28, color: DuelColors.red),
              ),
            ),
          ...cards,
        ],
      ),
    );
  }
}

extension on Widget {
  Widget withOpacity(double o) => Opacity(opacity: o, child: this);
}
