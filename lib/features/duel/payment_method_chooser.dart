import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';
import '../../l10n/strings.dart';
import 'lobby_data.dart';

enum ShopPayMethod { localMfs, crypto }

/// Always shows both MFS + crypto buttons so players can choose.
Future<ShopPayMethod?> showShopPaymentMethodChooser(
  BuildContext context, {
  required bool localAvailable,
  required bool cryptoAvailable,
  required int coinsPerUsd,
}) {
  if (!localAvailable && !cryptoAvailable) {
    return Future<ShopPayMethod?>.value(null);
  }
  return showDuelDialog<ShopPayMethod>(
    context,
    barrierColor: DesignAuth.overlayScrim,
    builder: (dialog) => Consumer(
      builder: (context, ref, _) {
        final t = ref.watch(stringsProvider);
        return PcDialog(
          title: t.choosePaymentMethod,
          width: 900,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.choosePaymentBody,
                textAlign: TextAlign.center,
                style: pcText(
                  28,
                  color: DesignColors.pcTextDim,
                  weight: FontWeight.w500,
                ).copyWith(height: 1.3),
              ),
              const SizedBox(height: 10),
              Text(
                t.bdtCoinParityNotice,
                textAlign: TextAlign.center,
                style: pcText(
                  24,
                  color: DesignColors.pcGold,
                  weight: FontWeight.w600,
                ).copyWith(height: 1.25),
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PayArtButton(
                      asset: 'assets/images/payments/pay_mfs_combo.jpg',
                      label: t.payLocalMfs,
                      notice: t.payLocalMfsNotice,
                      enabled: localAvailable,
                      onTap: () {
                        if (!localAvailable) return;
                        Navigator.of(dialog).pop(ShopPayMethod.localMfs);
                      },
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _PayArtButton(
                      asset: 'assets/images/payments/pay_crypto_wallet.jpg',
                      label: t.payCryptoUsd,
                      notice: t.usdCoinsNotice(coinsPerUsd),
                      enabled: cryptoAvailable,
                      onTap: () {
                        if (!cryptoAvailable) return;
                        Navigator.of(dialog).pop(ShopPayMethod.crypto);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

bool shopLocalPayAvailable(CoinDepositConfig cfg) =>
    cfg.autoEnabled || (cfg.manualEnabled && cfg.agents.isNotEmpty);

bool shopCryptoPayAvailable(CoinDepositConfig cfg) => cfg.cryptoEnabled;

class _PayArtButton extends StatelessWidget {
  const _PayArtButton({
    required this.asset,
    required this.label,
    required this.notice,
    required this.enabled,
    required this.onTap,
  });

  final String asset;
  final String label;
  final String notice;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: PressScale(
        onTap: enabled ? onTap : null,
        scale: 0.96,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF8C7CE8),
                    width: 3,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x99000000),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFF1A1240),
                      child: Icon(
                        Icons.payments_rounded,
                        color: Colors.white70,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              titleCase(label),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: pcText(26),
            ),
            const SizedBox(height: 6),
            Text(
              notice,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: pcText(
                20,
                color: DesignColors.pcTextDim,
                weight: FontWeight.w500,
              ).copyWith(height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}
