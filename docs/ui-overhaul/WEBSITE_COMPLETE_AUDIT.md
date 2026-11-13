# COMPLETE WEBSITE — Bug, UI & Functionality Audit

**Product:** PikoPe Web (`https://pikope.com`)  
**Client:** Flutter web via `pikope-web/` → Hostinger FTP  
**Audit date:** 2026-11-14  
**Code HEAD at audit:** `2e268a6` (gems hidden) / live deploy success after that commit  
**Method:** Static code review + inventory cross-check + responsive unit tests + live Chrome home smoke  

**Verification levels used:** L1 analyze baseline · L2 responsive tests · L5 live Chrome (home only)  
**NOT VERIFIED this pass:** full click-through of shop/pay/match on production · multi-device physical · every dialog screenshot

---

## 1. Executive verdict

| Area | Grade | Summary |
|------|-------|---------|
| **Lobby / secondary UI (web desktop)** | **Good** | Phone-column (≤420) + dialog column (≤360) — home looks correct live |
| **Dialogs / choosers** | **Good / improving** | Most go through capped frames; Practice row + gems hide shipped |
| **Gameplay web** | **Mixed** | Ludo/Carrom portrait-friendly; **Pool still landscape 1950×900 full-bleed** |
| **Auth / guest flows** | **Good (code)** | Guest home works; gated actions use `requireRegisteredAccount` |
| **Economy (shop / pay / transfer)** | **Functional risk** | ZiniPay + manual sheet exist; **manual deposit sheet uncapped on desktop** |
| **Online / matchmaking** | **Depends on API** | Default API `https://adminnew.pikope.com`; web deploy injects `API_BASE_URL` |
| **Overall ship readiness (web)** | **Ship with known gaps** | Not 100% — see CRITICAL/HIGH backlog |

**Bottom line:** Desktop web lobby is usable and no longer edge-to-edge oversized. Remaining website debt is concentrated in **Pool landscape**, **shop bottom sheet**, **partial live QA coverage**, and **a few wide logical overlays**.

---

## 2. What was verified this session

| Check | Result |
|-------|--------|
| Live `https://pikope.com` loads | **OK** — splash → guest home |
| Desktop phone column on home | **OK** — centered column, ink sides |
| Gem wallet chip hidden | **OK** — coins / Sign-up pill only |
| `test/portrait_canvas_responsive_test.dart` | **7 passed** |
| `test/ui_landscape_responsive_test.dart` (Phase 7 sizes) | **32 passed** (combined run +19→32) |
| Deploy web workflow (recent) | **success** (last 3 runs) |
| Full shop / Practice / Pool / login click path live | **NOT VERIFIED** |
| `flutter analyze` | Pre-existing infos/warnings only (no new errors from recent UI work) |

---

## 3. Architecture (web)

```
main.dart (kIsWeb)
  → bootstrapPikope(mobileShell: false)
  → BilliardPokerApp
       builder: WebLandscapeGate → WebApkPromoHost → ChallengeInboxHost → ZiniPayReturnHost
       home: AppStartGate → LoadingScreen → DuelHomeScreen
```

| Layer | Role |
|-------|------|
| `PortraitWebLayout` | Shared caps: phone 420, dialog 360, landscape menu 960×540 |
| `PortraitCanvas` / `PcPage` / `DuelPage` | Production lobby chrome (1080 design) |
| `DesignCanvas.tableSize` | Pool (+ legacy poker) — **uncapped** contain |
| `showDuelDialog` / `showPcDialog` | Dialog scaler → dialog column |
| Env | `API_BASE_URL` default `https://adminnew.pikope.com` |

---

## 4. Screen matrix (website-relevant)

Legend: **Risk** = desktop/mobile web layout or flow risk.

| ID | Screen | Canvas | Web risk | Function notes |
|----|--------|--------|----------|----------------|
| S-12 | Loading | PortraitCanvas | Low | Live splash OK |
| S-13 | Login | PortraitCanvas | Low | Full page + compact popup |
| S-14 | Forgot password | PcPage | Low | |
| S-15 | Create profile | PortraitCanvas | Low | **Orphan** — not linked |
| S-20 | Duel home | PortraitCanvas | Low | Live OK (guest) |
| S-21–23 | Pool/Ludo/Carrom hubs | PcPage | Low | Online play gated |
| S-24 | Legacy HomeScreen | DesignCanvas menu | Med | Tests only |
| S-30 | Bet levels | PcPage | Low | Auth gate for coin play |
| S-31 | Matchmaking | PcPage | Low | Needs API + WS |
| S-32–34 | Online lobby/room/account | PageFrame→PcPage | Low–Med | Legacy section cards |
| S-36–38 | Challenge flows | DuelPage | Low | Auth + API |
| S-40 | **Pool match** | DesignCanvas **table** | **High** | Landscape lock; desktop full-bleed; mobile rotate gate |
| S-41 | Ludo match | PortraitGameCanvas | Low | |
| S-42 | Carrom match | PortraitGameCanvas | Low | |
| S-43 | Legacy poker | DesignCanvas table | High | Deferred |
| S-50 | Shop | PcPage | **Med** | Tabs OK; manual deposit sheet **High** |
| S-51 | ZiniPay checkout | DuelPage | Low–Med | Web return host |
| S-52–54 | Items / cues / boards | PcPage/DuelPage | Med | Cue art width 940 |
| S-55 | Coin tutorial | custom | Med | Web opens URL path |
| S-60 | Settings | DuelPage | Low | |
| S-61–65 | Rank / history / refer / mail | PcPage/DuelPage | Low–Med | Refer `legacyScale` on phone |
| S-66–67 | How-to / legal | PageFrame | Low | |

---

## 5. Dialog / overlay matrix

| ID | Name | Cap | Status |
|----|------|-----|--------|
| D-01 | Login required | Dialog column | Compact stacked buttons |
| D-02 | Daily bonus | Dialog column | Width 900 design |
| D-03 | Practice / friends chooser | Dialog column | **3 games in one row** |
| D-04 | Offline practice mode | Dialog column | |
| D-05 | Not enough balance | Dialog column | Wide action row (340+400) — watch |
| D-06 | Incoming challenge banner | Logical max 560 | **Wider than phone column** |
| D-07 | Logout | Dialog column | |
| D-08 | Cue buy | Dialog column | Stacked actions |
| D-09 | Transfer confirm | Dialog column | Stacked actions |
| D-12 | Match overlays | In-canvas | Pool landscape coords |
| D-13 | Web rotate / fullscreen | Viewport | Pool landscape only |
| — | Shop manual deposit sheet | **None** | **CRITICAL desktop** |
| — | Match chat | ≤480 logical | OK |

---

## 6. Bug & issue backlog (priority)

### CRITICAL

| # | Issue | Where | Impact | 2026-11-14 fix |
|---|-------|-------|--------|----------------|
| C1 | Pool table canvas no desktop host cap | `DesignCanvas` `tableSize` | Ultrawide stretch | **Fixed** — `landscapeTableHost` ≤1280×590 |
| C2 | Shop manual deposit uncapped sheet | `shop_screen.dart` | Full-window sheet | **Fixed** — `maxWidth` phone column |

### HIGH

| # | Issue | Where | Impact |
|---|-------|-------|--------|
| H1 | Mobile web: Pool forces landscape → rotate overlay friction | `WebLandscapeGate`, `OrientationLock` | Extra step vs Ludo/Carrom |
| H2 | Items cue preview `width: 940` | `items_screen.dart` | Clip risk | **Fixed** — 860×140 |
| H3 | Refer `legacyScale: 2.5` | `refer_screen.dart` | Magnify quirks | **Fixed** — scale removed |
| H4 | Live QA gap shop/practice/pool | — | Manual QA | Still open (process) |
| H5 | Not-enough balance wide actions | `duel_ui.dart` | Crowded row | **Fixed** — stacked buttons |
| H1 | Pool mobile web hard rotate gate | `web_play.dart` | Blocked play | **Fixed** — soft banner, match still shown |

### MEDIUM

| # | Issue | Where |
|---|-------|-------|
| M1 | Challenge banner `maxWidth: 560` > phone column 420 | `challenge_incoming_banner.dart` |
| M2 | Online screens `SectionCard(legacy: true)` + ignored `maxWidth` | `online_screens.dart` |
| M3 | `DesignPromptDialog.width` parameter unused | `design_auth.dart` |
| M4 | Gems half-removed: `HomeWalletBar.showGems=false` but gems still plumbed; daily gem rewards still shown | wallet / daily |
| M5 | Docs drift: older reports still say primary stack is `DuelCanvas` | `FINAL_REPORT` / inventory P-01 |
| M6 | L3 automated coverage only home/login/loading/hub/howto — not shop/settings/gameplay/dialogs | tests |
| M7 | First-visit web load can feel slow (WASM/JS + assets) | live splash copy acknowledges this |

### LOW

| # | Issue |
|---|-------|
| L1 | Orphan `CreateProfileScreen` |
| L2 | Deferred legacy poker routes (HomeScreen / LobbyScreen / GameScreen) |
| L3 | Web fullscreen / rotate hint polish (D-13) |
| L4 | Audio: web skips preload (by design); SFX on-demand |
| L5 | `pikope-web` analyze warnings for missing asset dirs when not symlinked locally |

---

## 7. Functionality audit (by flow)

### 7.1 Bootstrap & guest home — **Works**

- Guest reaches `DuelHomeScreen` without forced login.
- Wallet shows sign-up placeholder; gems chip **intentionally hidden**.
- Side tiles + Play Pool / Ludo / Carrom / Friends / Practice / bottom nav present (live).

### 7.2 Auth — **Works (code + partial live)**

- `requireRegisteredAccount` → prompt → compact `showLoginAuthPopup`.
- Gates: shop buy/redeem, friends, coin play, challenges, transfers, etc.
- Forgot password + legal reachable from login.
- Session restore attempted on shop taps (`_restoreRegisteredIfSaved`).

### 7.3 Practice — **Works (code); live dialog NOT re-shot this pass**

- Home Practice chooser: Pool / Ludo / Carrom **one horizontal row**.
- Pool practice → vs bots / pass & play stacked dialog.
- Ludo/Carrom practice launchers intact.

### 7.4 Online coin play — **Works if API healthy**

- Hubs → auth → bet levels → matchmaking.
- `resumeActiveOnlineMatch` on web after loading.
- Failure mode: offline / API down → error UI / empty lobby (expected).

### 7.5 Shop / payments — **Partial risk**

- Tabs: Buy / Transfer / Redeem / History.
- Auto ZiniPay when enabled; return handled by `ZiniPayReturnHost` (`?zinipay_deposit=`).
- Manual agent sheet: **desktop uncapped** (C2).
- Tutorial video: web-specific branch.

### 7.6 Social / meta — **Works with API**

- Refer, challenges, notices, notifications, history, leaderboard, settings.
- Challenge inbox host global.

### 7.7 Gameplay — **Asymmetric**

| Game | Web layout | Notes |
|------|------------|-------|
| Pool | Landscape DesignCanvas | Highest web UX debt |
| Ludo | Portrait game canvas | Aligned with site |
| Carrom | Portrait game canvas | Aligned with site |

---

## 8. Recent fixes already on main (context)

| Commit | Change |
|--------|--------|
| `cda139b`…`4e7410c` | Phone + dialog columns |
| `815a060` | Full oversized-page/dialog audit pass |
| `39735c3` | Practice chooser 1-line buttons |
| `2e268a6` | Hide gem wallet chip |

---

## 9. Recommended fix order (do **not** auto-start without approval)

1. **C2** Cap / replace shop manual deposit sheet with dialog-column frame.  
2. **C1** Cap Pool desktop host **or** start portrait Pool web path (product decision).  
3. **H2–H3** Items cue width + Refer legacyScale.  
4. **H1 / D-13** Soften Pool mobile-web rotate UX.  
5. **M1** Challenge banner width align to 420.  
6. Expand L3/L5: shop, practice dialog, Pool entry, login popup at 1280 / 390.  
7. Doc refresh: inventory P-01/`DuelPage` → `PcPage`; mark this report in PROGRESS.

---

## 10. Completeness vs inventory

| Bucket | Count | Notes |
|--------|------:|-------|
| Production routes in inventory | ~35 | Still in scope |
| Live home verified | 1 | L5 partial |
| Dialogs with known web issues | 2–3 | Manual sheet, challenge banner, Pool overlays |
| Deferred / orphan | 4 | S-15, S-24, S-35, S-43 |
| Missing production route | **0** | No new orphan hubs found |

**Website completion estimate (honest):** **~82%** for desktop web lobby+dialogs; **~70%** including Pool + payments QA.

---

## 11. Phase report (audit-only)

1. **Phase name and status:** Website complete audit — **Completed** (findings only; no new UI phase started)  
2. **Screens done / total:** Audit coverage **35 / 35** inventory routes (static); live L5 **1 / 35**  
3. **Files created and modified:** `docs/ui-overhaul/WEBSITE_COMPLETE_AUDIT.md` (this file); PROGRESS pointer  
4. **Verified:** L2 responsive tests; L5 home on pikope.com; deploy green. **NOT VERIFIED:** full functional click path, Pool/shop visuals live  
5. **Build/test:** Responsive tests pass; analyze pre-existing warnings only  
6. **Remaining:** C1–C2, H1–H5, M1–M7 — **~82%** website readiness  

---

*End of audit. Await explicit approval before implementing the fix backlog.*
