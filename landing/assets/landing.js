/** Play Store–style landing: wire APK CTA from admin /landing/public. */
(function () {
  const cfg = window.PIKOPE_LANDING || {
    apiBase: 'https://adminnew.pikope.com',
    fallbackApk: '',
    defaultLang: 'bn',
  };

  function enableDownload(url) {
    const btn = document.getElementById('download-btn');
    const hint = document.getElementById('download-hint');
    if (!btn || !url) return;
    btn.href = url;
    btn.classList.remove('opacity-60', 'pointer-events-none');
    btn.removeAttribute('aria-disabled');
    if (hint) hint.classList.add('hidden');
  }

  async function load() {
    const base = String(cfg.apiBase || '').replace(/\/$/, '');
    // CI drops the fresh APK beside this page; use that first.
    let apkUrl = String(cfg.fallbackApk || '').trim();
    try {
      const res = await fetch(base + '/landing/public', { cache: 'no-store' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = await res.json();
      if (!apkUrl) apkUrl = String(data.apkUrl || '').trim();
      if (data.appIconUrl) {
        const icon = document.getElementById('landing-app-icon');
        if (icon) icon.src = data.appIconUrl;
      }
      const rating = data.stats && data.stats.rating;
      if (rating) {
        const el = document.getElementById('stat-rating-big');
        if (el) el.textContent = rating;
      }
    } catch (e) {
      console.warn('[PikoPe download landing]', e);
    }
    if (apkUrl && apkUrl !== '#') {
      enableDownload(apkUrl);
    }
  }

  load();
})();
