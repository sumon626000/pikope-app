import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';
import '../../l10n/strings.dart';
import 'lobby_data.dart';

enum ShopPayMethod { localMfs, crypto }

/// Shows only the payment methods that are currently available.
/// Crypto/USD appears only when admin enables NOWPayments.
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
        final showLocal = localAvailable;
        final showCrypto = cryptoAvailable;
        final dual = showLocal && showCrypto;
        return PcDialog(
          title: t.choosePaymentMethod,
          width: dual ? 900 : 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DuelLogo(height: 64),
              const SizedBox(height: 18),
              Text(
                dual ? t.choosePaymentBody : t.chooseLocalPaymentBody,
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
              if (showCrypto) ...[
                const SizedBox(height: 8),
                Text(
                  t.usdCoinsNotice(coinsPerUsd),
                  textAlign: TextAlign.center,
                  style: pcText(
                    22,
                    color: DesignColors.pcTextDim,
                    weight: FontWeight.w500,
                  ).copyWith(height: 1.25),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showLocal)
                    Expanded(
                      child: _PayArtButton(
                        asset: 'assets/images/payments/pay_mfs_combo.jpg',
                        label: t.payLocalMfs,
                        notice: t.payLocalMfsNotice,
                        onTap: () =>
                            Navigator.of(dialog).pop(ShopPayMethod.localMfs),
                      ),
                    ),
                  if (showLocal && showCrypto) const SizedBox(width: 18),
                  if (showCrypto)
                    Expanded(
                      child: _PayArtButton(
                        asset: 'assets/images/payments/pay_crypto_wallet.jpg',
                        label: t.payCryptoUsd,
                        notice: t.usdCoinsNotice(coinsPerUsd),
                        onTap: () =>
                            Navigator.of(dialog).pop(ShopPayMethod.crypto),
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
    required this.onTap,
  });

  final String asset;
  final String label;
  final String notice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
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
    );
  }
}
