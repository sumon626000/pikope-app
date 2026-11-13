import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';
import '../../l10n/strings.dart';
import 'lobby_data.dart';

enum ShopPayMethod { localMfs, crypto }

/// Two big image buttons: local MFS (bKash/Nagad/Rocket) and crypto wallet.
Future<ShopPayMethod?> showShopPaymentMethodChooser(
  BuildContext context, {
  required bool localAvailable,
  required bool cryptoAvailable,
}) {
  if (!localAvailable && !cryptoAvailable) {
    return Future<ShopPayMethod?>.value(null);
  }
  if (localAvailable && !cryptoAvailable) {
    return Future<ShopPayMethod?>.value(ShopPayMethod.localMfs);
  }
  if (!localAvailable && cryptoAvailable) {
    return Future<ShopPayMethod?>.value(ShopPayMethod.crypto);
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
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _PayArtButton(
                      asset: 'assets/images/payments/pay_mfs_combo.jpg',
                      label: t.payLocalMfs,
                      onTap: () =>
                          Navigator.of(dialog).pop(ShopPayMethod.localMfs),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _PayArtButton(
                      asset: 'assets/images/payments/pay_crypto_wallet.jpg',
                      label: t.payCrypto,
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
    required this.onTap,
  });

  final String asset;
  final String label;
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
          const SizedBox(height: 14),
          Text(
            titleCase(label),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: pcText(26),
          ),
        ],
      ),
    );
  }
}
