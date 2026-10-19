import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../../data/cues.dart';
import '../misc/settings_screen.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import '../../l10n/strings.dart';
import 'lobby_data.dart';

/// The cue rack: buy with coins, pick the one to play with.
/// With [ownedOnly] it is the player's inventory ("ITEMS").
/// With [asShop] the same rack is the shop.
class CuesScreen extends ConsumerStatefulWidget {
  const CuesScreen({super.key, this.ownedOnly = false, this.asShop = false});

  final bool ownedOnly;
  final bool asShop;

  @override
  ConsumerState<CuesScreen> createState() => _CuesScreenState();
}

class _CuesScreenState extends ConsumerState<CuesScreen> {
  String? _busy;

  Future<void> _run(String id, Future<void> Function() action, {String? done}) async {
    setState(() => _busy = id);
    try {
      await action();
      if (done != null) ref.read(audioProvider).play(Sfx.success);
    } on ApiException catch (e) {
      if (mounted) {
        final t = ref.read(stringsProvider);
        showDuelMessage(context,
            title: e.code.startsWith('not_enough') ? e.message.toUpperCase() : t.notDone,
            body: e.code.startsWith('not_enough') ? t.notEnoughCueBody : t.maybeApi(e.message),
            icon: Icons.lock_rounded);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _buy(CueOffer cue) async {
    final t = ref.read(stringsProvider);
    final yes = await showDuelDialog<bool>(
      context,
      barrierColor: const Color(0xB3000000),
      builder: (dialog) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(22),
          decoration: duelPanel(rim: DuelColors.rimLight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.buyCue(cue.name), textAlign: TextAlign.center, style: AppText.label(18, weight: FontWeight.w900)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const PikoCoinIcon(size: 30),
                  const SizedBox(width: 8),
                  Text(formatCoins(cue.price), style: AppText.label(22, color: DuelColors.gold, weight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DuelButton(label: t.buy, width: 150, height: 42, fontSize: 16, onPressed: () => Navigator.of(dialog).pop(true)),
                  const SizedBox(width: 10),
                  DuelButton(
                      label: t.cancel,
                      width: 150,
                      height: 42,
                      fontSize: 16,
                      color: DuelColors.rimLight,
                      onPressed: () => Navigator.of(dialog).pop(false)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (yes == true) await _run(cue.id, () => ref.read(lobbyProvider.notifier).buyCue(cue.id), done: 'bought');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final lobby = ref.watch(lobbyProvider);
    final session = ref.watch(sessionProvider);
    final all = lobby.valueOrNull?.cues ?? const <CueOffer>[];
    final owned = session.cues;
    final cues = [for (final c in all) if (!widget.ownedOnly || owned.contains(c.id)) c];
    return DuelPage(
      title: widget.ownedOnly ? t.myItems : (widget.asShop ? t.shopTitleShort : t.navCues),
      sub: widget.ownedOnly ? t.cuesSubOwned : t.cuesSubBuy,
      child: lobby.valueOrNull == null
          ? Center(
              child: lobby.hasError
                  ? Text(t.offlineServer, style: AppText.label(20, color: DuelColors.red))
                  : const CircularProgressIndicator(color: DuelColors.silver))
          : Column(
              children: [
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.36,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      for (final cue in cues)
                        _CueCard(
                          cue: cue,
                          owned: owned.contains(cue.id),
                          equipped: session.cue == cue.id,
                          busy: _busy == cue.id,
                          onBuy: () => _buy(cue),
                          onEquip: () => _run(cue.id, () => ref.read(lobbyProvider.notifier).equipCue(cue.id)),
                          t: t,
                        ),
                      if (widget.ownedOnly)
                        GestureDetector(
                          onTap: () {
                            AudioService.tap();
                            pushScreen(context, const SettingsScreen());
                          },
                          child: Container(
                            decoration: duelPanel(radius: 16, rim: DuelColors.rim),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.table_restaurant_rounded, color: DuelColors.silver, size: 70),
                                const SizedBox(height: 8),
                                Text(t.tablesProfile, style: AppText.label(18, color: DuelColors.silver, weight: FontWeight.w900)),
                                Text(t.chooseTableLook, style: AppText.label(11, color: DuelColors.dim)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CueCard extends StatelessWidget {
  const _CueCard({required this.cue, required this.owned, required this.equipped, required this.busy, required this.onBuy, required this.onEquip, required this.t});

  final CueOffer cue;
  final bool owned;
  final bool equipped;
  final bool busy;
  final VoidCallback onBuy;
  final VoidCallback onEquip;
  final AppStrings t;

  @override
  Widget build(BuildContext context) {
    final style = CueStyle.of(cue.id);
    return Container(
      decoration: duelPanel(radius: 16, rim: equipped ? DuelColors.green : DuelColors.rim, glow: equipped),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          Expanded(child: CustomPaint(size: Size.infinite, painter: _CuePreviewPainter(style))),
          const SizedBox(height: 6),
          Text(cue.name.toUpperCase(), maxLines: 1, style: AppText.label(17, color: Colors.white, weight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (equipped)
            Container(
              height: 40,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, color: DuelColors.green, size: 24),
                  const SizedBox(width: 6),
                  Text(t.inUse, style: AppText.label(16, color: DuelColors.green, weight: FontWeight.w900)),
                ],
              ),
            )
          else if (owned)
            DuelButton(label: busy ? '...' : t.useCue, width: 170, height: 40, fontSize: 16, color: DuelColors.blue, onPressed: busy ? null : onEquip)
          else
            GestureDetector(
              onTap: busy
                  ? null
                  : () {
                      AudioService.tap();
                      onBuy();
                    },
              child: Container(
                width: 190,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2038),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DuelColors.gold, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const PikoCoinIcon(size: 26),
                    const SizedBox(width: 8),
                    Text(busy ? '...' : formatCoins(cue.price), style: AppText.label(17, color: DuelColors.gold, weight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CuePreviewPainter extends CustomPainter {
  _CuePreviewPainter(this.style);

  final CueStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    // Lying across the card, tip to the left, slightly raised.
    final tip = Offset(size.width * 0.04, size.height * 0.72);
    final end = Offset(size.width * 0.97, size.height * 0.26);
    final v = end - tip;
    paintCueStick(canvas, tip, v / v.distance, v.distance, 22, style);
  }

  @override
  bool shouldRepaint(_CuePreviewPainter old) => old.style != style;
}
