import '../l10n/strings.dart';

/// Bangladesh mobile input: user types 10 digits after +880 (1XXXXXXXXX).
class BdPhone {
  /// Sends `phone` to the API: local 10 digits, or full +880 / 880 form.
  static String apiPayload(String localOrFull) {
    final d = localOrFull.replaceAll(RegExp(r'\D'), '');
    if (d.length == 10 && d.startsWith('1')) return d;
    if (d.length == 11 && d.startsWith('0')) return d.substring(1);
    if (d.length == 13 && d.startsWith('880')) return d.substring(3);
    return d;
  }

  static bool validLocal(String local) {
    final d = local.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^1[3-9]\d{8}$').hasMatch(d);
  }

  static String? validationMessage(String local, [AppStrings? l10n]) {
    final s = l10n ?? AppStrings.en;
    if (local.replaceAll(RegExp(r'\D'), '').isEmpty) {
      return s.phoneEmpty;
    }
    if (!validLocal(local)) {
      return s.phoneInvalid;
    }
    return null;
  }
}
