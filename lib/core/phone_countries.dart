/// Dialing metadata for sign-in / sign-up (flag + country code picker).
class PhoneCountry {
  const PhoneCountry({
    required this.iso,
    required this.name,
    required this.dialCode,
    this.nationalMaxLength = 12,
    this.nationalMinLength = 4,
  });

  final String iso;
  final String name;
  final String dialCode;
  final int nationalMaxLength;
  final int nationalMinLength;

  String get flag {
    final u = iso.toUpperCase();
    if (u.length != 2) return '🌐';
    return String.fromCharCodes([
      u.codeUnitAt(0) + 0x1F1A5,
      u.codeUnitAt(1) + 0x1F1A5,
    ]);
  }

  String get dialDisplay => '+$dialCode';
}

/// All ISO countries with a dial code (Bangladesh included). Default follows device locale.
abstract final class PhoneCountries {
  static const _bd = PhoneCountry(
    iso: 'BD',
    name: 'Bangladesh',
    dialCode: '880',
    nationalMinLength: 10,
    nationalMaxLength: 10,
  );

  static final List<PhoneCountry> all = [
    _bd,
    const PhoneCountry(iso: 'IN', name: 'India', dialCode: '91', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'PK', name: 'Pakistan', dialCode: '92', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'NP', name: 'Nepal', dialCode: '977', nationalMinLength: 8, nationalMaxLength: 10),
    const PhoneCountry(iso: 'LK', name: 'Sri Lanka', dialCode: '94', nationalMinLength: 9, nationalMaxLength: 9),
    const PhoneCountry(iso: 'US', name: 'United States', dialCode: '1', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'GB', name: 'United Kingdom', dialCode: '44', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'AE', name: 'UAE', dialCode: '971', nationalMinLength: 8, nationalMaxLength: 9),
    const PhoneCountry(iso: 'SA', name: 'Saudi Arabia', dialCode: '966', nationalMinLength: 8, nationalMaxLength: 9),
    const PhoneCountry(iso: 'QA', name: 'Qatar', dialCode: '974', nationalMinLength: 8, nationalMaxLength: 8),
    const PhoneCountry(iso: 'KW', name: 'Kuwait', dialCode: '965', nationalMinLength: 8, nationalMaxLength: 8),
    const PhoneCountry(iso: 'OM', name: 'Oman', dialCode: '968', nationalMinLength: 8, nationalMaxLength: 8),
    const PhoneCountry(iso: 'BH', name: 'Bahrain', dialCode: '973', nationalMinLength: 8, nationalMaxLength: 8),
    const PhoneCountry(iso: 'MY', name: 'Malaysia', dialCode: '60', nationalMinLength: 9, nationalMaxLength: 10),
    const PhoneCountry(iso: 'SG', name: 'Singapore', dialCode: '65', nationalMinLength: 8, nationalMaxLength: 8),
    const PhoneCountry(iso: 'ID', name: 'Indonesia', dialCode: '62', nationalMinLength: 9, nationalMaxLength: 11),
    const PhoneCountry(iso: 'PH', name: 'Philippines', dialCode: '63', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'TH', name: 'Thailand', dialCode: '66', nationalMinLength: 9, nationalMaxLength: 9),
    const PhoneCountry(iso: 'VN', name: 'Vietnam', dialCode: '84', nationalMinLength: 9, nationalMaxLength: 10),
    const PhoneCountry(iso: 'CN', name: 'China', dialCode: '86', nationalMinLength: 11, nationalMaxLength: 11),
    const PhoneCountry(iso: 'JP', name: 'Japan', dialCode: '81', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'KR', name: 'South Korea', dialCode: '82', nationalMinLength: 9, nationalMaxLength: 10),
    const PhoneCountry(iso: 'AU', name: 'Australia', dialCode: '61', nationalMinLength: 9, nationalMaxLength: 9),
    const PhoneCountry(iso: 'NZ', name: 'New Zealand', dialCode: '64', nationalMinLength: 8, nationalMaxLength: 10),
    const PhoneCountry(iso: 'CA', name: 'Canada', dialCode: '1', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'DE', name: 'Germany', dialCode: '49', nationalMinLength: 10, nationalMaxLength: 11),
    const PhoneCountry(iso: 'FR', name: 'France', dialCode: '33', nationalMinLength: 9, nationalMaxLength: 9),
    const PhoneCountry(iso: 'IT', name: 'Italy', dialCode: '39', nationalMinLength: 9, nationalMaxLength: 10),
    const PhoneCountry(iso: 'ES', name: 'Spain', dialCode: '34', nationalMinLength: 9, nationalMaxLength: 9),
    const PhoneCountry(iso: 'NL', name: 'Netherlands', dialCode: '31', nationalMinLength: 9, nationalMaxLength: 9),
    const PhoneCountry(iso: 'BE', name: 'Belgium', dialCode: '32', nationalMinLength: 8, nationalMaxLength: 9),
    const PhoneCountry(iso: 'SE', name: 'Sweden', dialCode: '46', nationalMinLength: 9, nationalMaxLength: 10),
    const PhoneCountry(iso: 'NO', name: 'Norway', dialCode: '47', nationalMinLength: 8, nationalMaxLength: 8),
    const PhoneCountry(iso: 'DK', name: 'Denmark', dialCode: '45', nationalMinLength: 8, nationalMaxLength: 8),
    const PhoneCountry(iso: 'PL', name: 'Poland', dialCode: '48', nationalMinLength: 9, nationalMaxLength: 9),
    const PhoneCountry(iso: 'TR', name: 'Turkey', dialCode: '90', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'RU', name: 'Russia', dialCode: '7', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'ZA', name: 'South Africa', dialCode: '27', nationalMinLength: 9, nationalMaxLength: 9),
    const PhoneCountry(iso: 'NG', name: 'Nigeria', dialCode: '234', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'KE', name: 'Kenya', dialCode: '254', nationalMinLength: 9, nationalMaxLength: 9),
    const PhoneCountry(iso: 'EG', name: 'Egypt', dialCode: '20', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'BR', name: 'Brazil', dialCode: '55', nationalMinLength: 10, nationalMaxLength: 11),
    const PhoneCountry(iso: 'MX', name: 'Mexico', dialCode: '52', nationalMinLength: 10, nationalMaxLength: 10),
    const PhoneCountry(iso: 'AR', name: 'Argentina', dialCode: '54', nationalMinLength: 10, nationalMaxLength: 10),
  ]..sort((a, b) => a.name.compareTo(b.name));

  /// Sign-up / log-in always opens on Bangladesh (+880); user can change country.
  static PhoneCountry defaultCountry() => bangladesh;

  static PhoneCountry? byIso(String iso) {
    final u = iso.toUpperCase();
    for (final c in all) {
      if (c.iso == u) return c;
    }
    return null;
  }

  static PhoneCountry get bangladesh => _bd;
}
