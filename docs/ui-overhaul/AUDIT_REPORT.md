# UI/UX audit report — Phase 1

**Scope:** Code review + architecture mapping only. **No UI files modified.**

**Product:** PikoPe — landscape-first Flutter game (Pool, Ludo, Carrom, shop, online). Entry: `AppStartGate` → `LoadingScreen` → `DuelHomeScreen`.

---

## Executive summary

The app has a **strong visual identity** (dark hall, gold rim panels, custom game art) centered on `lib/core/duel_ui.dart`. Most lobby/game selection screens use **`DuelCanvas` (1600×900) scaled with `FittedBox`**, which keeps layout stable but is **not adaptive responsive design** — it uniform-scales, which can make text/icons small on narrow landscape phones and large empty margins on desktop web.

**Three parallel UI stacks** coexist: `DuelCanvas` + absolute `Positioned` layouts, `PageFrame` (settings/online/legal), and legacy `HomeScreen`/`LobbyScreen` poker flow. **Button components are duplicated** (`GameButton`, `DuelButton`, `NavTile`, top icons) with overlapping roles.

**No CRITICAL “unusable” screens** were identified from static analysis; primary risks are **consistency**, **small-target readability after scale**, and **web viewport** behavior outside the fixed canvas.

---

## Design system (current state)

| Area | Location | Issues |
|------|----------|--------|
| Colors | `DuelColors` in `duel_ui.dart`, `AppColors` in `app_theme.dart` | Two palettes; no single token file |
| Typography | `AppText` in `app_theme.dart` | Mixed with inline `TextStyle` (e.g. login) |
| Spacing / radii | Ad hoc per screen | Home/bet level use hardcoded `Positioned(left/top/width)` |
| Buttons | `GameButton`, `DuelButton`, `NavTile`, `Icon` taps | Different heights (42–92px logical in design coords) |
| Panels | `duelPanel`, `panelDecoration`, `SectionCard` | Similar look, different APIs |
| Dialogs | `showDuelDialog`, `showDuelMessage` | Scaled via DuelCanvas math — good for consistency, needs breakpoint review |

**Recommendation (Phase 2):** Add `lib/core/design/` tokens; map existing `DuelColors`/`AppText` into tokens **without visual breaking change** in first pass.

---

## Responsive / layout

| Priority | Finding | Where |
|----------|---------|--------|
| **HIGH** | Fixed **1600×900** design surface + `FittedBox` = scale-only “responsive” | `DuelCanvas` |
| **HIGH** | Heavy use of **absolute positioning** (e.g. home bottom nav at `top: 722`) | `duel_home_screen.dart`, `bet_level_screen.dart` |
| **MEDIUM** | `PageFrame` maxWidth paths differ from DuelCanvas screens | settings, online, leaderboard |
| **MEDIUM** | Web: portrait allowed + overlays; canvas still scales | `web_play.dart` |
| **MEDIUM** | Login / forgot password use **non–DuelCanvas** layout | `login_screen.dart` |
| **LOW** | `DuelPage` back button position varies by `showShortcuts` | `duel_chrome.dart` |

**Breakpoint gap:** No shared breakpoints; `web_play` uses `shortestSide < 720` only for hints.

---

## Screen-specific notes (sample; full list in SCREEN_INVENTORY)

| ID | Screen | Priority | Notes |
|----|--------|----------|-------|
| S-20 | DuelHomeScreen | MEDIUM | Dense positioned layout; side tiles + 3 game cards + bottom nav |
| S-30 | BetLevelScreen | MEDIUM | Horizontal carousel; nav row similar to home |
| S-50 | ShopScreen | MEDIUM | Tabs, transfer, deposit — complex; PageFrame vs Duel mix |
| S-60 | SettingsScreen | MEDIUM | Long form; PageFrame; challenge toggles |
| S-13 | LoginScreen | MEDIUM | Large typography (32/46); different shell from lobby |
| S-12 | LoadingScreen | LOW | Recently added game preview cards — aligned with brand |
| S-15 | CreateProfileScreen | LOW | **Orphan** — no navigation references |
| S-24 / S-35 / S-43 | Legacy poker | LOW | Test/legacy paths only |

---

## Dialogs & overlays

- **13** dialog/overlay patterns documented (see inventory D-01–D-13).
- Incoming challenge + not-enough-balance are **high-traffic** and must stay function-identical in redesign.
- Match overlays (`GameRevealOverlay`, `JackpotWheelOverlay`, `DuelResultOverlay`) are **game-critical** — Phase 4 touch only with gameplay QA.

---

## Code quality baseline (pre-overhaul)

| Check | Result (2026-11-01 session baseline) |
|-------|--------------------------------------|
| `flutter analyze lib` | **3 info** (`unnecessary_underscores` in 3 files) — pre-existing |
| `flutter test` | **114 pass, 1 fail** — `widget_test.dart` pool home test (pre-existing) |
| `flutter build apk --release` | Success (local) |
| `flutter build web` (pikope-web) | Success (local) |

---

## Regression risks for future phases

1. **Shared widgets:** `DuelCanvas`, `DuelTopBar`, `NavTile`, `GameCard`, `showDuelDialog` — wide blast radius.
2. **Auth / guest-first flows** — UI must not reintroduce login-at-start.
3. **Shop / ZiniPay / transfer** — financial UI; copy and callbacks frozen.
4. **Online rejoin** (`resumeActiveOnlineMatch`) — navigation stack sensitive.

---

## Priority backlog (for ROADMAP)

| Priority | Theme | Phase hint |
|----------|-------|------------|
| CRITICAL | — | None identified statically |
| HIGH | Canvas scaling vs true breakpoints; touch targets on small landscape | 2, 3, 7 |
| HIGH | Unify buttons/cards/dialog chrome | 2, 3 |
| MEDIUM | Login/settings/pageframe alignment with lobby | 2, 5, 6 |
| MEDIUM | Shop + bet level spacing/alignment pass | 3, 6 |
| LOW | Orphan screens (CreateProfile) product decision | 6 or drop |
| LOW | Legacy HomeScreen/LobbyScreen visual parity or isolation | 6 |

---

## Verification (Phase 1)

| Level | Status |
|-------|--------|
| 1 analyze | Recorded baseline (3 info, pre-existing) |
| 2 test | Not re-run this phase (use session baseline above) |
| 3–6 visual/build | **NOT VERIFIED** — audit is documentation-only |
