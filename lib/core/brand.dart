/// User-facing product name (logo, store listing, legal documents).
abstract final class Brand {
  static const name = 'PikoPe';
}

/// In-app currency: 1 Pico coin = 1 BDT (display rate for players).
abstract final class PicoCoin {
  static const name = 'Pico coin';
  static const asset = 'assets/images/piko_coin.png';
  static const bdtPerCoin = 1;
}
