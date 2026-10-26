import 'package:flutter/material.dart';

import '../../core/duel_ui.dart';
import '../../core/root_nav.dart';
import '../../data/api_client.dart';
import 'shop_screen.dart';

bool isNotEnoughCoins(ApiException e) =>
    e.code.startsWith('not_enough') || e.message.toLowerCase().contains('not enough');

/// Popup: not enough balance, then Buy Coin opens the shop or Cancel dismisses.
Future<void> promptNotEnoughBalance(BuildContext context, {int? need, int? have}) async {
  final buy = await showNotEnoughBalanceDialog(context, need: need, have: have);
  if (!buy) return;
  final nav = rootNavigatorKey.currentState ?? (context.mounted ? Navigator.of(context) : null);
  if (nav == null) return;
  await nav.push(MaterialPageRoute<void>(builder: (_) => const ShopScreen(initialTab: 0)));
}
