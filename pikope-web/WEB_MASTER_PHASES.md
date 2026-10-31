# PikoPe Web — master plan (APK + Web, one admin)

Same backend (`adminnew.pikope.com`), same users/coins/rooms. Mobile APK stays in repo root; browser client lives in **`pikope-web/`** (local now, deploy later e.g. `play.pikope.com`).

---

## Phase 0 — Local shell (this folder)

- [x] Separate Flutter project `pikope-web/` with path dependency on `../` (`billiard_poker`).
- [x] Web entry `lib/main.dart` → `bootstrapPikope(mobileShell: false)`.
- [x] `setup-local.ps1` — asset junction + `flutter pub get`.
- [x] First green `flutter build web` (local; run `build-local.ps1`).

**Exit:** Chrome/local web opens lobby (even if some tabs fail).

**Status: COMPLETE (local).** Run `run-local.ps1` to open the app in Chrome.

---

## Phase 1 — Build & platform plumbing

- [x] Web HTTP client (`BrowserClient`; IO + cert pin on mobile only).
- [x] Web-safe auth token storage (secure storage + prefs fallback on web).
- [x] APK update gate skipped on web (`app_update_stub.dart`).
- [x] API CORS: `CORS_ORIGIN` comma-separated origins (`backend/src/Cors.php`).
- [x] `.env` / `API_BASE_URL` via `run-local.ps1` → `../.env`.

**Exit:** Login/guest, `/me`, lobby load from production or staging API.

**Status: CODE COMPLETE.** Deploy backend + set `CORS_ORIGIN` on Hostinger (include `http://localhost:PORT` for Chrome dev).

**Server example:**
```env
CORS_ORIGIN=http://localhost:7357,http://127.0.0.1:7357,https://play.pikope.com
```
After deploy, run `pikope-web/run-local.ps1` and sign in — lobby should load.

---

## Phase 2 — Shop & economy (parity)

- [x] ZiniPay on web: same-tab checkout + `WEB_APP_URL` return redirect + `resolveZiniPayReturnIfAny`.
- [x] Transfer + redeem + history (shared UI; Phase 1 CORS).
- [x] Coin tutorials on web: open YouTube in new browser tab.
- [x] Manual deposit + coin-pack buy (shared API).

**Exit:** Same coin balance on APK and web for one account.

**Status: CODE COMPLETE.** Set server `WEB_APP_URL` (e.g. `http://localhost:7357` for dev) and deploy `ZiniPay.php`.

**Server:**
```env
WEB_APP_URL=http://localhost:7357
```
After ZiniPay pay, browser returns to web app and credits via `/deposit/zinipay/finish`.

---

## Phase 3 — Online play (core games)

- [x] Same online routes (matchmaking, rooms, challenges) — shared `lib/`.
- [x] WebSocket URL `ws`→`wss` on HTTPS pages; HTTP poll fallback if WS down.
- [x] Pool + carrom: tap/drag aim (mouse + touch on web).
- [x] `WebPlayScope` landscape hint on portrait browser.

**Exit:** APK user can play web user in same room.

**Status: CODE COMPLETE.** Ops: expose **`WS_PUBLIC_URL=wss://…`** (reverse-proxy to `bin/ws-server.php`). Without WS, online still works via HTTP polling (slightly slower).

---

## Phase 4 — Polish & deploy

- [x] PWA manifest + favicon/icons (`generate-web-icons.ps1`).
- [x] First-load splash in `web/index.html` (removed on `flutter-first-frame`).
- [x] Web audio: lazy load (no full WAV warm-up on `kIsWeb`).
- [x] `deploy-hostinger.ps1` → release build + zip; `DEPLOY.txt` Hostinger steps.
- [ ] Firebase web push (optional — skipped; use same admin notices/inbox).
- [ ] CDN (optional ops — Cloudflare in front of static host).

**Exit:** Public web URL, same admin, both clients in store/browser.

**Status: READY TO UPLOAD.** Run `.\deploy-hostinger.ps1`, upload zip to `play.pikope.com` (or `/play/`), set CORS + WEB_APP_URL on API.

---

## Phase 5 — Hardening

- [x] Same API throttles as APK (no web bypass — server-side).
- [x] `smoke-web.ps1` — widget tests + web unit smoke + `verify-api-web.ps1` (health/CORS/ws).
- [x] `SMOKE_CHECKLIST.txt` — manual Chrome + mobile browser QA.
- [x] `RELEASE.txt` — git tag `pikope-web-1.0.0+1`, rollback, monitoring notes.
- [x] Web package version **1.0.0+1**.

**Exit:** Release tagged, smoke green, rollback path documented.

**Status: COMPLETE (local tooling).** Run `.\smoke-web.ps1` before each deploy.

---

## Phase 6 — Go live (ops)

- [x] Single checklist: `GO_LIVE.txt` (build → upload → API env → DNS → smoke → tag).
- [ ] Production upload + API `.env` on Hostinger (your step).
- [ ] Manual `SMOKE_CHECKLIST.txt` on live URL (your step).
- [ ] Git tag `pikope-web-1.0.0+1` after push (see `RELEASE.txt`).

**Exit:** `https://play.pikope.com` (or your URL) serves the web client; APK + web share one backend.

**Status: REPO READY — deploy when DNS/API env are set.**

---

## Folder layout

```
duelx/                 ← APK (Android), shared lib + assets
  lib/
  assets/
  backend/             ← one admin + API (unchanged)
pikope-web/            ← Web-only Flutter project (this folder)
  lib/main.dart
  web/
  setup-local.ps1
  run-local.ps1
```

**Do not duplicate game logic in `pikope-web/lib`** — only entry + web-specific shims (add `pikope-web/lib/src/` later if needed).
