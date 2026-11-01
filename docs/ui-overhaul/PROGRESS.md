# UI overhaul progress

Update at end of each phase. Status: **Not started** | **Redesigned** | **Verified** | **Deferred**

Verification levels: L1 analyze | L2 test | L3 multi-size | L4 device | L5 web run | L6 build

---

## Summary

| Metric | Value |
|--------|------:|
| Phase | **8 — Final audit** ✅ **Completed** (awaiting your approval) |
| Production routes redesigned | **35 / 35** (in-scope) |
| Legacy/orphan routes | **4 deferred** (S-15, S-24, S-35, S-43) |
| Dialogs/overlays redesigned | **11 / 13** (D-06 partial, D-13 unchanged) |
| Design primitives (P-xx) | **11 / 11** |
| Overall UI overhaul | **~88%** (see `FINAL_REPORT.md`) |

**Reports:** `AUDIT_REPORT.md` · `RESPONSIVE_REPORT.md` · `FINAL_REPORT.md`

---

## Routes (S-xx)

| ID | Screen | Status | Verification | Notes |
|----|--------|--------|--------------|-------|
| S-10 | AppStartGate | Acceptable | L1 | Minimal spinner — bootstrap only |
| S-11 | MandatoryUpdateScreen | Acceptable | L1 | Android APK gate — functional |
| S-12 | LoadingScreen | Redesigned | L3 | `LoadingSplashBody` in L3 tests |
| S-13 | LoginScreen | Redesigned | L3 | Scroll + scaleDown (Phase 7) |
| S-14 | ForgotPasswordScreen | Redesigned | L1 | |
| S-15 | CreateProfileScreen | Deferred | — | Orphan |
| S-20 | DuelHomeScreen | Redesigned | L3 | L3 + device overflow fix (Phase 3/7) |
| S-21 | PoolHubScreen | Redesigned | L3 | |
| S-22 | LudoLobbyScreen | Redesigned | L1 | |
| S-23 | CarromLobbyScreen | Redesigned | L1 | |
| S-24 | HomeScreen (legacy) | Deferred | — | Tests only |
| S-30 | BetLevelScreen | Redesigned | L1 | |
| S-31 | MatchmakingScreen | Redesigned | L1 | |
| S-32 | OnlineLobbyScreen | Redesigned | L1 | `PageFrame` |
| S-33 | RoomScreen | Redesigned | L1 | |
| S-34 | AccountScreen | Redesigned | L1 | |
| S-35 | LobbyScreen (legacy) | Deferred | — | |
| S-36 | ChallengeScreen | Redesigned | L1 | `DuelPage` |
| S-37 | ChallengeGamePickScreen | Redesigned | L1 | |
| S-38 | ChallengeWaitScreen | Redesigned | L1 | |
| S-40 | PoolScreen | Redesigned | L1 | |
| S-41 | LudoScreen | Redesigned | L1 | |
| S-42 | CarromScreen | Redesigned | L1 | |
| S-43 | GameScreen (legacy) | Deferred | — | |
| S-50 | ShopScreen | Redesigned | L1 | |
| S-51 | ZiniPayCheckoutScreen | Redesigned | L1 | |
| S-52 | ItemsScreen | Redesigned | L1 | |
| S-53 | CuesScreen | Redesigned | L1 | |
| S-54 | BoardShopScreen | Redesigned | L1 | |
| S-55 | CoinTutorialPlayerScreen | Redesigned | L1 | |
| S-60 | SettingsScreen | Redesigned | L1 | |
| S-61 | LeaderboardScreen | Redesigned | L1 | |
| S-62 | HistoryScreen | Redesigned | L1 | |
| S-63 | ReferScreen | Redesigned | L1 | |
| S-64 | NoticesScreen | Redesigned | L1 | |
| S-65 | NotificationsScreen | Redesigned | L1 | |
| S-66 | HowToPlayScreen | Redesigned | L3 | |
| S-67 | LegalScreen | Redesigned | L1 | |

## Shells & web (S-01–S-06, W-01)

| ID | Name | Status | Verification |
|----|------|--------|--------------|
| S-01–S-06 | App shells | Acceptable | L1 | Behavior-only; no visual overhaul |
| W-01 | HTML splash | Redesigned | L1 | `pikope-web/web/index.html` |

## Dialogs / overlays (D-xx)

| ID | Name | Status | Verification |
|----|------|--------|--------------|
| D-01 | Auth prompt | Redesigned | L1 | |
| D-02 | Daily bonus | Redesigned | L1 | |
| D-03 | Home choosers | Redesigned | L1 | |
| D-04 | Practice mode | Redesigned | L1 | |
| D-05 | Not enough balance | Redesigned | L1 | |
| D-06 | Incoming challenge | Partial | L1 | Banner; optional token pass |
| D-07 | Logout confirm | Redesigned | L1 | |
| D-08 | Cue purchase | Redesigned | L1 | `showDuelDialog` |
| D-09 | Transfer confirm | Redesigned | L1 | `showDuelDialog` |
| D-10 | Bet level messages | Redesigned | L1 | |
| D-11 | Offline practice | Redesigned | L1 | |
| D-12 | Match overlays | Redesigned | L1 | |
| D-13 | Web hints | Acceptable | L1 | Unchanged overlays |

## Primitives (P-xx)

| ID | Name | Status | Verification |
|----|------|--------|--------------|
| P-01 | DuelCanvas | Redesigned | L1 |
| P-02 | DuelPage | Redesigned | L1 | |
| P-03 | PageFrame | Redesigned | L1 | |
| P-04 | DuelTopBar | Redesigned | L1 | `duel_chrome.dart` |
| P-05 | GameCard / NavTile | Redesigned | L1 | |
| P-06 | Buttons | Redesigned | L1 | |
| P-07 | Dialog system | Redesigned | L1 | |
| P-08 | LobbyScaffold | Redesigned | L1 | |
| P-09 | DesignGameplay | Redesigned | L1 | |
| P-10 | DesignAuth | Redesigned | L1 | |
| P-11 | DesignSecondaryPage | Redesigned | L1 | |

## Phase completion log

| Phase | Status |
|-------|--------|
| 1 Audit | ✅ |
| 2 Design system | ✅ |
| 3 Home / menu | ✅ |
| 4 Gameplay UI | ✅ |
| 5 Profile / settings / auth | ✅ |
| 6 Remaining screens | ✅ |
| 7 Responsive testing | ✅ |
| 8 Final audit | ✅ |
