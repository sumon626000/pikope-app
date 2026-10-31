import 'package:web/web.dart' as web;

const _hideKey = 'pikope_web_apk_installed';

bool _androidBrowser() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('android');
}

bool webApkPromoPlatformEligible() => _androidBrowser();

bool webApkPromoUserHasInstalledApp() {
  if (web.window.localStorage.getItem(_hideKey) == '1') return true;
  if (web.window.matchMedia('(display-mode: standalone)').matches) return true;
  if (web.window.matchMedia('(display-mode: minimal-ui)').matches) return true;
  return false;
}

void webApkPromoMarkHasInstalledApp() {
  web.window.localStorage.setItem(_hideKey, '1');
}
