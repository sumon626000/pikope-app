import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../../l10n/strings.dart';
import '../online/session.dart';
import 'lobby_data.dart';
import 'zinipay_browser_url.dart';

const _pendingKey = 'pending_zinipay_deposit_id';

Future<void> rememberPendingZiniPayDeposit(int depositId) async {
  if (!kIsWeb || depositId <= 0) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_pendingKey, depositId);
}

Future<void> clearPendingZiniPayDeposit() async {
  if (!kIsWeb) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_pendingKey);
}

/// After ZiniPay redirect back to the web app (?zinipay_deposit=&status=).
Future<void> resolveZiniPayReturnIfAny(BuildContext context, WidgetRef ref) async {
  if (!kIsWeb || !context.mounted) return;
  final t = ref.read(stringsProvider);
  final uri = Uri.base;
  var depositId = int.tryParse(uri.queryParameters['zinipay_deposit'] ?? '');
  final status = uri.queryParameters['status'];
  final fromUrl = depositId != null && depositId > 0;
  if (!fromUrl) {
    final prefs = await SharedPreferences.getInstance();
    depositId = prefs.getInt(_pendingKey);
  }
  if (depositId == null || depositId <= 0) return;

  if (status == 'cancel') {
    await clearPendingZiniPayDeposit();
    if (fromUrl) stripZiniPayQueryFromBrowserUrl();
    if (context.mounted) {
      showDuelMessage(context, title: t.addCoinTitle, body: t.paymentCancelled, icon: Icons.cancel_outlined);
    }
    return;
  }

  try {
    await ref.read(sessionProvider.notifier).finishZiniPayDeposit(depositId);
    await ref.read(lobbyProvider.notifier).refresh();
    await clearPendingZiniPayDeposit();
    if (fromUrl) stripZiniPayQueryFromBrowserUrl();
    if (context.mounted) {
      showDuelMessage(context,
          title: t.autoAddSuccess, body: t.autoAddSuccessBody, icon: Icons.check_circle_rounded);
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      showDuelMessage(context,
          title: t.autoAddPending, body: t.maybeApi(e.message), icon: Icons.hourglass_top_rounded);
    }
  }
}
