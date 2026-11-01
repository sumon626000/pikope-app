# UI overhaul roadmap

Phases follow `.cursor/rules/ui-overhaul.mdc`. **One phase at a time; user approval between phases.**

---

## Phase 1 — Audit ✅ (this document set)

- Deliverables: `SCREEN_INVENTORY.md`, `AUDIT_REPORT.md`, `ROADMAP.md`, `PROGRESS.md`
- **No UI code changes**

---

## Phase 2 — Design system

**Goal:** `lib/core/design/` (or equivalent) as single source of truth; thin wrappers so existing screens compile.

**Tasks:**

1. Token files: color, type scale, spacing (4/8 grid), radii, elevation/shadows, icon sizes.
2. Document mapping: `DuelColors` → tokens, `AppText` → tokens (deprecate gradually, no big-bang rename).
3. Standardize **one primary button** spec (height, min width, label style) — wrap `DuelButton` / align `GameButton`.
4. Standardize **card** spec (game card, nav tile, section panel).
5. Dialog chrome spec aligned with `showDuelDialog` scaler.
6. Breakpoint constants: phone landscape, tablet, desktop web (width/height thresholds).

**Out of scope:** Rewriting individual screens (Phase 3+).

**Exit criteria:** Tokens + 2–3 reference components; analyze clean; no visual change required yet (optional golden stub).

---

## Phase 3 — Home / main / menu / selection

**Screens (priority order):**

1. S-20 DuelHomeScreen  
2. S-21 PoolHubScreen, S-22 LudoLobby, S-23 CarromLobby  
3. S-30 BetLevelScreen  
4. S-31 MatchmakingScreen (waiting UI only)  
5. S-12 LoadingScreen (polish only if needed)

**Focus:** Replace fragile `Positioned` clusters with structured layouts where possible **without changing navigation callbacks**. Use Phase 2 tokens.

---

## Phase 4 — Gameplay UI

**Screens:**

- S-40 PoolScreen, S-41 LudoScreen, S-42 CarromScreen  
- S-43 GameScreen (legacy poker) — minimal unless still shipped  
- D-12 match overlays (result, jackpot, reveal)

**Constraint:** No rule/scoring/timer logic changes. HUD layout and controls spacing only.

---

## Phase 5 — Profile / settings / sound

**Screens:**

- S-60 SettingsScreen  
- S-13 LoginScreen, S-14 ForgotPasswordScreen, D-01 auth prompt  
- S-34 AccountScreen  
- Audio toggles / UX in settings (UI only)

**Align** PageFrame screens with design system while keeping forms functional.

---

## Phase 6 — Remaining screens

**Include:**

- Economy: S-50 Shop, S-51 ZiniPay, S-52–S-55 items/cues/boards/tutorials  
- Social/data: S-61–S-65 leaderboard, history, refer, notices, notifications  
- Online: S-32–S-33, S-36–S-38 challenge flow  
- Info: S-66 HowToPlay, S-67 Legal  
- Dialogs D-02–D-11 not covered earlier  
- W-01 HTML splash (coordinate with `pikope-web/web/index.html`)  
- Orphan/legacy decision: S-15, S-24, S-35  

---

## Phase 7 — Responsive testing

- Widget/golden tests at: 640×360, 800×360, 915×412, 1280×800, 1920×1080 (landscape first).  
- Web Chrome smoke; Android device smoke.  
- Fix HIGH overflow/clipping issues only; log MEDIUM/LOW polish.

---

## Phase 8 — Final audit & production readiness

- Full regression checklist (master rules).  
- Release APK + web build.  
- `PROGRESS.md` 100% verified or explicit exceptions.  
- Production-readiness report in `docs/ui-overhaul/FINAL_REPORT.md` (to be created in Phase 8).

---

## Suggested order of shared refactors

1. `DuelCanvas` / scaler behavior (document safe zones; optional adaptive padding) — **discuss before changing**  
2. `DuelTopBar` + `NavTile`  
3. `GameCard` + `HomeBanner`  
4. `showDuelDialog` / `showDuelMessage`  
5. `PageFrame` alignment layer  
