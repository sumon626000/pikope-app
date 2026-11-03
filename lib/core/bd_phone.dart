import '../l10n/strings.dart';
import 'phone_countries.dart';

/// Bangladesh mobile input: user types 10 digits after +880 (1XXXXXXXXX).
class BdPhone {
  /// Sends `phone` to the API: local 10 digits, or full +880 / 880 form.
  static String apiPayload(String localOrFull) {
    return PhoneInput.apiPayload(localOrFull, PhoneCountries.bangladesh);
  }

  static bool validLocal(String local) {
    final d = local.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^1[3-9]\d{8}$').hasMatch(d);
  }

  static String? validationMessage(String local, [AppStrings? l10n]) {
    return PhoneInput.validationMessage(local, PhoneCountries.bangladesh, l10n);
  }
}

/// International mobile: national digits + selected [PhoneCountry].
abstract final class PhoneInput {
  static String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  /// Full international number as digits only (e.g. 8801…, 919…).
  static String apiPayload(String nationalDigits, PhoneCountry country) {
    var d = digitsOnly(nationalDigits);
    if (country.iso == 'BD') {
      if (d.length == 10 && d.startsWith('1')) return '880$d';
      if (d.length == 11 && d.startsWith('0')) return '880${d.substring(1)}';
      if (d.length == 13 && d.startsWith('880')) return d;
    }
    if (d.startsWith('0')) d = d.replaceFirst(RegExp(r'^0+'), '');
    return '${country.dialCode}$d';
  }

  static bool validNational(String national, PhoneCountry country) {
    final d = digitsOnly(national);
    if (d.isEmpty) return false;
    if (country.iso == 'BD') {
      return RegExp(r'^1[3-9]\d{8}$').hasMatch(d);
    }
    return d.length >= country.nationalMinLength && d.length <= country.nationalMaxLength;
  }

  static String? validationMessage(String national, PhoneCountry country, [AppStrings? l10n]) {
    final s = l10n ?? AppStrings.en;
    if (digitsOnly(national).isEmpty) return s.phoneEmpty;
    if (!validNational(national, country)) return s.phoneInvalid;
    return null;
  }
}
