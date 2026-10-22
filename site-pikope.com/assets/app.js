(function () {
  const cfg = window.PIKOPE_LANDING || { apiBase: 'https://adminnew.pikope.com', fallbackApk: '', defaultLang: 'bn' };
  const UI = window.PIKOPE_I18N || { bn: {}, en: {} };
  const STORAGE_KEY = 'pikope_lang';

  const DEFAULTS = {
    defaultLang: 'bn',
    apkUrl: cfg.fallbackApk || '#',
    heroImageUrl: '',
    screenshots: [],
    stats: { rating: '4.8', reviews: '12K+', downloads: '500K+', rated: '18+' },
    updatedLabel: '',
    locales: {
      bn: {
        headline: 'দক্ষতার গেমিং',
        tagline: 'অনলাইন Pool, Ludo ও Carrom',
        apkLabel: 'দ্রুত ইনস্টল',
        aboutBody: 'PikoPe — দক্ষতা-ভিত্তিক গেমিং অ্যাপ।',
        features: ['অনলাইন ১ভি১', 'Pico coin', 'ফেয়ার প্লে'],
      },
      en: {
        headline: 'Skill gaming',
        tagline: 'Pool, Ludo & Carrom online',
        apkLabel: 'Fast install',
        aboutBody: 'PikoPe — skill-based gaming app.',
        features: ['Online 1v1', 'Pico coin', 'Fair play'],
      },
    },
  };

  let apiData = null;
  let lang = localStorage.getItem(STORAGE_KEY) || cfg.defaultLang || 'bn';
  if (lang !== 'bn' && lang !== 'en') lang = 'bn';

  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);

  function t(key) {
    const pack = UI[lang] || UI.bn || {};
    return pack[key] ?? (UI.en && UI.en[key]) ?? key;
  }

  function applyStaticI18n() {
    document.documentElement.lang = lang === 'bn' ? 'bn' : 'en';
    const meta = document.querySelector('meta[name="description"]');
    if (meta) meta.setAttribute('content', t('metaDescription'));
    $$('[data-i18n]').forEach((el) => {
      const key = el.getAttribute('data-i18n');
      if (key && el.id !== 'updated-label') el.textContent = t(key);
    });
    $$('.lang-switch button').forEach((btn) => {
      btn.classList.toggle('active', btn.getAttribute('data-lang') === lang);
    });
  }

  function localePack() {
    return { ...(apiData?.locales?.[lang] || DEFAULTS.locales[lang] || DEFAULTS.locales.bn) };
  }

  function setHeroBg(url) {
    const el = $('.bg-photo');
    if (el && url) el.style.backgroundImage = 'url("' + url.replace(/"/g, '\\"') + '")';
  }

  function setDownload(url, label) {
    const href = url && url !== '#' ? url : cfg.fallbackApk || '';
    const text = label || (lang === 'bn' ? 'দ্রুত ইনস্টল' : 'Fast install');
    const unavailable = t('apkUnavailable');
    ['#download-btn', '#download-footer'].forEach((sel) => {
      const el = $(sel);
      if (!el) return;
      const span = el.querySelector('.btn-label');
      if (href) {
        el.href = href;
        el.classList.remove('btn-install--disabled');
        el.removeAttribute('aria-disabled');
        if (span) span.textContent = text;
        el.onclick = null;
      } else {
        el.href = '#';
        el.classList.add('btn-install--disabled');
        el.setAttribute('aria-disabled', 'true');
        if (span) span.textContent = unavailable;
        el.onclick = (e) => e.preventDefault();
      }
    });
  }

  function renderFeatures(list) {
    const el = $('#features');
    if (!el) return;
    el.innerHTML = '';
    (list || []).slice(0, 6).forEach((text) => {
      const li = document.createElement('li');
      li.textContent = text;
      el.appendChild(li);
    });
  }

  function buildShots(urls) {
    const strip = $('#shot-strip');
    if (!strip) return;
    strip.innerHTML = '';
    const shots = (urls || []).filter(Boolean);
    if (shots.length === 0) {
      strip.innerHTML =
        '<div class="shot-placeholder card-panel"><img src="assets/pikope_logo.png" alt="" width="72"><p data-i18n="phScreens"></p></div>';
      const p = strip.querySelector('[data-i18n="phScreens"]');
      if (p) p.textContent = t('phScreens');
      return;
    }
    shots.forEach((src, i) => {
      const frame = document.createElement('div');
      frame.className = 'shot-frame';
      const img = document.createElement('img');
      img.src = src;
      img.alt = t('shotAlt') + ' ' + (i + 1);
      img.loading = i < 2 ? 'eager' : 'lazy';
      frame.appendChild(img);
      strip.appendChild(frame);
    });
  }

  function applyStats() {
    const s = apiData?.stats || DEFAULTS.stats;
    const set = (id, val) => {
      const el = document.getElementById(id);
      if (el && val) el.textContent = val;
    };
    set('stat-rating', s.rating);
    set('stat-reviews', s.reviews);
    set('stat-downloads', s.downloads);
    set('stat-rated', s.rated);
    set('rating-display', s.rating);
  }

  function applyDynamic() {
    const loc = localePack();
    document.title = 'PikoPe — ' + (loc.apkLabel || 'APK');
    const headline = $('#headline');
    const tagline = $('#tagline');
    const about = $('#about-body');
    if (headline) headline.textContent = loc.headline;
    if (tagline) tagline.textContent = loc.tagline;
    if (about) about.textContent = loc.aboutBody || loc.tagline;
    renderFeatures(loc.features);
    applyStats();
    const updated = $('#updated-label');
    if (updated) {
      updated.textContent = apiData?.updatedLabel || t('updatedDefault');
      updated.removeAttribute('data-i18n');
    }
    setDownload(apiData?.apkUrl || cfg.fallbackApk || '#', loc.apkLabel);
    setHeroBg(apiData?.heroImageUrl || '');
    buildShots(apiData?.screenshots || []);
    document.body.classList.remove('loading');
  }

  function setLang(next) {
    if (next !== 'bn' && next !== 'en') return;
    lang = next;
    localStorage.setItem(STORAGE_KEY, lang);
    applyStaticI18n();
    applyDynamic();
  }

  function initShare() {
    const btn = $('#btn-share');
    if (!btn) return;
    btn.addEventListener('click', async () => {
      const url = location.href;
      const title = 'PikoPe';
      try {
        if (navigator.share) {
          await navigator.share({ title, url });
          return;
        }
      } catch (_) {}
      try {
        await navigator.clipboard.writeText(url);
        btn.textContent = t('shareCopied');
        setTimeout(() => applyStaticI18n(), 2000);
      } catch (_) {}
    });
  }

  async function load() {
    document.body.classList.add('loading');
    $$('.lang-switch button').forEach((btn) => {
      btn.addEventListener('click', () => setLang(btn.getAttribute('data-lang')));
    });
    initShare();
    applyStaticI18n();

    const base = (cfg.apiBase || '').replace(/\/$/, '');
    try {
      const res = await fetch(base + '/landing/public', { cache: 'no-store' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      apiData = await res.json();
      if (!localStorage.getItem(STORAGE_KEY)) {
        lang = apiData.defaultLang === 'en' ? 'en' : 'bn';
      }
    } catch (e) {
      console.warn('[PikoPe landing]', e);
      apiData = { ...DEFAULTS, locales: DEFAULTS.locales };
    }
    applyStaticI18n();
    applyDynamic();
  }

  load();
})();
